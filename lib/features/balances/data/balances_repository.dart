import 'package:decimal/decimal.dart';
import 'package:tally/core/dates.dart';
import 'package:tally/core/supabase_client.dart';
import 'package:tally/models/member_balance.dart';
import 'package:tally/models/settlement.dart';

class BalancesRepository {
  // Net balance per member from the group_balances view (RLS-scoped).
  Future<List<MemberBalance>> fetchBalances({required String groupId}) async {
    final data = await supabase
        .from('group_balances')
        .select()
        .eq('group_id', groupId);
    return (data as List)
        .map((e) => MemberBalance.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<Settlement>> fetchSettlements({required String groupId}) async {
    final data = await supabase
        .from('settlements')
        .select()
        .eq('group_id', groupId)
        .order('occurred_on', ascending: false)
        .order('created_at', ascending: false);
    return (data as List)
        .map((e) => Settlement.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  // Record a payment from one member to another. Any amount, not just the
  // suggested one, so partial payments work.
  Future<void> settle({
    required String groupId,
    required String fromMemberId,
    required String toMemberId,
    required Decimal amount,
  }) async {
    await supabase.from('settlements').insert({
      'group_id': groupId,
      'from_member': fromMemberId,
      'to_member': toMemberId,
      'amount': amount.toString(),
      'occurred_on': isoDate(DateTime.now()),
    });
  }

  Future<void> updateSettlement({
    required String id,
    required String fromMemberId,
    required String toMemberId,
    required Decimal amount,
  }) async {
    await supabase.from('settlements').update({
      'from_member': fromMemberId,
      'to_member': toMemberId,
      'amount': amount.toString(),
    }).eq('id', id);
  }

  Future<void> deleteSettlement({required String id}) async {
    await supabase.from('settlements').delete().eq('id', id);
  }
}
