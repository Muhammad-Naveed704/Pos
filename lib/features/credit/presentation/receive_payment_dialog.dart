import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/money/money.dart';
import '../../../core/money/money_format.dart';
import '../../../core/ui/ui_kit.dart';
import '../../auth/application/session_controller.dart';
import '../../settings/data/business_settings_repository.dart';
import '../data/credit_service.dart';
import '../domain/credit.dart';

/// Records a payment against a customer account. Pass [customerId] to fix
/// the customer (customer screen); otherwise the user picks one.
/// Returns the result when saved.
Future<PaymentResult?> showReceivePaymentDialog(
  BuildContext context, {
  String? customerId,
}) => showDialog<PaymentResult>(
  context: context,
  builder: (_) => ReceivePaymentDialog(customerId: customerId),
);

class ReceivePaymentDialog extends ConsumerStatefulWidget {
  const ReceivePaymentDialog({this.customerId, super.key});
  final String? customerId;

  @override
  ConsumerState<ReceivePaymentDialog> createState() =>
      _ReceivePaymentDialogState();
}

class _ReceivePaymentDialogState extends ConsumerState<ReceivePaymentDialog> {
  final _amount = TextEditingController();
  final _reference = TextEditingController();
  final _note = TextEditingController();
  final _amountFocus = FocusNode();
  String? _customerId;
  List<(String, String, Money)> _debtors = const [];
  CustomerBalance? _balance;
  List<OpenItem> _items = const [];
  String _method = 'cash';
  DateTime _date = DateTime.now();
  bool _manual = false;
  final Map<String?, TextEditingController> _allocations = {};
  bool _loading = false;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _amount.addListener(() => setState(() {}));
    _customerId = widget.customerId;
    if (_customerId != null) {
      _load(_customerId!);
    } else {
      _loadDebtors();
    }
  }

  @override
  void dispose() {
    _amount.dispose();
    _reference.dispose();
    _note.dispose();
    _amountFocus.dispose();
    for (final controller in _allocations.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _loadDebtors() async {
    try {
      final session = ref.read(activeSessionProvider)!;
      final debtors = await ref.read(creditServiceProvider).debtorList(session);
      if (mounted) {
        setState(
          () => _debtors = [
            for (final d in debtors) (d.customerId, d.name, d.outstanding),
          ],
        );
      }
    } catch (error) {
      if (mounted) setState(() => _error = friendlyError(error));
    }
  }

  Future<void> _load(String customerId) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final session = ref.read(activeSessionProvider)!;
      final service = ref.read(creditServiceProvider);
      final balance = await service.balance(session, customerId);
      final items = await service.openItems(session, customerId);
      if (!mounted) return;
      for (final controller in _allocations.values) {
        controller.dispose();
      }
      _allocations
        ..clear()
        ..addEntries([
          for (final item in items)
            MapEntry(
              item.saleId,
              TextEditingController()..addListener(_changed),
            ),
        ]);
      setState(() {
        _balance = balance;
        _items = items;
        _loading = false;
        if (_amount.text.isEmpty && balance.outstanding.minorUnits > 0) {
          _amount.text = ref
              .read(moneyFormatterProvider)
              .editable(balance.outstanding);
        }
      });
      _amountFocus.requestFocus();
      _amount.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _amount.text.length,
      );
    } catch (error) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = friendlyError(error);
        });
      }
    }
  }

  void _changed() => setState(() {});

  Money get _value => Money.fromMajor(
    ref.read(moneyFormatterProvider).parse(_amount.text) ?? 0,
  );

  Money get _owed =>
      _items.fold(Money.zero, (sum, item) => sum + item.outstanding);

  Map<String?, Money> get _manualPlan => {
    for (final MapEntry(:key, :value) in _allocations.entries)
      key: Money.fromMajor(
        ref.read(moneyFormatterProvider).parse(value.text) ?? 0,
      ),
  };

  Money get _manualTotal =>
      _manualPlan.values.fold(Money.zero, (sum, value) => sum + value);

  /// Oldest-first preview of how the amount will be applied.
  List<AllocationPlan> get _autoPlan {
    try {
      return allocateOldestFirst(_value, _items);
    } catch (_) {
      return const [];
    }
  }

  String? get _problem {
    if (_customerId == null) return 'Choose a customer.';
    if (_value.minorUnits <= 0) return 'Enter the amount received.';
    if (_value.compareTo(_owed) > 0) {
      return 'More than the outstanding balance.';
    }
    if (_manual && _manualTotal != _value) {
      return 'Allocations must add up to the amount.';
    }
    return null;
  }

  Future<void> _save() async {
    if (_problem != null || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await ref
          .read(creditServiceProvider)
          .receivePayment(
            ref.read(activeSessionProvider)!,
            customerId: _customerId!,
            amount: _value,
            method: _method,
            reference: _reference.text,
            note: _note.text,
            receivedAt: _date,
            manualAllocations: _manual ? _manualPlan : null,
          );
      if (mounted) Navigator.pop(context, result);
    } catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = friendlyError(error);
        });
      }
    }
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      firstDate: now.subtract(const Duration(days: 365)),
      lastDate: now,
      initialDate: _date,
    );
    if (picked == null || !mounted) return;
    final time = TimeOfDay.fromDateTime(_date);
    final combined = DateTime(
      picked.year,
      picked.month,
      picked.day,
      time.hour,
      time.minute,
    );
    setState(() => _date = combined.isAfter(now) ? now : combined);
  }

  @override
  Widget build(BuildContext context) {
    final money = ref.watch(moneyFormatterProvider);
    final balance = _balance;
    final problem = _problem;
    final plan = _autoPlan;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.f10): _save,
        const SingleActivator(LogicalKeyboardKey.enter, control: true): _save,
      },
      child: AlertDialog(
        icon: const Icon(Icons.price_check_rounded),
        title: const Text('Receive payment'),
        content: SizedBox(
          width: 620,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (widget.customerId == null)
                  AppSelect<String?>(
                    label: 'Customer',
                    icon: Icons.person_search_rounded,
                    searchable: true,
                    hint: _debtors.isEmpty
                        ? 'No customer owes money'
                        : 'Search customers with a balance',
                    items: [
                      for (final (id, name, owed) in _debtors)
                        SelectItem(
                          id,
                          name,
                          subtitle: 'Owes ${money.format(owed)}',
                        ),
                    ],
                    value: _customerId,
                    onChanged: (id) {
                      if (id == null) return;
                      setState(() {
                        _customerId = id;
                        _amount.clear();
                      });
                      _load(id);
                    },
                  ),
                if (_loading) const LinearProgressIndicator(),
                if (balance != null) ...[
                  if (widget.customerId == null) const SizedBox(height: 12),
                  _BalanceStrip(balance: balance),
                ],
                const SizedBox(height: 16),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _amount,
                        focusNode: _amountFocus,
                        autofocus: true,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                        ),
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                        ],
                        decoration: InputDecoration(
                          labelText: 'Amount received',
                          prefixText: '${money.symbol} ',
                          helperText: balance == null
                              ? null
                              : 'Outstanding ${money.format(_owed)}',
                        ),
                        onSubmitted: (_) => _save(),
                      ),
                    ),
                    const SizedBox(width: 12),
                    OutlinedButton.icon(
                      onPressed: _pickDate,
                      icon: const Icon(Icons.event_rounded),
                      label: Text(DateFormat('d MMM y').format(_date)),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                AppSegmented<String>(
                  expand: true,
                  items: const [
                    SegmentItem('cash', 'Cash', icon: Icons.payments_outlined),
                    SegmentItem(
                      'card',
                      'Card',
                      icon: Icons.credit_card_rounded,
                    ),
                    SegmentItem(
                      'bank',
                      'Bank / wallet',
                      icon: Icons.account_balance_outlined,
                    ),
                    SegmentItem(
                      'other',
                      'Other',
                      icon: Icons.more_horiz_rounded,
                    ),
                  ],
                  value: _method,
                  onChanged: (value) => setState(() => _method = value),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _reference,
                        decoration: const InputDecoration(
                          labelText: 'Reference (optional)',
                          hintText: 'Cheque / transfer no.',
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: _note,
                        decoration: const InputDecoration(
                          labelText: 'Note (optional)',
                        ),
                      ),
                    ),
                  ],
                ),
                if (_items.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Text(
                        'Apply to',
                        style: context.text.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const Spacer(),
                      AppSegmented<bool>(
                        dense: true,
                        items: const [
                          SegmentItem(false, 'Oldest first'),
                          SegmentItem(true, 'Choose invoices'),
                        ],
                        value: _manual,
                        onChanged: (value) => setState(() => _manual = value),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  for (final item in _items)
                    _AllocationRow(
                      item: item,
                      money: money,
                      manual: _manual,
                      controller: _allocations[item.saleId]!,
                      applied: plan
                          .where((p) => p.saleId == item.saleId)
                          .firstOrNull
                          ?.amount,
                    ),
                ],
                if (_error != null ||
                    (problem != null && _value.minorUnits > 0)) ...[
                  const SizedBox(height: 10),
                  Text(
                    _error ?? problem!,
                    style: TextStyle(color: context.colors.error),
                  ),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            onPressed: problem == null && !_busy ? _save : null,
            icon: const Icon(Icons.check_rounded),
            label: Text(
              _value.minorUnits > 0
                  ? 'Receive ${money.format(_value)}'
                  : 'Receive payment',
            ),
          ),
        ],
      ),
    );
  }
}

