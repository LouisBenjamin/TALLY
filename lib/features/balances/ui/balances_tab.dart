import 'package:decimal/decimal.dart';
import 'package:tally/core/dates.dart';
import 'package:tally/core/icons.dart';
import 'package:tally/core/theme.dart';
import 'package:tally/core/money.dart';
import 'package:tally/core/supabase_client.dart';
import 'package:tally/features/balances/data/balances_repository.dart';
import 'package:tally/features/balances/logic/settle.dart';
import 'package:tally/features/balances/providers/balances_provider.dart';
import 'package:tally/features/groups/providers/groups_provider.dart';
import 'package:tally/models/group_member.dart';
import 'package:tally/models/settlement.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class BalancesTab extends ConsumerWidget {
  const BalancesTab({super.key, required this.groupId});
  final String groupId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final balancesAsync = ref.watch(balancesProvider(groupId));
    final members =
        ref.watch(membersProvider(groupId)).valueOrNull ?? const <GroupMember>[];
    final payments =
        ref.watch(settlementsProvider(groupId)).valueOrNull ?? const <Settlement>[];
    final theme = Theme.of(context);

    return balancesAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
      data: (balances) {
        final nameOf = {for (final m in members) m.id: m.displayName};
        String name(String id) => nameOf[id] ?? 'Former member';

        final owing = balances.where((b) => b.net != Decimal.zero).toList()
          ..sort((a, b) => b.net.compareTo(a.net));
        final transfers = simplifyDebts(balances);

        void openPayment({DebtTransfer? suggested, Settlement? existing}) =>
            showDialog<void>(
              context: context,
              builder: (_) => PaymentDialog(
                groupId: groupId,
                members: members,
                suggested: suggested,
                existing: existing,
              ),
            );

        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
          children: [
            if (owing.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Column(
                  children: [
                    Icon(AppIcons.success,
                        size: 64, color: AppColors.of(context).positive),
                    const SizedBox(height: 16),
                    Text('All settled up',
                        style: Theme.of(context).textTheme.titleMedium),
                  ],
                ),
              )
            else ...[
              Text('Balances', style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              ...owing.map((b) => _BalanceRow(name: name(b.memberId), net: b.net)),
            ],
            if (transfers.isNotEmpty) ...[
              const SizedBox(height: 24),
              Text('Suggested settlements', style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              ...transfers.map((t) => Card(
                    child: ListTile(
                      leading: const Icon(AppIcons.arrowForward),
                      title: Text('${name(t.fromMemberId)} → ${name(t.toMemberId)}'),
                      titleTextStyle: theme.textTheme.titleSmall,
                      subtitle: Text(formatCurrency(t.amount)),
                      trailing: TextButton(
                        onPressed: () => openPayment(suggested: t),
                        child: const Text('Settle up'),
                      ),
                    ),
                  )),
            ],
            const SizedBox(height: 16),
            if (members.length >= 2)
              OutlinedButton.icon(
                onPressed: openPayment,
                icon: const Icon(AppIcons.add),
                label: const Text('Record a payment'),
              ),
            if (payments.isNotEmpty) ...[
              const SizedBox(height: 24),
              Text('Payments', style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              ...payments.map((p) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(AppIcons.doneAll),
                    title: Text('${name(p.fromMemberId)} paid ${name(p.toMemberId)}'),
                    subtitle: Text(formatDayYear(p.occurredOn)),
                    trailing: Text(formatCurrency(p.amount),
                        style: theme.textTheme.titleSmall),
                    onTap: () => openPayment(existing: p),
                  )),
            ],
          ],
        );
      },
    );
  }
}

