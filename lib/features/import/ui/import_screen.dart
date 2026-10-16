import 'package:decimal/decimal.dart';
import 'package:file_picker/file_picker.dart';
import 'package:tally/core/dates.dart';
import 'package:tally/core/icons.dart';
import 'package:tally/core/theme.dart';
import 'package:tally/core/supabase_client.dart';
import 'package:tally/core/widgets/page_body.dart';
import 'package:tally/features/expenses/providers/categories_provider.dart';
import 'package:tally/features/groups/providers/groups_provider.dart';
import 'package:tally/features/import/data/import_repository.dart';
import 'package:tally/features/import/data/merchant_rules_repository.dart';
import 'package:tally/features/import/logic/field_parsers.dart';
import 'package:tally/features/import/logic/fingerprint.dart';
import 'package:tally/features/import/logic/import_plan.dart';
import 'package:tally/features/import/logic/merchant_rules.dart';
import 'package:tally/features/import/logic/statement_parser.dart';
import 'package:tally/features/import/providers/import_providers.dart';
import 'package:tally/features/import/ui/import_review_list.dart';
import 'package:tally/models/category.dart';
import 'package:tally/models/group_member.dart';
import 'package:tally/models/import_result.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
enum _Step { pick, review, done }

class ImportScreen extends ConsumerStatefulWidget {
  const ImportScreen({super.key, required this.groupId});

  final String groupId;

  @override
  ConsumerState<ImportScreen> createState() => _ImportScreenState();
}

class _ImportScreenState extends ConsumerState<ImportScreen> {
  _Step _step = _Step.pick;

  // The parsed statement lives here and nowhere else — never uploaded, never
  // written to disk. Closing this screen discards it.
  final _txns = <String, ParsedTransaction>{};
  var _rows = <ReviewRow>[];

  String _parseStatus = '';
  String _splitType = 'equal';
  String? _payerMemberId;
  Set<String> _participants = {};
  final _percentCtl = <String, TextEditingController>{};
  DateTimeRange? _range;

  bool _loading = false;
  bool _submitting = false;
  bool _seededParticipants = false;
  ImportResult? _result;

  @override
  void dispose() {
    for (final c in _percentCtl.values) {
      c.dispose();
    }
    super.dispose();
  }

  TextEditingController _percent(String memberId) =>
      _percentCtl.putIfAbsent(memberId, () => TextEditingController());

  // ------------------------------------------------------------------ pick

