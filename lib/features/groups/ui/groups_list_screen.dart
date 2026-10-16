import 'package:tally/core/icons.dart';
import 'package:tally/core/money.dart';
import 'package:tally/core/theme.dart';
import 'package:tally/core/widgets/page_body.dart';
import 'package:tally/core/widgets/state_views.dart';
import 'package:tally/features/groups/data/groups_repository.dart';
import 'package:tally/features/groups/providers/groups_provider.dart';
import 'package:tally/features/groups/ui/create_group_dialog.dart';
import 'package:tally/models/group_summary.dart';
import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
class GroupsListScreen extends ConsumerWidget {
  const GroupsListScreen({super.key});

  void _createGroup(BuildContext context, WidgetRef ref) => showDialog(
        context: context,
        builder: (_) => CreateGroupDialog(
          onCreated: () {
            ref.invalidate(groupsProvider);
            ref.invalidate(groupSummariesProvider);
          },
        ),
      );

  void _joinGroup(BuildContext context) => showDialog(
        context: context,
        builder: (_) => const JoinGroupDialog(),
      );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summariesAsync = ref.watch(groupSummariesProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Groups'),
        centerTitle: false,
        actions: [
          IconButton(
            tooltip: 'Join by code',
            icon: const Icon(AppIcons.signIn),
            onPressed: () => _joinGroup(context),
          ),
        ],
      ),
      // The empty state has its own create/join buttons; no FAB duplicate.
      floatingActionButton: summariesAsync.valueOrNull?.isEmpty ?? true
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _createGroup(context, ref),
              icon: const Icon(AppIcons.add),
              label: const Text('New group'),
            ),
      body: PageBody(
        child: summariesAsync.when(
          loading: () => const _GroupsSkeleton(),
          error: (e, _) => ErrorView(
            error: e,
            onRetry: () => ref.invalidate(groupSummariesProvider),
          ),
          data: (groups) => groups.isEmpty
              ? EmptyState(
                  icon: AppIcons.groupAdd,
                  title: 'No groups yet',
                  message: 'Create one and invite your people.',
                  actions: [
                    FilledButton.icon(
                      onPressed: () => _createGroup(context, ref),
                      icon: const Icon(AppIcons.add),
                      label: const Text('Create a group'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => _joinGroup(context),
                      icon: const Icon(AppIcons.signIn),
                      label: const Text('Join with a code'),
                    ),
                  ],
                )
              : _GroupsGrid(groups: groups),
        ),
      ),
    );
  }
}

const _gridDelegate = SliverGridDelegateWithMaxCrossAxisExtent(
  maxCrossAxisExtent: 200,
  crossAxisSpacing: Space.md,
  mainAxisSpacing: Space.md,
  childAspectRatio: 1,
);
const _gridPadding = EdgeInsets.fromLTRB(Space.lg, Space.lg, Space.lg, 96);

/// Square tiles, as many per row as fit — photo (or initial) on top, name and
/// "who owes what" underneath on the card surface so the text always has a
/// solid, contrast-checked background.
class _GroupsGrid extends StatelessWidget {
  const _GroupsGrid({required this.groups});
  final List<GroupSummary> groups;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: _gridPadding,
      itemCount: groups.length,
      gridDelegate: _gridDelegate,
      itemBuilder: (_, i) => _GroupCard(summary: groups[i]),
    );
  }
}

class _GroupCard extends StatelessWidget {
  const _GroupCard({required this.summary});
  final GroupSummary summary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final photoUrl = summary.photoUrl;

    // Merged so a screen reader announces "Name, You owe $5" as one button.
    return MergeSemantics(
      child: Card(
        child: InkWell(
          onTap: () => context.push('/groups/${summary.id}'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: photoUrl != null
                    ? Image.network(
                        photoUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) =>
                            _InitialTile(summary: summary),
                      )
                    : _InitialTile(summary: summary),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                    Space.md, Space.sm, Space.md, Space.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      summary.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 2),
                    _StatusLine(net: summary.myNet),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Group initial on a per-group tint, so tiles without photos still differ.
class _InitialTile extends StatelessWidget {
  const _InitialTile({required this.summary});
  final GroupSummary summary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tint = categoryTint(summary.id, theme.brightness);
    final name = summary.name;
    return ColoredBox(
      color: tint,
      child: Center(
        child: Text(
          name.isNotEmpty ? name.substring(0, 1).toUpperCase() : '?',
          style: theme.textTheme.displaySmall?.copyWith(
            color: onCategoryTint(tint),
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

/// "You owe $X" / "You're owed $X" / "Settled up", colored to match.
class _StatusLine extends StatelessWidget {
  const _StatusLine({required this.net});
  final Decimal net;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final String label;
    final Color color;
    if (net.compareTo(Decimal.zero) > 0) {
      label = "You're owed ${formatCurrency(net)}";
      color = AppColors.of(context).positive;
    } else if (net.compareTo(Decimal.zero) < 0) {
      label = 'You owe ${formatCurrency(-net)}';
      color = theme.colorScheme.error;
    } else {
      label = 'Settled up';
      color = theme.colorScheme.onSurfaceVariant;
    }
    return Text(
      label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: theme.textTheme.bodySmall?.copyWith(
        color: color,
        fontWeight: FontWeight.w700,
        fontFeatures: kTabularFigures,
      ),
    );
  }
}

/// Same grid shape as the real thing, so nothing jumps when data arrives.
class _GroupsSkeleton extends StatelessWidget {
  const _GroupsSkeleton();

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: _gridPadding,
      itemCount: 6,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: _gridDelegate,
      itemBuilder: (_, __) => const Card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: Skeleton(radius: 0)),
            Padding(
              padding: EdgeInsets.all(Space.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Skeleton(width: 100, height: 14),
                  SizedBox(height: Space.sm),
                  Skeleton(width: 70, height: 10),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class JoinGroupDialog extends ConsumerStatefulWidget {
  const JoinGroupDialog({super.key});

  @override
  ConsumerState<JoinGroupDialog> createState() => _JoinGroupDialogState();
}

class _JoinGroupDialogState extends ConsumerState<JoinGroupDialog> {
  final _controller = TextEditingController();
  bool _joining = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _join() async {
    final code = _controller.text.trim();
    if (code.isEmpty) return;
    setState(() => _joining = true);
    try {
      final group = await GroupsRepository().joinGroupByCode(code: code);
      ref.invalidate(groupsProvider);
      ref.invalidate(groupSummariesProvider);
      if (mounted) {
        Navigator.of(context).pop();
        context.push('/groups/${group.id}');
      }
    } on Exception catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
      }
    } finally {
      if (mounted) setState(() => _joining = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Join a group'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        textCapitalization: TextCapitalization.characters,
        onSubmitted: (_) => _join(),
        decoration: const InputDecoration(
          labelText: 'Invite code',
          hintText: 'e.g. AB452A',
          border: OutlineInputBorder(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _joining ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _joining ? null : _join,
          child: _joining
              ? const SizedBox(
                  height: 16,
                  width: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Join'),
        ),
      ],
    );
  }
}
