import 'package:decimal/decimal.dart';
import 'package:tally/core/dates.dart';
import 'package:tally/core/supabase_client.dart';
import 'package:tally/features/expenses/data/expenses_repository.dart';
import 'package:tally/features/expenses/split_logic.dart';
import 'package:tally/models/recurring_expense.dart';

class RecurringRepository {
  Future<List<RecurringExpense>> fetchRecurring({required String groupId}) async {
    final data = await supabase
        .from('recurring_expenses')
        .select()
        .eq('group_id', groupId)
        .order('next_occurrence');
    return (data as List)
        .map((e) => RecurringExpense.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> createRecurring({
    required String groupId,
    required String payerMemberId,
    required Decimal amount,
    required String description,
    required String splitType,
    String? categoryId,
    required String frequency,
    required int intervalCount,
    required DateTime nextOccurrence,
    required List<Split> splits,
  }) async {
    // One transaction: a template saved without its splits would make the
    // daily tick materialize split-less expenses forever.
    await supabase.rpc('create_recurring', params: {
      'p_group_id': groupId,
      'p_payer_member_id': payerMemberId,
      'p_amount': amount.toString(),
      'p_description': description,
      'p_split_type': splitType,
      'p_category_id': categoryId,
      'p_frequency': frequency,
      'p_interval_count': intervalCount,
      'p_next_occurrence': isoDate(nextOccurrence),
      'p_splits': splitsJson(splits),
    });
  }

  Future<void> setActive({required String id, required bool active}) async {
    await supabase
        .from('recurring_expenses')
        .update({'active': active}).eq('id', id);
  }

  Future<void> deleteRecurring({required String id}) async {
    await supabase.from('recurring_expenses').delete().eq('id', id);
  }

}
