import 'package:tally/core/icons.dart';
import 'package:tally/features/activity/activity_tab.dart';
import 'package:tally/core/money.dart';
import 'package:tally/core/supabase_client.dart';
import 'package:tally/core/widgets/page_body.dart';
import 'package:tally/features/balances/ui/balances_tab.dart';
import 'package:tally/features/expenses/data/expenses_repository.dart';
import 'package:tally/features/expenses/providers/categories_provider.dart';
import 'package:tally/features/expenses/providers/expenses_provider.dart';
import 'package:tally/features/groups/data/groups_repository.dart';
import 'package:tally/features/groups/providers/groups_provider.dart';
import 'package:tally/features/labels/ui/labels_tab.dart';
import 'package:tally/features/realtime/group_realtime_provider.dart';
import 'package:tally/models/category.dart';
import 'package:tally/models/expense.dart';
import 'package:tally/models/group_member.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

class GroupDetailScreen extends ConsumerStatefulWidget {
  const GroupDetailScreen({super.key, required this.groupId});
  final String groupId;

  @override
  ConsumerState<GroupDetailScreen> createState() => _GroupDetailScreenState();
}

class _GroupDetailScreenState extends ConsumerState<GroupDetailScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tab =
      TabController(length: 5, vsync: this)..addListener(() => setState(() {}));

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  Future<void> _addExpense() async {
    await context.push('/groups/${widget.groupId}/expenses/new');
    invalidateGroupMoney(ref, widget.groupId);
  }

  Future<void> _importStatement() async {
    await context.push('/groups/${widget.groupId}/import');
    invalidateGroupMoney(ref, widget.groupId);
  }

  Future<void> _addGuest() async {
    await showDialog(
      context: context,
      builder: (_) => _AddGuestDialog(groupId: widget.groupId),
    );
    ref.invalidate(membersProvider(widget.groupId));
  }

  @override
  Widget build(BuildContext context) {
    final groupAsync = ref.watch(groupProvider(widget.groupId));
    // Keep a realtime subscription alive while this screen is open.
    ref.watch(groupRealtimeProvider(widget.groupId));

    return Scaffold(
      appBar: AppBar(
        title: groupAsync.when(
          loading: () => const Text('Loading…'),
          error: (_, __) => const Text('Group'),
          data: (g) => Text(g.name),
        ),
        centerTitle: false,
        actions: [
          IconButton(
            tooltip: 'Recurring',
            icon: const Icon(AppIcons.repeat),
            onPressed: () => context.push('/groups/${widget.groupId}/recurring'),
          ),
          IconButton(
            tooltip: 'Insights',
            icon: const Icon(AppIcons.insights),
            onPressed: () => context.push('/groups/${widget.groupId}/insights'),
          ),
          IconButton(
            tooltip: 'Import statement',
            icon: const Icon(AppIcons.upload),
            onPressed: _importStatement,
          ),
          IconButton(
            tooltip: 'Group settings',
            icon: const Icon(AppIcons.settings),
            onPressed: () => context.push('/groups/${widget.groupId}/settings'),
          ),
        ],
        bottom: TabBar(
          controller: _tab,
          tabs: const [
            Tab(text: 'Expenses'),
            Tab(text: 'Balances'),
            Tab(text: 'Members'),
            Tab(text: 'Labels'),
            Tab(text: 'Activity'),
          ],
        ),
      ),
      floatingActionButton: switch (_tab.index) {
        0 => FloatingActionButton.extended(
            onPressed: _addExpense,
            icon: const Icon(AppIcons.add),
            label: const Text('Add expense'),
          ),
        2 => FloatingActionButton.extended(
            onPressed: _addGuest,
            icon: const Icon(AppIcons.personAdd),
            label: const Text('Add guest'),
          ),
        _ => null,
      },
      body: PageBody(
        child: TabBarView(
          controller: _tab,
          children: [
            _ExpensesTab(groupId: widget.groupId),
            BalancesTab(groupId: widget.groupId),
            _MembersTab(groupId: widget.groupId),
            LabelsTab(groupId: widget.groupId),
            ActivityTab(groupId: widget.groupId),
          ],
        ),
      ),
    );
  }
}

// ============================================================ Expenses tab

class _ExpensesTab extends ConsumerWidget {
  const _ExpensesTab({required this.groupId});
  final String groupId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final expensesAsync = ref.watch(expensesProvider(groupId));
    // A slow categories fetch never blocks the expense list — cards just
    // render uncategorized until it resolves.
    final categories = ref.watch(categoriesProvider(groupId)).valueOrNull ??
        const <Category>[];
    final categoryById = {for (final c in categories) c.id: c};