class _BalanceStrip extends ConsumerWidget {
  const _BalanceStrip({required this.balance});
  final CustomerBalance balance;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final money = ref.watch(moneyFormatterProvider);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.colors.surfaceContainerHigh,
        borderRadius: context.tokens.borderRadius,
      ),
      child: Row(
        children: [
          CircleAvatar(
            child: Text(balance.customer.name.characters.first.toUpperCase()),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  balance.customer.name,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                Text(
                  '${balance.openInvoices} open invoice(s)'
                  '${balance.overdue.minorUnits > 0 ? ' · ${money.format(balance.overdue)} overdue' : ''}',
                  style: context.text.bodySmall,
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('Owes', style: context.text.labelSmall),
              Text(
                money.format(balance.outstanding),
                style: context.text.titleLarge?.copyWith(
                  fontWeight: FontWeight.w900,
                  color: balance.hasBalance ? context.tokens.warning : null,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AllocationRow extends StatelessWidget {
  const _AllocationRow({
    required this.item,
    required this.money,
    required this.manual,
    required this.controller,
    this.applied,
  });
  final OpenItem item;
  final MoneyFormatter money;
  final bool manual;
  final TextEditingController controller;
  final Money? applied;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      children: [
        Expanded(
          flex: 3,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.label,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              Text(
                DateFormat('d MMM y').format(item.date) +
                    (item.dueDate == null
                        ? ''
                        : ' · due ${DateFormat('d MMM').format(item.dueDate!)}'),
                style: context.text.bodySmall,
              ),
            ],
          ),
        ),
        if (item.saleId != null) DueStatusPill(item.dueStatus),
        const SizedBox(width: 10),
        SizedBox(
          width: 110,
          child: Text(money.format(item.outstanding), textAlign: TextAlign.end),
        ),
        const SizedBox(width: 12),
        SizedBox(
          width: 130,
          child: manual
              ? TextField(
                  controller: controller,
                  textAlign: TextAlign.end,
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                  ],
                  decoration: const InputDecoration(
                    isDense: true,
                    hintText: '0',
                  ),
                )
              : Text(
                  applied == null ? '—' : '− ${money.format(applied!)}',
                  textAlign: TextAlign.end,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: applied == null ? null : context.tokens.success,
                  ),
                ),
        ),
      ],
    ),
  );
}

/// Due status shown with an icon and text, never colour alone.
class DueStatusPill extends StatelessWidget {
  const DueStatusPill(this.status, {super.key});
  final DueStatus status;

  @override
  Widget build(BuildContext context) => StatusPill(
    status.label,
    tone: switch (status) {
      DueStatus.overdue => PillTone.danger,
      DueStatus.dueSoon => PillTone.warning,
      DueStatus.current => PillTone.neutral,
    },
    icon: switch (status) {
      DueStatus.overdue => Icons.error_outline_rounded,
      DueStatus.dueSoon => Icons.schedule_rounded,
      DueStatus.current => Icons.check_circle_outline_rounded,
    },
  );
}
