import 'package:tally/core/supabase_client.dart';
import 'package:tally/features/activity/activity_provider.dart';
import 'package:tally/features/balances/providers/balances_provider.dart';
import 'package:tally/features/expenses/providers/expenses_provider.dart';
import 'package:tally/features/groups/providers/groups_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// Live updates for a group. Subscribes to Postgres changes on the tables that
// feed the group screen and invalidates the data providers so every open tab
// (expenses / balances / members) refreshes when anyone in the group makes a
// change. Auto-disposes — and unsubscribes from the channel — once no widget is
// watching it (i.e. after leaving the group screen).
//
// RLS still governs what the client receives; events are only used as a trigger
// to re-fetch through the normal RLS-scoped queries.
final groupRealtimeProvider =
    Provider.autoDispose.family<void, String>((ref, groupId) {
  void refresh() {
    ref.invalidate(expensesProvider(groupId));
    ref.invalidate(balancesProvider(groupId));
    ref.invalidate(settlementsProvider(groupId));
    ref.invalidate(membersProvider(groupId));
    // Activity rows are written by triggers in the same transaction as these
    // changes, so the activity table itself needs no subscription.
    ref.invalidate(activityProvider(groupId));
  }

  final channel = supabase.channel('group-$groupId');
  for (final table in const [
    'expenses',
    'expense_splits',
    'settlements',
    'group_members',
  ]) {
    channel.onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: table,
      callback: (_) => refresh(),
    );
  }
  channel.subscribe();

  ref.onDispose(() => supabase.removeChannel(channel));
});
