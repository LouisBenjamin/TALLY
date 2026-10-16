-- TALLY — expense dates, editable payments, leaving groups, activity feed
--
-- (1) update_expense takes the expense date, so a date can be fixed later.
-- (2) settlements ("payments") can be edited and deleted by any member.
-- (3) Members can leave or be removed, and the owner can delete the group.
--     Removal is soft (removed_at): old expenses and payments keep pointing at
--     the member row, so history and balances stay intact. Only someone whose
--     balance is zero can be removed, so nobody's debt disappears with them.
-- (4) An activity table written by triggers, so every path (app, import,
--     recurring tick) is logged and the client can't forge or skip entries.

-- ================================================================ membership
alter table group_members add column removed_at timestamptz;

-- A removed member loses access to the group everywhere RLS checks it.
create or replace function is_group_member(gid uuid)
returns boolean
language sql
security definer
stable
set search_path = public
as $$
  select exists (
    select 1 from group_members
    where group_id = gid and user_id = auth.uid() and removed_at is null
  );
$$;

-- Rejoining with the code after being removed restores the old member row,
-- so the person gets their history back instead of a second identity.
create or replace function join_group_by_code(p_code text)
returns groups
language plpgsql
security definer
set search_path = public
as $$
declare
  g groups;
begin
  if auth.uid() is null then
    raise exception 'Not authenticated' using errcode = '28000';
  end if;

  select * into g from groups where join_code = upper(trim(p_code));
  if not found then
    raise exception 'No group found for code %', p_code using errcode = 'no_data_found';
  end if;

  insert into group_members (group_id, user_id, role)
  values (g.id, auth.uid(), 'member')
  on conflict (group_id, user_id) do update set removed_at = null
    where group_members.removed_at is not null;

  return g;
end;
$$;

