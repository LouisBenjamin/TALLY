import 'package:tally/core/icons.dart';
import 'package:tally/core/money.dart';
import 'package:tally/features/activity/activity_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

class ActivityTab extends ConsumerWidget {
  const ActivityTab({super.key, required this.groupId});
  final String groupId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return ref.watch(activityProvider(groupId)).when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('Error: $e')),
          data: (entries) => entries.isEmpty
              ? const Center(child: Text('No activity yet'))
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                  itemCount: entries.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final a = entries[i];
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(AppIcons.receipt),
                      title: Text(a.summary),
                      // createdAt is an instant (timestamptz), unlike the
                      // date-only expense dates, so local time is right here.
                      subtitle: Text(
                        DateFormat('MMM d, h:mm a').format(a.createdAt.toLocal()),
                        style: theme.textTheme.bodySmall,
                      ),
                      trailing: a.amount == null
                          ? null
                          : Text(formatCurrency(a.amount!),
                              style: theme.textTheme.titleSmall),
                    );
                  },
                ),
        );
  }
}
