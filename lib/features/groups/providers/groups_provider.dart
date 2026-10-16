import 'package:tally/features/activity/activity_provider.dart';
import 'package:tally/features/balances/providers/balances_provider.dart';
import 'package:tally/features/expenses/providers/expenses_provider.dart';
import 'package:tally/features/groups/data/groups_repository.dart';
import 'package:tally/models/group.dart';
import 'package:tally/models/group_member.dart';
import 'package:tally/models/group_summary.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// All groups for the current user.
// Invalidate with ref.invalidate(groupsProvider) after create/update.
final groupsProvider = FutureProvider<List<Group>>((ref) {
  return GroupsRepository().fetchGroups();
});

// Groups + the caller's own net balance in each — powers the groups list
// cards. Invalidate with ref.invalidate(groupSummariesProvider) after
// create/join/photo-change/settle-up.
final groupSummariesProvider = FutureProvider<List<GroupSummary>>((ref) {
  return GroupsRepository().fetchGroupSummaries();
});

// Single group by ID — used by GroupDetailScreen.
final groupProvider = FutureProvider.family<Group, String>((ref, groupId) {
  return GroupsRepository().fetchGroup(id: groupId);
});

// Roster for a group (real users + guests).
// Invalidate with ref.invalidate(membersProvider(groupId)) after adding a member.
final membersProvider = FutureProvider.family<List<GroupMember>, String>(
  (ref, groupId) => GroupsRepository().fetchMembers(groupId: groupId),
);

// Call after anything changes a group's money — adding, editing, deleting or
// importing an expense, or recording a settlement. Refreshes the expense list
// and the in-group balances, and — easy to forget — groupSummariesProvider,
// the separate view behind the "you owe / you're owed" tally on the groups
// list. Nothing else invalidates it, so skipping it leaves that tally stale
// until a manual pull-to-refresh.
void invalidateGroupMoney(WidgetRef ref, String groupId) {
  ref.invalidate(expensesProvider(groupId));
  ref.invalidate(balancesProvider(groupId));
  ref.invalidate(settlementsProvider(groupId));
  ref.invalidate(activityProvider(groupId));
  ref.invalidate(groupSummariesProvider);
}