-- Remove a member, or leave (pass your own member id). Any member may do it,
-- the same rule Splitwise uses, but only at a zero balance, and never to the
-- owner: the owner deletes the group instead.
create or replace function remove_member(p_member_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  m     group_members;
  v_net numeric;
begin
  select * into m from group_members where id = p_member_id and removed_at is null;
  if not found then
    raise exception 'Member not found';
  end if;
  if not is_group_member(m.group_id) then
    raise exception 'Not a member of this group' using errcode = '42501';
  end if;
  if m.role = 'owner' then
    raise exception 'The owner can''t leave. Delete the group instead.';
  end if;

  select net into v_net from group_balances
  where group_id = m.group_id and member_id = m.id;
  if coalesce(v_net, 0) <> 0 then
    raise exception 'Settle up first: % has a balance of %', coalesce(m.display_name, 'this member'), v_net;
  end if;

  update group_members set removed_at = now() where id = m.id;

  -- A template still naming them would fail the member check below and abort
  -- the whole daily tick, so pause those templates.
  update recurring_expenses r set active = false
  where  r.group_id = m.group_id and r.active
    and  (r.payer_member_id = m.id
          or exists (select 1 from recurring_expense_splits s
                     where s.recurring_id = r.id and s.member_id = m.id));
end;
$$;

grant execute on function remove_member(uuid) to authenticated;

-- Owner only. A plain `delete from groups` can't work: the member rows would
-- go before the splits that point at them, failing their foreign keys. So
-- clear the money tables first, then let the group cascade the rest.
create or replace function delete_group(p_group_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not exists (select 1 from groups where id = p_group_id and created_by = auth.uid()) then
    raise exception 'Only the group owner can delete the group' using errcode = '42501';
  end if;

  delete from expenses           where group_id = p_group_id; -- cascades splits
  delete from recurring_expenses where group_id = p_group_id; -- cascades splits
  delete from settlements        where group_id = p_group_id;
  delete from groups             where id = p_group_id;       -- members, rules, activity
end;
$$;

grant execute on function delete_group(uuid) to authenticated;

-- Payers, split members and payment parties must be current members of the
-- expense's group. Extends the 0014 trigger with settlements and removal.
create or replace function assert_member_in_group()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_group   uuid;
  v_members uuid[];
begin
  case tg_table_name
    when 'expenses', 'recurring_expenses' then
      v_group   := new.group_id;
      v_members := array[new.payer_member_id];
    when 'settlements' then
      v_group   := new.group_id;
      v_members := array[new.from_member, new.to_member];
    when 'expense_splits' then
      select group_id into v_group from expenses where id = new.expense_id;
      v_members := array[new.member_id];
    when 'recurring_expense_splits' then
      select group_id into v_group from recurring_expenses where id = new.recurring_id;
      v_members := array[new.member_id];
  end case;

  if (select count(*) from group_members
      where id = any(v_members) and group_id = v_group and removed_at is null)
     <> cardinality(array(select distinct unnest(v_members))) then
    raise exception 'Everyone on this must be a current member of the group'
      using errcode = '23503';
  end if;
  return new;
end;
$$;

create trigger settlements_member_in_group
  before insert or update of from_member, to_member, group_id on settlements
  for each row execute function assert_member_in_group();

-- ================================================================ payments
create policy "members update settlement" on settlements
  for update using (is_group_member(group_id)) with check (is_group_member(group_id));

create policy "members delete settlement" on settlements
  for delete using (is_group_member(group_id));

-- ================================================================ expense date
drop function if exists update_expense(uuid, uuid, numeric, text, text, uuid, jsonb);

create or replace function update_expense(
  p_expense_id      uuid,
  p_payer_member_id uuid,
  p_amount          numeric,
  p_description     text,
  p_split_type      text,
  p_category_id     uuid,
  p_occurred_on     date,
  p_splits          jsonb
) returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_group_id uuid;
begin
  select group_id into v_group_id
  from   expenses
  where  id = p_expense_id and deleted_at is null;

  if v_group_id is null then
    raise exception 'Expense not found';
  end if;
  if not is_group_member(v_group_id) then
    raise exception 'Not authorized';
  end if;
  perform assert_splits_sum(p_amount, p_splits);

  update expenses set
    payer_member_id = p_payer_member_id,
    amount          = p_amount,
    description     = p_description,
    split_type      = p_split_type,
    category_id     = p_category_id,
    occurred_on     = coalesce(p_occurred_on, occurred_on)
  where id = p_expense_id;

  delete from expense_splits where expense_id = p_expense_id;

  insert into expense_splits (expense_id, member_id, share_amount, share_percent)
  select p_expense_id,
         (s->>'member_id')::uuid,
         (s->>'share_amount')::numeric,
         nullif(s->>'share_percent', '')::numeric
  from   jsonb_array_elements(p_splits) s;
end;
$$;

grant execute on function update_expense(uuid, uuid, numeric, text, text, uuid, date, jsonb)
  to authenticated;

-- ================================================================ activity
create table activity (
  id         uuid primary key default gen_random_uuid(),
  group_id   uuid not null references groups(id) on delete cascade,
  actor_id   uuid references profiles(id) on delete set null, -- null = Tally itself (recurring tick)
  summary    text not null,          -- full sentence, names snapshotted at write time
  amount     numeric(12, 2),
  created_at timestamptz not null default now()
);

create index activity_group_idx on activity (group_id, created_at desc);

alter table activity enable row level security;

-- Read-only to clients: rows are only ever written by the triggers below.
create policy "members read activity" on activity
  for select using (is_group_member(group_id));

create or replace function member_name(p_member_id uuid)
returns text
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(p.display_name, gm.display_name, 'Someone')
  from   group_members gm
  left   join profiles p on p.id = gm.user_id
  where  gm.id = p_member_id;
$$;

create or replace function log_activity()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor text := coalesce(
    (select display_name from profiles where id = auth.uid()), 'Tally');
  v_group   uuid;
  v_summary text;
  v_amount  numeric;
  v_label   text;
begin
  if tg_table_name = 'expenses' then
    v_group  := new.group_id;
    v_amount := new.amount;
    v_label  := coalesce(nullif(new.description, ''), 'an expense');
    if tg_op = 'INSERT' then
      v_summary := format('%s added "%s"', v_actor, v_label);
    elsif old.deleted_at is null and new.deleted_at is not null then
      v_summary := format('%s deleted "%s"', v_actor, v_label);
    elsif new.amount is distinct from old.amount
       or new.description is distinct from old.description
       or new.payer_member_id is distinct from old.payer_member_id
       or new.occurred_on is distinct from old.occurred_on
       or new.category_id is distinct from old.category_id then
      v_summary := format('%s edited "%s"', v_actor, v_label);
    else
      return null; -- e.g. a category delete detaching rows: nothing worth showing
    end if;

  elsif tg_table_name = 'settlements' then
    if tg_op = 'DELETE' then
      v_group  := old.group_id;
      v_amount := old.amount;
      v_summary := format('%s deleted a payment from %s to %s', v_actor,
                          member_name(old.from_member), member_name(old.to_member));
    else
      v_group  := new.group_id;
      v_amount := new.amount;
      v_summary := format('%s %s a payment: %s paid %s', v_actor,
                          case tg_op when 'INSERT' then 'recorded' else 'edited' end,
                          member_name(new.from_member), member_name(new.to_member));
    end if;

  elsif tg_table_name = 'group_members' then
    v_group := new.group_id;
    if tg_op = 'INSERT' and new.user_id is null then
      v_summary := format('%s added guest %s', v_actor, new.display_name);
    elsif tg_op = 'INSERT' then
      if new.role = 'owner' then return null; end if; -- group creation itself
      v_summary := format('%s joined the group', member_name(new.id));
    elsif old.removed_at is null and new.removed_at is not null then
      v_summary := case when new.user_id = auth.uid()
                        then format('%s left the group', v_actor)
                        else format('%s removed %s', v_actor, member_name(new.id)) end;
    elsif old.removed_at is not null and new.removed_at is null then
      v_summary := format('%s rejoined the group', member_name(new.id));
    else
      return null;
    end if;
  end if;

  insert into activity (group_id, actor_id, summary, amount)
  values (v_group, auth.uid(), v_summary, v_amount);
  return null;
end;
$$;

create trigger expenses_activity
  after insert or update on expenses
  for each row execute function log_activity();
create trigger settlements_activity
  after insert or update or delete on settlements
  for each row execute function log_activity();
create trigger group_members_activity
  after insert or update of removed_at on group_members
  for each row execute function log_activity();
