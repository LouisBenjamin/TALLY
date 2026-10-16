import 'package:decimal/decimal.dart';
import 'package:tally/core/icons.dart';
import 'package:tally/core/theme.dart';
import 'package:tally/core/supabase_client.dart';
import 'package:tally/core/widgets/page_body.dart';
import 'package:tally/features/expenses/providers/categories_provider.dart';
import 'package:tally/features/expenses/split_logic.dart';
import 'package:tally/features/expenses/ui/split_editor.dart';
import 'package:tally/features/groups/providers/groups_provider.dart';
import 'package:tally/features/recurring/data/recurring_repository.dart';
import 'package:tally/models/category.dart';
import 'package:tally/models/group_member.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
class AddRecurringScreen extends ConsumerStatefulWidget {
  const AddRecurringScreen({super.key, required this.groupId});
  final String groupId;

  @override
  ConsumerState<AddRecurringScreen> createState() => _AddRecurringScreenState();
}

class _AddRecurringScreenState extends ConsumerState<AddRecurringScreen> {
  final _amountController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _intervalController = TextEditingController(text: '1');
  final _formKey = GlobalKey<FormState>();

  final Map<String, TextEditingController> _exactCtl = {};
  final Map<String, TextEditingController> _percentCtl = {};

  String _splitType = 'equal';
  String _frequency = 'monthly';
  DateTime _startDate = DateTime.now();
  final Set<String> _selected = {};
  String? _payerMemberId;
  String? _categoryId;
  bool _inited = false;
  bool _submitting = false;

  @override
  void dispose() {
    _amountController.dispose();
    _descriptionController.dispose();
    _intervalController.dispose();
    for (final c in _exactCtl.values) {
      c.dispose();
    }
    for (final c in _percentCtl.values) {
      c.dispose();
    }
    super.dispose();
  }

  Decimal get _amount =>
      Decimal.tryParse(_amountController.text.trim()) ?? Decimal.zero;
  int get _interval => int.tryParse(_intervalController.text.trim()) ?? 1;

  TextEditingController _exact(String id) =>
      _exactCtl.putIfAbsent(id, () => TextEditingController());
  TextEditingController _percent(String id) =>
      _percentCtl.putIfAbsent(id, () => TextEditingController());

  SplitOutcome _compute(List<GroupMember> members) => computeSplits(
        splitType: _splitType,
        orderedMemberIds: members.map((m) => m.id).toList(),
        selected: _selected,
        amount: _amount,
        exact: {
          for (final id in _selected)
            id: Decimal.tryParse(_exact(id).text.trim()) ?? Decimal.zero,
        },
        percent: {
          for (final id in _selected)
            id: Decimal.tryParse(_percent(id).text.trim()) ?? Decimal.zero,
        },
      );