  Future<void> _pickFile() async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['csv'],
      // Web gives bytes and no path, so always take the bytes.
      withData: true,
    );
    if (picked == null || picked.files.isEmpty) return;

    final file = picked.files.single;
    final bytes = file.bytes;
    if (bytes == null) {
      if (mounted) _snack("Couldn't read that file.");
      return;
    }

    setState(() => _loading = true);
    try {
      final parsed = parseStatement(file.name, bytes);
      if (!parsed.valid) {
        if (mounted) _snack(parsed.status);
        return;
      }

      // Both are needed before the list can be rendered honestly: the rules
      // decide the tags, and the fingerprints decide what is already in the
      // group (including rows someone else imported from another device).
      final rules = await ref.read(merchantRulesProvider(widget.groupId).future);
      final imported =
          await ref.read(importedFingerprintsProvider(widget.groupId).future);

      _txns
        ..clear()
        ..addEntries([
          for (final t in parsed.transactions)
            MapEntry(
              transactionFingerprint(
                groupId: widget.groupId,
                reference: t.reference,
              ),
              t,
            ),
        ]);

      final rows = <ReviewRow>[];
      for (final entry in _txns.entries) {
        final txn = entry.value;
        final hit = matchMerchantRule(
          merchantNormalized: txn.merchantNormalized,
          merchantCategoryDescription: txn.merchantCategory,
          rules: rules,
        );
        final already = imported.contains(entry.key);
        rows.add(
          ReviewRow(
            fingerprint: entry.key,
            description: txn.merchantName,
            occurredOn: txn.occurredOn,
            amount: txn.amount,
            selected: !hit.isSkip && !already,
            alreadyImported: already,
            categoryId: hit.categoryId,
          ),
        );
      }
      rows.sort((a, b) => b.occurredOn.compareTo(a.occurredOn));

      final alreadyCount = rows.where((r) => r.alreadyImported).length;

      if (!mounted) return;
      setState(() {
        _rows = rows;
        _parseStatus = alreadyCount == 0
            ? parsed.status
            : '${parsed.status} · $alreadyCount already imported';
        _range = null;
        _step = _Step.review;
      });
    } on Exception catch (e) {
      if (mounted) _snack(e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ---------------------------------------------------------------- review

  List<ReviewRow> get _visible {
    final range = _range;
    if (range == null) return _rows;
    return _rows.where((r) {
      final iso = isoDate(r.occurredOn);
      return iso.compareTo(isoDate(range.start)) >= 0 &&
          iso.compareTo(isoDate(range.end)) <= 0;
    }).toList();
  }

  void _replace(ReviewRow row, ReviewRow updated) {
    final index = _rows.indexWhere((r) => r.fingerprint == row.fingerprint);
    if (index < 0) return;
    setState(() => _rows = [..._rows]..[index] = updated);
  }

  void _setAllSelected(bool selected) {
    setState(() {
      final visible = _visible.map((r) => r.fingerprint).toSet();
      _rows = [
        for (final r in _rows)
          visible.contains(r.fingerprint) && r.canImport
              ? r.copyWith(selected: selected)
              : r,
      ];
    });
  }

  Future<void> _pickRange() async {
    if (_rows.isEmpty) return;
    final dates = _rows.map((r) => r.occurredOn).toList()..sort();
    final first = dates.first;
    final last = dates.last;

    final picked = await showDateRangePicker(
      context: context,
      firstDate: first,
      lastDate: last,
      initialDateRange: _range ?? DateTimeRange(start: first, end: last),
    );
    if (picked != null) setState(() => _range = picked);
  }

  Future<void> _tagRow(ReviewRow row, List<Category> categories) async {
    final chosen = await _chooseCategory(categories, row.categoryId);
    if (chosen == null) return;
    _replace(row, row.copyWith(categoryId: chosen.id));
  }

  Future<void> _tagSelected(List<Category> categories) async {
    final chosen = await _chooseCategory(categories, null);
    if (chosen == null) return;
    setState(() {
      final visible = _visible.map((r) => r.fingerprint).toSet();
      _rows = [
        for (final r in _rows)
          visible.contains(r.fingerprint) && r.selected && r.canImport
              ? r.copyWith(categoryId: chosen.id)
              : r,
      ];
    });
  }

  Future<Category?> _chooseCategory(
    List<Category> categories,
    String? current,
  ) {
    return showModalBottomSheet<Category>(
      context: context,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const ListTile(title: Text('Tag as'), dense: true),
            for (final c in categories)
              ListTile(
                leading: Icon(iconForCategory(c.icon)),
                title: Text(c.name),
                selected: c.id == current,
                onTap: () => Navigator.pop(context, c),
              ),
          ],
        ),
      ),
    );
  }

  // Turns "this merchant is always groceries" into a group-wide rule, so
  // nobody has to tag it again next month.
  Future<void> _alwaysTag(ReviewRow row, List<Category> categories) async {
    final txn = _txns[row.fingerprint];
    if (txn == null) return;

    final result = await showDialog<_RuleDraft>(
      context: context,
      builder: (_) => _AlwaysTagDialog(
        // Collapsed so the rule covers every store, not the one branch the
        // user happened to be looking at.
        pattern: suggestRulePattern(txn.merchantName),
        categories: categories,
        initialCategoryId: row.categoryId,
      ),
    );
    if (result == null) return;

    try {
      await MerchantRulesRepository().createRule(
        groupId: widget.groupId,
        pattern: result.pattern,
        matchType: 'contains',
        action: result.action,
        categoryId: result.categoryId,
      );
      ref.invalidate(merchantRulesProvider(widget.groupId));
      final rules = await ref.read(merchantRulesProvider(widget.groupId).future);
      if (!mounted) return;
      _reapply(rules);
      _snack('Rule saved — ${result.pattern}');
    } on Exception catch (e) {
      if (mounted) _snack(e.toString());
    }
  }

  // Re-runs matching over rows the user hasn't hand-tagged, so a new rule
  // takes effect immediately without discarding manual work.
  void _reapply(List rules) {
    setState(() {
      _rows = [
        for (final r in _rows)
          () {
            final txn = _txns[r.fingerprint];
            if (txn == null || r.alreadyImported) return r;
            final hit = matchMerchantRule(
              merchantNormalized: txn.merchantNormalized,
              merchantCategoryDescription: txn.merchantCategory,
              rules: List.from(rules),
            );
            if (hit.ruleId == null) return r;
            return r.copyWith(
              categoryId: hit.categoryId ?? r.categoryId,
              selected: hit.isSkip ? false : r.selected,
            );
          }(),
      ];
    });
  }

  ImportPlan _plan(List<GroupMember> members) => buildImportPlan(
        rows: _visible,
        splitType: _splitType,
        orderedMemberIds: members.map((m) => m.id).toList(),
        participants: _participants,
        percent: {
          for (final id in _participants)
            id: Decimal.tryParse(_percent(id).text.trim()) ?? Decimal.zero,
        },
      );

  Future<void> _commit(List<GroupMember> members) async {
    final plan = _plan(members);
    if (!plan.valid) {
      _snack(plan.status);
      return;
    }
    final payer = _payerMemberId;
    if (payer == null) return;

    setState(() => _submitting = true);
    try {
      final result = await ImportRepository().commitImport(
        groupId: widget.groupId,
        payerMemberId: payer,
        splitType: _splitType,
        items: plan.items,
      );
      ref.invalidate(importedFingerprintsProvider(widget.groupId));
      if (mounted) {
        setState(() {
          _result = result;
          _step = _Step.done;
        });
      }
    } on Exception catch (e) {
      if (mounted) _snack(e.toString());
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _snack(String message) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(message)));

  // ------------------------------------------------------------------ build

  @override
  Widget build(BuildContext context) {
    final membersAsync = ref.watch(membersProvider(widget.groupId));
    final categories =
        ref.watch(categoriesProvider(widget.groupId)).valueOrNull ??
            const <Category>[];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Import statement'),
        actions: [
          IconButton(
            tooltip: 'Tags',
            icon: const Icon(AppIcons.tag),
            onPressed: () =>
                context.push('/groups/${widget.groupId}/labels'),
          ),
        ],
      ),
      body: PageBody(
        child: membersAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('Error: $e')),
          data: (members) {
            // Default to everyone, payer = the signed-in member.
            if (!_seededParticipants && members.isNotEmpty) {
              _seededParticipants = true;
              _participants = members.map((m) => m.id).toSet();
              _payerMemberId = _myMemberId(members) ?? members.first.id;
            }

            return switch (_step) {
              _Step.pick => _PickStep(
                  loading: _loading,
                  onPick: _pickFile,
                ),
              _Step.review => _buildReview(members, categories),
              _Step.done => _DoneStep(result: _result),
            };
          },
        ),
      ),
    );
  }

  Widget _buildReview(List<GroupMember> members, List<Category> categories) {
    final theme = Theme.of(context);
    final plan = _plan(members);
    final visible = _visible;
    final selectedCount = visible.where((r) => r.selected && r.canImport).length;

    return Stack(
      children: [
        ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
          children: [
            Text(_parseStatus, style: theme.textTheme.bodyMedium),
            const SizedBox(height: 12),

            _RangeBar(
              range: _range,
              onPick: _pickRange,
              onClear: () => setState(() => _range = null),
            ),
            const SizedBox(height: 12),

            DropdownButtonFormField<String>(
              initialValue: _payerMemberId,
              decoration: const InputDecoration(
                labelText: 'Paid by',
                border: OutlineInputBorder(),
              ),
              items: [
                for (final m in members)
                  DropdownMenuItem(value: m.id, child: Text(m.displayName)),
              ],
              onChanged: (v) => setState(() => _payerMemberId = v),
            ),
            const SizedBox(height: 12),

            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'equal', label: Text('Equally')),
                ButtonSegment(value: 'percent', label: Text('%')),
              ],
              selected: {_splitType},
              onSelectionChanged: (s) =>
                  setState(() => _splitType = s.first),
            ),
            const SizedBox(height: 8),

            for (final m in members)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                dense: true,
                value: _participants.contains(m.id),
                onChanged: (v) => setState(() {
                  if (v ?? false) {
                    _participants = {..._participants, m.id};
                  } else {
                    _participants = {..._participants}..remove(m.id);
                  }
                }),
                title: Text(m.displayName),
                secondary: _splitType == 'percent'
                    ? SizedBox(
                        width: 90,
                        child: TextField(
                          controller: _percent(m.id),
                          textAlign: TextAlign.end,
                          keyboardType:
                              const TextInputType.numberWithOptions(decimal: true),
                          decoration: const InputDecoration(
                            isDense: true,
                            suffixText: '%',
                            border: OutlineInputBorder(),
                          ),
                          onChanged: (_) => setState(() {}),
                        ),
                      )
                    : null,
              ),
            const Divider(height: 24),

            Row(
              children: [
                Text('$selectedCount selected',
                    style: theme.textTheme.labelLarge),
                const Spacer(),
                TextButton(
                  onPressed: () => _setAllSelected(true),
                  child: const Text('All'),
                ),
                TextButton(
                  onPressed: () => _setAllSelected(false),
                  child: const Text('None'),
                ),
                TextButton(
                  onPressed: selectedCount == 0 || categories.isEmpty
                      ? null
                      : () => _tagSelected(categories),
                  child: const Text('Tag selected'),
                ),
              ],
            ),
            const SizedBox(height: 8),

            ImportReviewList(
              rows: visible,
              categories: categories,
              onToggle: (row, selected) =>
                  _replace(row, row.copyWith(selected: selected)),
              onTag: (row) => _tagRow(row, categories),
              onAlwaysTag: (row) => _alwaysTag(row, categories),
            ),

            const SizedBox(height: 8),
            Row(
              children: [
                Icon(
                  plan.valid ? AppIcons.success : AppIcons.info,
                  size: 18,
                  color: plan.valid ? AppColors.of(context).positive : theme.colorScheme.error,
                ),
                const SizedBox(width: 8),
                Expanded(child: Text(plan.status)),
              ],
            ),
          ],
        ),
        Positioned(
          right: 0,
          bottom: 16,
          child: FloatingActionButton.extended(
            onPressed: _submitting || !plan.valid ? null : () => _commit(members),
            icon: _submitting
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(AppIcons.downloadDone),
            label: Text('Import $selectedCount'),
          ),
        ),
      ],
    );
  }
}