    return expensesAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
      data: (expenses) => expenses.isEmpty
          ? const _EmptyState(
              icon: AppIcons.receipt,
              title: 'No expenses yet',
              subtitle: 'Tap + to log the first one.',
            )
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
              itemCount: expenses.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (_, i) => _ExpenseCard(
                expense: expenses[i],
                groupId: groupId,
                category: categoryById[expenses[i].categoryId],
              ),
            ),
    );
  }
}

class _ExpenseCard extends ConsumerWidget {
  const _ExpenseCard({
    required this.expense,
    required this.groupId,
    required this.category,
  });
  final Expense expense;
  final String groupId;
  final Category? category;

  void _refresh(WidgetRef ref) => invalidateGroupMoney(ref, groupId);

  Future<void> _edit(BuildContext context, WidgetRef ref) async {
    await context.push('/groups/$groupId/expenses/${expense.id}/edit');
    _refresh(ref);
  }

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final label = expense.description.isEmpty ? 'this expense' : '"${expense.description}"';
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete expense?'),
        content: Text('$label will be removed and balances recalculated.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ExpensesRepository().deleteExpense(expenseId: expense.id);
      _refresh(ref);
    } on Exception catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  void _showActions(BuildContext context, WidgetRef ref) {
    showModalBottomSheet<void>(
      context: context,
      builder: (sheetCtx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(AppIcons.edit),
              title: const Text('Edit'),
              onTap: () {
                Navigator.pop(sheetCtx);
                _edit(context, ref);
              },
            ),
            ListTile(
              leading: const Icon(AppIcons.delete),
              title: const Text('Delete'),
              onTap: () {
                Navigator.pop(sheetCtx);
                _delete(context, ref);
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final dateStr = DateFormat('MMM d').format(expense.occurredOn);
    final amountStr = formatCurrency(expense.amount, currency: expense.currency);
    final category = this.category;

    // Uncategorized expenses keep the original neutral look; a category
    // gets its own icon on a deterministic tint (see categoryTint).
    final Color tint;
    final Color onTint;
    final IconData icon;
    if (category == null) {
      tint = theme.colorScheme.secondaryContainer;
      onTint = theme.colorScheme.onSecondaryContainer;
      icon = AppIcons.receipt;
    } else {
      tint = categoryTint(category.id, theme.brightness);
      onTint = onCategoryTint(tint);
      icon = iconForCategory(category.icon);
    }

    return Card(
      clipBehavior: Clip.hardEdge,
      child: ListTile(
        onTap: () => _showActions(context, ref),
        leading: CircleAvatar(
          backgroundColor: tint,
          child: Icon(icon, color: onTint),
        ),
        title: Text(
          expense.description.isEmpty ? 'Expense' : expense.description,
          style: theme.textTheme.titleSmall,
        ),
        subtitle: Text(
          category == null ? dateStr : '$dateStr · ${category.name}',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        trailing: Text(
          amountStr,
          style: theme.textTheme.titleMedium?.copyWith(
            color: theme.colorScheme.primary,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}

// ============================================================ Members tab

class _MembersTab extends ConsumerWidget {
  const _MembersTab({required this.groupId});
  final String groupId;

  Future<void> _remove(
    BuildContext context,
    WidgetRef ref,
    GroupMember m, {
    required bool isYou,
  }) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: Text(isYou ? 'Leave group?' : 'Remove ${m.displayName}?'),
        content: Text(isYou
            ? 'You will lose access to this group. Your past expenses stay.'
            : 'Their past expenses and payments stay in the history.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogCtx, true),
            child: Text(isYou ? 'Leave' : 'Remove'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await GroupsRepository().removeMember(memberId: m.id);
      ref.invalidate(groupSummariesProvider);
      if (isYou) {
        if (context.mounted) context.go('/groups');
      } else {
        ref.invalidate(membersProvider(groupId));
      }
    } on Exception catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groupAsync = ref.watch(groupProvider(groupId));
    final membersAsync = ref.watch(membersProvider(groupId));
    final myUserId = supabase.auth.currentUser?.id;

    return membersAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
      data: (members) => ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
        children: [
          groupAsync.maybeWhen(
            data: (g) => _JoinCodeCard(code: g.joinCode),
            orElse: () => const SizedBox.shrink(),
          ),
          const SizedBox(height: 16),
          Text('Members (${members.length})',
              style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          ...members.map((m) {
            final isYou = m.userId != null && m.userId == myUserId;
            return _MemberTile(
              member: m,
              isYou: isYou,
              // The owner deletes the group instead (Group settings).
              onRemove: m.role == 'owner'
                  ? null
                  : () => _remove(context, ref, m, isYou: isYou),
            );
          }),
        ],
      ),
    );
  }
}

class _JoinCodeCard extends StatelessWidget {
  const _JoinCodeCard({required this.code});
  final String code;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      color: theme.colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(AppIcons.key, color: theme.colorScheme.onPrimaryContainer),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Invite code',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: theme.colorScheme.onPrimaryContainer,
                      )),
                  Text(
                    code,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      color: theme.colorScheme.onPrimaryContainer,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 3,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Copy code',
              icon: Icon(AppIcons.copy, color: theme.colorScheme.onPrimaryContainer),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: code));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Invite code copied')),
                );
              },
            ),
            IconButton(
              tooltip: 'Share invite',
              icon: Icon(AppIcons.share,
                  color: theme.colorScheme.onPrimaryContainer),
              onPressed: () {
                // On web, share a one-tap link that opens straight to the join
                // screen; elsewhere there's no meaningful URL, so share the code.
                final text = kIsWeb
                    ? _inviteLink(code)
                    : 'Join my group on Tally with code $code';
                Clipboard.setData(ClipboardData(text: text));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content:
                        Text(kIsWeb ? 'Invite link copied' : 'Invite copied'),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  // Builds a deep link to the join screen from the app's current origin. The
  // app uses hash routing on web, so the route lives in the URL fragment:
  // https://host/#/join?code=XXXXXX
  String _inviteLink(String code) =>
      Uri.base.replace(fragment: '/join?code=$code').toString();
}

class _MemberTile extends StatelessWidget {
  const _MemberTile({
    required this.member,
    required this.isYou,
    required this.onRemove,
  });
  final GroupMember member;
  final bool isYou;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(
        backgroundColor: member.isGuest
            ? theme.colorScheme.surfaceContainerHighest
            : theme.colorScheme.primaryContainer,
        child: Text(
          member.displayName.isNotEmpty
              ? member.displayName.substring(0, 1).toUpperCase()
              : '?',
          style: TextStyle(
            color: member.isGuest
                ? theme.colorScheme.onSurfaceVariant
                : theme.colorScheme.onPrimaryContainer,
          ),
        ),
      ),
      title: Row(
        children: [
          Flexible(child: Text(member.displayName)),
          if (isYou) ...[
            const SizedBox(width: 8),
            _Chip(label: 'You', color: theme.colorScheme.primary),
          ],
          if (member.isGuest) ...[
            const SizedBox(width: 8),
            _Chip(label: 'Guest', color: theme.colorScheme.outline),
          ],
        ],
      ),
      subtitle: member.role == 'owner' ? const Text('Owner') : null,
      trailing: onRemove == null
          ? null
          : TextButton(
              onPressed: onRemove,
              child: Text(isYou ? 'Leave' : 'Remove'),
            ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(label,
          style: Theme.of(context)
              .textTheme
              .labelSmall
              ?.copyWith(color: color, fontWeight: FontWeight.w600)),
    );
  }
}

class _AddGuestDialog extends ConsumerStatefulWidget {
  const _AddGuestDialog({required this.groupId});
  final String groupId;

  @override
  ConsumerState<_AddGuestDialog> createState() => _AddGuestDialogState();
}

class _AddGuestDialogState extends ConsumerState<_AddGuestDialog> {
  final _controller = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _controller.text.trim();
    if (name.isEmpty) return;
    setState(() => _saving = true);
    try {
      await GroupsRepository().addGuest(groupId: widget.groupId, name: name);
      if (mounted) Navigator.of(context).pop();
    } on Exception catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add guest'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        textCapitalization: TextCapitalization.words,
        onSubmitted: (_) => _save(),
        decoration: const InputDecoration(
          labelText: 'Guest name',
          hintText: 'e.g. Sam (no account)',
          border: OutlineInputBorder(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(
                  height: 16,
                  width: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Add'),
        ),
      ],
    );
  }
}

// ============================================================ Shared

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.icon,
    required this.title,
    required this.subtitle,
  });
  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 64, color: theme.colorScheme.outlineVariant),
          const SizedBox(height: 16),
          Text(title, style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
