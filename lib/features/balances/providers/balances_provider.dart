import 'package:tally/features/balances/data/balances_repository.dart';
import 'package:tally/models/member_balance.dart';
import 'package:tally/models/settlement.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// Net balance per member for a group.
// Invalidate after any expense or settlement change.
final balancesProvider = FutureProvider.family<List<MemberBalance>, String>(
  (ref, groupId) => BalancesRepository().fetchBalances(groupId: groupId),
);

// Recorded payments for a group, newest first.
final settlementsProvider = FutureProvider.family<List<Settlement>, String>(
  (ref, groupId) => BalancesRepository().fetchSettlements(groupId: groupId),
);