// The signed-in user's own member row. A group can hold several real users
// plus guests, so this matches on user_id rather than taking the first
// non-guest.
String? _myMemberId(List<GroupMember> members) {
  final userId = supabase.auth.currentUser?.id;
  if (userId == null) return null;
  for (final m in members) {
    if (m.userId == userId) return m.id;
  }
  return null;
}

class _PickStep extends StatelessWidget {
  const _PickStep({required this.loading, required this.onPick});

  final bool loading;
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  AppIcons.receipt,
                  size: 56,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(height: 16),
                Text('Import a statement',
                    style: theme.textTheme.titleLarge),
                const SizedBox(height: 8),
                Text(
                  'Your statement never leaves this device. Only the expenses '
                  'you confirm are shared with the group.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: loading ? null : onPick,
                  icon: loading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(AppIcons.upload),
                  label: const Text('Choose CSV file'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RangeBar extends StatelessWidget {
  const _RangeBar({
    required this.range,
    required this.onPick,
    required this.onClear,
  });

  final DateTimeRange? range;
  final VoidCallback onPick;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final label = range == null
        ? 'All dates'
        : '${formatDay(range!.start)} – ${formatDayYear(range!.end)}';
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: onPick,
            icon: const Icon(AppIcons.dateRange),
            label: Text(label),
          ),
        ),
        if (range != null)
          IconButton(
            tooltip: 'Clear date filter',
            icon: const Icon(AppIcons.close),
            onPressed: onClear,
          ),
      ],
    );
  }
}

