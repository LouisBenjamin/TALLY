import 'package:decimal/decimal.dart';
import 'package:tally/core/dates.dart';
import 'package:tally/core/supabase_client.dart';
import 'package:tally/features/expenses/split_logic.dart';
import 'package:tally/models/expense.dart';
import 'package:tally/models/expense_split.dart';

class ExpensesRepository {
  Future<List<Expense>> fetchExpenses({required String groupId}) async {
    final data = await supabase
        .from('expenses')
        .select()
        .eq('group_id', groupId)
        .isFilter('deleted_at', null)
        .order('occurred_on', ascending: false)
        .order('created_at', ascending: false);
    return (data as List)
        .map((e) => Expense.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  // The per-member splits of a single expense — used to pre-fill the edit form.
  Future<List<ExpenseSplit>> fetchSplits({required String expenseId}) async {
    final data = await supabase
        .from('expense_splits')
        .select()
        .eq('expense_id', expenseId);
    return (data as List)
        .map((e) => ExpenseSplit.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  // Creates an expense and its splits in one transaction via the
  // create_expense RPC, which re-checks membership and that the splits sum to
  // the amount server-side. Money is Decimal, sent as strings so numeric(12,2)
  // precision survives the JSON round-trip.
  Future<void> createExpense({
    required String groupId,
    required String payerMemberId,
    required Decimal amount,
    required String description,
    String splitType = 'equal',
    String? categoryId,
    required List<Split> splits,
  }) async {
    await supabase.rpc('create_expense', params: {
      'p_group_id': groupId,
      'p_payer_member_id': payerMemberId,
      'p_amount': amount.toString(),
      'p_description': description,
      'p_split_type': splitType,
      'p_category_id': categoryId,
      // The user's local today: the server's current_date is UTC, which is
      // already tomorrow on a Montreal evening.
      'p_occurred_on': isoDate(DateTime.now()),
      'p_splits': splitsJson(splits),
    });
  }

  // Rewrites an expense and its splits in one transaction via the
  // update_expense RPC, which re-checks membership and that the splits sum to
  // the amount server-side.
  Future<void> updateExpense({
    required String expenseId,
    required String payerMemberId,
    required Decimal amount,
    required String description,
    String splitType = 'equal',
    String? categoryId,
    required List<Split> splits,
  }) async {
    await supabase.rpc('update_expense', params: {
      'p_expense_id': expenseId,
      'p_payer_member_id': payerMemberId,
      'p_amount': amount.toString(),
      'p_description': description,
      'p_split_type': splitType,
      'p_category_id': categoryId,
      'p_splits': splitsJson(splits),
    });
  }

  // Soft delete via RPC: the row stays for history but drops out of every read
  // and the balances view (all filter on deleted_at is null). Routed through a
  // SECURITY DEFINER function because a plain UPDATE that sets deleted_at is
  // rejected by RLS — the new state fails the "deleted_at is null" SELECT policy.
  Future<void> deleteExpense({required String expenseId}) async {
    await supabase.rpc('delete_expense', params: {'p_expense_id': expenseId});
  }
}

// The p_splits payload shared by every RPC that writes splits.
List<Map<String, String>> splitsJson(List<Split> splits) => [
      for (final s in splits)
        {
          'member_id': s.memberId,
          'share_amount': s.shareAmount.toString(),
          if (s.sharePercent != null) 'share_percent': s.sharePercent.toString(),
        },
    ];