class _BalanceRow extends StatelessWidget {
  const _BalanceRow({required this.name, required this.net});
  final String name;
  final Decimal net;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final owed = net > Decimal.zero;
    final color = owed ? AppColors.of(context).positive : theme.colorScheme.error;
    final label = owed ? 'gets back' : 'owes';
    final abs = owed ? net : Decimal.zero - net;

    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(
        backgroundColor: theme.colorScheme.surfaceContainerHighest,
        child: Text(name.isNotEmpty ? name.substring(0, 1).toUpperCase() : '?'),
      ),
      title: Text(name),
      subtitle: Text(label),
      trailing: Text(
        formatCurrency(abs),
        style: theme.textTheme.titleMedium?.copyWith(
          color: color,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

// Records a new payment (blank, or prefilled from a suggestion) or edits /
// deletes an [existing] one. The amount is editable either way, so a partial
// payment is just a smaller number.
class PaymentDialog extends ConsumerStatefulWidget {
  const PaymentDialog({
    super.key,
    required this.groupId,
    required this.members,
    this.suggested,
    this.existing,
  });
  final String groupId;
  final List<GroupMember> members;
  final DebtTransfer? suggested;
  final Settlement? existing;

  @override
  ConsumerState<PaymentDialog> createState() => _PaymentDialogState();
}

class _PaymentDialogState extends ConsumerState<PaymentDialog> {
  late String? _from;
  late String? _to;
  late final TextEditingController _amount;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    final s = widget.suggested;
    final myId = widget.members
        .where((m) => m.userId == supabase.auth.currentUser?.id)
        .map((m) => m.id)
        .firstOrNull;
    _from = e?.fromMemberId ?? s?.fromMemberId ?? myId;
    _to = e?.toMemberId ?? s?.toMemberId;
    _amount = TextEditingController(
        text: (e?.amount ?? s?.amount)?.toStringAsFixed(2) ?? '');
  }

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  // A payment naming someone who has left can't be shown in the dropdowns
  // (they're not in the list), so it can only be deleted.
  bool get _editable {
    final ids = {for (final m in widget.members) m.id};
    final e = widget.existing;
    return e == null || (ids.contains(e.fromMemberId) && ids.contains(e.toMemberId));
  }

  Decimal? get _parsedAmount {
    final a = Decimal.tryParse(_amount.text.trim());
    return a != null && a > Decimal.zero ? a : null;
  }

  bool get _valid =>
      _from != null && _to != null && _from != _to && _parsedAmount != null;

  Future<void> _run(Future<void> Function(BalancesRepository repo) action) async {
    setState(() => _saving = true);
    try {
      await action(BalancesRepository());
      invalidateGroupMoney(ref, widget.groupId);
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

  void _save() {
    final e = widget.existing;
    _run((repo) => e == null
        ? repo.settle(
            groupId: widget.groupId,
            fromMemberId: _from!,
            toMemberId: _to!,
            amount: _parsedAmount!,
          )
        : repo.updateSettlement(
            id: e.id,
            fromMemberId: _from!,
            toMemberId: _to!,
            amount: _parsedAmount!,
          ));
  }

  Widget _memberPicker(String label, String? value, ValueChanged<String?> onChanged) =>
      DropdownButtonFormField<String>(
        initialValue: value,
        isExpanded: true,
        decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
        items: [
          for (final m in widget.members)
            DropdownMenuItem(value: m.id, child: Text(m.displayName)),
        ],
        onChanged: (v) => setState(() => onChanged(v)),
      );

  @override
  Widget build(BuildContext context) {
    final existing = widget.existing;
    return AlertDialog(
      title: Text(existing == null ? 'Record a payment' : 'Payment'),
      content: !_editable
          ? const Text('This payment involves someone who has left the group, '
              'so it can only be deleted.')
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _memberPicker('Who paid', _from, (v) => _from = v),
                const SizedBox(height: 12),
                _memberPicker('Who received it', _to, (v) => _to = v),
                const SizedBox(height: 12),
                TextField(
                  controller: _amount,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}')),
                  ],
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    labelText: 'Amount',
                    prefixText: r'$',
                    border: OutlineInputBorder(),
                  ),
                ),
                if (_from != null && _from == _to)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text('Pick two different people.',
                        style: TextStyle(color: Theme.of(context).colorScheme.error)),
                  ),
              ],
            ),
      actions: [
        if (existing != null)
          TextButton(
            onPressed: _saving
                ? null
                : () => _run((repo) => repo.deleteSettlement(id: existing.id)),
            child: const Text('Delete'),
          ),
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        if (_editable)
          FilledButton(
            onPressed: _saving || !_valid ? null : _save,
            child: const Text('Save'),
          ),
      ],
    );
  }
}
