-- TALLY — atomic expense / recurring creation
--
-- The client used to create an expense in two requests: insert the expense,
-- then insert its splits. If the second request failed (dropped connection,
-- closed tab), the expense survived with no splits: the payer was credited the
-- full amount and nobody owed it, so the group's balances stopped summing to
-- zero. Recurring templates had the same shape, and the daily tick then copied
-- the empty split set into a new broken expense every period.
--
-- create_expense / create_recurring do both inserts in one transaction and
-- re-check the splits-sum-to-amount invariant server-side, the same way
-- update_expense and import_expenses already do. The direct insert policies are
-- dropped so the RPCs are the only way in (SECURITY DEFINER paths — import,
-- the tick — are unaffected by RLS).
--
-- Separately, nothing checked that a payer or split member belongs to the
-- expense's group. A trigger now enforces that on every write path at once:
-- these RPCs, update_expense, import_expenses and process_due_recurring.

-- ---------------------------------------------------------------- membership
create or replace function assert_member_in_group()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_group  uuid;
  v_member uuid;
begin
  case tg_table_name
    when 'expenses', 'recurring_expenses' then
      v_group  := new.group_id;
      v_member := new.payer_member_id;
    when 'expense_splits' then
      select group_id into v_group from expenses where id = new.expense_id;
      v_member := new.member_id;
    when 'recurring_expense_splits' then
      select group_id into v_group from recurring_expenses where id = new.recurring_id;
      v_member := new.member_id;
  end case;

  if not exists (select 1 from group_members where id = v_member and group_id = v_group) then
    raise exception 'Member % is not in this group', v_member using errcode = '23503';
  end if;
  return new;
end;
$$;

create trigger expenses_member_in_group
  before insert or update of payer_member_id, group_id on expenses
  for each row execute function assert_member_in_group();
create trigger recurring_expenses_member_in_group
  before insert or update of payer_member_id, group_id on recurring_expenses
  for each row execute function assert_member_in_group();
create trigger expense_splits_member_in_group
  before insert or update on expense_splits
  for each row execute function assert_member_in_group();
create trigger recurring_expense_splits_member_in_group
  before insert or update on recurring_expense_splits
  for each row execute function assert_member_in_group();

-- ---------------------------------------------------------------- shared check
-- Sums the shares as they will be stored (rounded to cents), so 5.005 + 5.005
-- can't pass as 10.01 and then land as 10.02.
create or replace function assert_splits_sum(p_amount numeric, p_splits jsonb)
returns void
language plpgsql
immutable
as $$
declare
  v_sum numeric;
begin
  if p_splits is null or jsonb_typeof(p_splits) <> 'array'
     or jsonb_array_length(p_splits) = 0 then
    raise exception 'At least one split is required';
  end if;

  select sum(round((s->>'share_amount')::numeric, 2))
  into   v_sum
  from   jsonb_array_elements(p_splits) s;

  if v_sum <> round(p_amount, 2) then
    raise exception 'Splits (%) must sum to amount (%)', v_sum, p_amount;
  end if;
end;
$$;

-- ---------------------------------------------------------------- expense
-- p_splits is a jsonb array of {member_id, share_amount, share_percent?}.
create or replace function create_expense(
  p_group_id        uuid,
  p_payer_member_id uuid,
  p_amount          numeric,
  p_description     text,
  p_split_type      text,
  p_category_id     uuid,
  p_occurred_on     date,
  p_splits          jsonb
) returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id uuid;
begin
  if not is_group_member(p_group_id) then
    raise exception 'Not a member of this group' using errcode = '42501';
  end if;
  perform assert_splits_sum(p_amount, p_splits);

  insert into expenses (group_id, payer_member_id, amount, description,
                        split_type, category_id, occurred_on, created_by)
  values (p_group_id, p_payer_member_id, p_amount, coalesce(p_description, ''),
          p_split_type, p_category_id, coalesce(p_occurred_on, current_date), auth.uid())
  returning id into v_id;

  insert into expense_splits (expense_id, member_id, share_amount, share_percent)
  select v_id,
         (s->>'member_id')::uuid,
         (s->>'share_amount')::numeric,
         nullif(s->>'share_percent', '')::numeric
  from   jsonb_array_elements(p_splits) s;

  return v_id;
end;
$$;

-- ---------------------------------------------------------------- recurring
create or replace function create_recurring(
  p_group_id        uuid,
  p_payer_member_id uuid,
  p_amount          numeric,
  p_description     text,
  p_split_type      text,
  p_category_id     uuid,
  p_frequency       text,
  p_interval_count  int,
  p_next_occurrence date,
  p_splits          jsonb
) returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id uuid;
begin
  if not is_group_member(p_group_id) then
    raise exception 'Not a member of this group' using errcode = '42501';
  end if;
  perform assert_splits_sum(p_amount, p_splits);

  insert into recurring_expenses (group_id, payer_member_id, amount, description,
                                  split_type, category_id, frequency, interval_count,
                                  next_occurrence, created_by)
  values (p_group_id, p_payer_member_id, p_amount, coalesce(p_description, ''),
          p_split_type, p_category_id, p_frequency, p_interval_count,
          p_next_occurrence, auth.uid())
  returning id into v_id;

  insert into recurring_expense_splits (recurring_id, member_id, share_amount, share_percent)
  select v_id,
         (s->>'member_id')::uuid,
         (s->>'share_amount')::numeric,
         nullif(s->>'share_percent', '')::numeric
  from   jsonb_array_elements(p_splits) s;

  return v_id;
end;
$$;

grant execute on function create_expense(uuid, uuid, numeric, text, text, uuid, date, jsonb)
  to authenticated;
grant execute on function create_recurring(uuid, uuid, numeric, text, text, uuid, text, int, date, jsonb)
  to authenticated;

-- ---------------------------------------------------------------- close the old path
drop policy if exists "members insert expense"          on expenses;
drop policy if exists "members insert splits"           on expense_splits;
drop policy if exists "members insert recurring"        on recurring_expenses;
drop policy if exists "members insert recurring splits" on recurring_expense_splits;