  Future<void> _submit(List<GroupMember> members) async {
    if (!_formKey.currentState!.validate()) return;
    if (_payerMemberId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pick who pays')),
      );
      return;
    }
    final result = _compute(members);
    if (!result.valid) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(result.status)));
      return;
    }

    setState(() => _submitting = true);
    try {
      await RecurringRepository().createRecurring(
        groupId: widget.groupId,
        payerMemberId: _payerMemberId!,
        amount: _amount,
        description: _descriptionController.text.trim(),
        splitType: _splitType,
        categoryId: _categoryId,
        frequency: _frequency,
        intervalCount: _interval < 1 ? 1 : _interval,
        nextOccurrence: _startDate,
        splits: result.splits,
      );
      if (mounted) context.pop();
    } on Exception catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final membersAsync = ref.watch(membersProvider(widget.groupId));
    final categories =
        ref.watch(categoriesProvider(widget.groupId)).valueOrNull ??
            const <Category>[];

    return Scaffold(
      appBar: AppBar(title: const Text('New recurring expense')),
      body: PageBody(
        child: membersAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('Error: $e')),
          data: (members) {
            if (members.isEmpty) {
              return const Center(child: Text('No members in this group.'));
            }
            if (!_inited) {
              _selected.addAll(members.map((m) => m.id));
              final myUid = supabase.auth.currentUser?.id;
              _payerMemberId = members
                      .where((m) => m.userId == myUid)
                      .map((m) => m.id)
                      .firstOrNull ??
                  members.first.id;
              _inited = true;
            }
            final compute = _compute(members);

            return Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 96),
                children: [
                  TextFormField(
                    controller: _amountController,
                    autofocus: true,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}')),
                    ],
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(
                      labelText: 'Amount',
                      prefixText: r'$',
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) {
                      final a = Decimal.tryParse((v ?? '').trim());
                      if (a == null || a <= Decimal.zero) {
                        return 'Enter a valid amount';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _descriptionController,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                      labelText: 'Description',
                      hintText: 'e.g. Rent, Netflix, Internet…',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String?>(
                    initialValue: _categoryId,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Category (optional)',
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      const DropdownMenuItem(value: null, child: Text('None')),
                      ...categories.map((c) => DropdownMenuItem(
                            value: c.id,
                            child: Row(
                              children: [
                                Icon(iconForCategory(c.icon), size: 18),
                                const SizedBox(width: 8),
                                Text(c.name),
                              ],
                            ),
                          )),
                    ],
                    onChanged: (v) => setState(() => _categoryId = v),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    initialValue: _payerMemberId,
                    decoration: const InputDecoration(
                      labelText: 'Paid by',
                      border: OutlineInputBorder(),
                    ),
                    items: members
                        .map((m) => DropdownMenuItem(
                              value: m.id,
                              child: Text(m.displayName),
                            ))
                        .toList(),
                    onChanged: (v) => setState(() => _payerMemberId = v),
                  ),
                  const SizedBox(height: 24),
                  Text('Repeats', style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 8),
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'daily', label: Text('Daily')),
                      ButtonSegment(value: 'weekly', label: Text('Weekly')),
                      ButtonSegment(value: 'monthly', label: Text('Monthly')),
                    ],
                    selected: {_frequency},
                    onSelectionChanged: (s) => setState(() => _frequency = s.first),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      const Text('Every'),
                      const SizedBox(width: 12),
                      SizedBox(
                        width: 64,
                        child: TextField(
                          controller: _intervalController,
                          keyboardType: TextInputType.number,
                          textAlign: TextAlign.center,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                          ],
                          onChanged: (_) => setState(() {}),
                          decoration: const InputDecoration(
                            isDense: true,
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(_unitLabel()),
                    ],
                  ),
                  const SizedBox(height: 16),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(AppIcons.dateRange),
                    title: const Text('Starts on'),
                    trailing: Text(DateFormat('MMM d, yyyy').format(_startDate)),
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: _startDate,
                        firstDate: DateTime.now().subtract(const Duration(days: 365)),
                        lastDate: DateTime.now().add(const Duration(days: 365 * 5)),
                      );
                      if (picked != null) setState(() => _startDate = picked);
                    },
                  ),
                  const SizedBox(height: 24),
                  Text('Split', style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 8),
                  SplitTypeSelector(
                    value: _splitType,
                    onChanged: (v) => setState(() => _splitType = v),
                  ),
                  const SizedBox(height: 8),
                  ...members.map((m) => ParticipantSplitRow(
                        member: m,
                        included: _selected.contains(m.id),
                        splitType: _splitType,
                        equalShare:
                            _splitType == 'equal' && _selected.contains(m.id)
                                ? compute.splits
                                    .where((s) => s.memberId == m.id)
                                    .map((s) => s.shareAmount)
                                    .firstOrNull
                                : null,
                        exactController: _exact(m.id),
                        percentController: _percent(m.id),
                        onToggle: (on) => setState(() {
                          if (on) {
                            _selected.add(m.id);
                          } else {
                            _selected.remove(m.id);
                          }
                        }),
                        onChanged: () => setState(() {}),
                      )),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(
                        compute.valid ? AppIcons.success : AppIcons.info,
                        size: 18,
                        color: compute.valid
                            ? AppColors.of(context).positive
                            : Theme.of(context).colorScheme.error,
                      ),
                      const SizedBox(width: 8),
                      Expanded(child: Text(compute.status)),
                    ],
                  ),
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: _submitting || !compute.valid
                        ? null
                        : () => _submit(members),
                    child: _submitting
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Save recurring expense'),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  String _unitLabel() {
    final plural = _interval != 1;
    return switch (_frequency) {
      'daily' => plural ? 'days' : 'day',
      'weekly' => plural ? 'weeks' : 'week',
      _ => plural ? 'months' : 'month',
    };
  }
}