class _DoneStep extends StatelessWidget {
  const _DoneStep({required this.result});

  final ImportResult? result;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final r = result;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(AppIcons.success,
                    size: 56, color: theme.colorScheme.primary),
                const SizedBox(height: 16),
                Text(r?.summary ?? 'Imported',
                    style: theme.textTheme.titleLarge),
                if (r != null && r.skipped > 0) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Skipped transactions were already in this group — '
                    'imported earlier, or by someone else.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: () => context.pop(),
                  child: const Text('Done'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RuleDraft {
  const _RuleDraft({
    required this.pattern,
    required this.action,
    this.categoryId,
  });

  final String pattern;
  final String action;
  final String? categoryId;
}

class _AlwaysTagDialog extends StatefulWidget {
  const _AlwaysTagDialog({
    required this.pattern,
    required this.categories,
    this.initialCategoryId,
  });

  final String pattern;
  final List<Category> categories;
  final String? initialCategoryId;

  @override
  State<_AlwaysTagDialog> createState() => _AlwaysTagDialogState();
}

class _AlwaysTagDialogState extends State<_AlwaysTagDialog> {
  late final _pattern = TextEditingController(text: widget.pattern);
  late String? _categoryId = widget.initialCategoryId;
  bool _share = true;

  @override
  void dispose() {
    _pattern.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Always tag this merchant'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _pattern,
            textCapitalization: TextCapitalization.characters,
            decoration: const InputDecoration(
              labelText: 'Merchant contains',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _categoryId,
            decoration: const InputDecoration(
              labelText: 'Category',
              border: OutlineInputBorder(),
            ),
            items: [
              for (final c in widget.categories)
                DropdownMenuItem(value: c.id, child: Text(c.name)),
            ],
            onChanged: (v) => setState(() => _categoryId = v),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _share,
            onChanged: (v) => setState(() => _share = v),
            title: const Text('Share with the group'),
            subtitle: Text(
              _share
                  ? 'Matching transactions are offered for import'
                  : 'Matching transactions are never offered',
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            final pattern = _pattern.text.trim();
            if (pattern.isEmpty) return;
            Navigator.pop(
              context,
              _RuleDraft(
                pattern: pattern,
                action: _share ? 'share' : 'skip',
                categoryId: _share ? _categoryId : null,
              ),
            );
          },
          child: const Text('Save rule'),
        ),
      ],
    );
  }
}
