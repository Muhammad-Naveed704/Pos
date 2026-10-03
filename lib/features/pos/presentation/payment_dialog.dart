import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../../core/money/money.dart';
import '../../../core/money/money_format.dart';
import '../../../core/ui/ui_kit.dart';
import '../domain/pos_cart.dart';

enum TenderMethod {
  cash('Cash', Icons.payments_outlined),
  card('Card', Icons.credit_card_rounded),
  bank('Bank / wallet', Icons.account_balance_outlined),
  other('Other', Icons.more_horiz_rounded);

  const TenderMethod(this.label, this.icon);
  final String label;
  final IconData icon;
}

/// How much of the invoice is paid now.
enum PayMode {
  full('Pay in full', Icons.check_circle_outline_rounded),
  partial('Partial', Icons.pie_chart_outline_rounded),
  credit('Credit', Icons.account_balance_wallet_outlined);

  const PayMode(this.label, this.icon);
  final String label;
  final IconData icon;
}

enum DuePreset {
  none('No due date', null),
  today('Today', 0),
  week('7 days', 7),
  fortnight('15 days', 15),
  month('30 days', 30),
  custom('Custom…', null);

  const DuePreset(this.label, this.days);
  final String label;
  final int? days;
}

/// The customer a credit sale is charged to, with their current account.
class CreditCustomer {
  const CreditCustomer({
    required this.id,
    required this.name,
    required this.outstanding,
    required this.limit,
  });
  final String id;
  final String name;
  final Money outstanding;
  final Money limit;

  Money get available => (limit - outstanding).max(Money.zero);
}

class PaymentDecision {
  const PaymentDecision({
    required this.payments,
    this.dueDate,
    this.customerId,
  });
  final List<PaymentInput> payments;
  final DateTime? dueDate;

  /// Customer chosen inside the dialog (credit sales).
  final String? customerId;
}

/// Opens the tender dialog and returns the payments, or null if cancelled.
/// Partial and credit modes appear only when [allowCredit] is true.
Future<PaymentDecision?> showPaymentDialog(
  BuildContext context, {
  required Money total,
  required MoneyFormatter money,
  required List<int> denominations,
  bool allowCredit = false,
  CreditCustomer? customer,
  Future<CreditCustomer?> Function()? onPickCustomer,
  PayMode initialMode = PayMode.full,
}) => showDialog<PaymentDecision>(
  context: context,
  builder: (context) => PaymentDialog(
    total: total,
    money: money,
    denominations: denominations,
    allowCredit: allowCredit,
    customer: customer,
    onPickCustomer: onPickCustomer,
    initialMode: initialMode,
  ),
);

class PaymentDialog extends StatefulWidget {
  const PaymentDialog({
    required this.total,
    required this.money,
    required this.denominations,
    this.allowCredit = false,
    this.customer,
    this.onPickCustomer,
    this.initialMode = PayMode.full,
    super.key,
  });

  final Money total;
  final MoneyFormatter money;
  final List<int> denominations;
  final bool allowCredit;
  final CreditCustomer? customer;
  final Future<CreditCustomer?> Function()? onPickCustomer;
  final PayMode initialMode;

  @override
  State<PaymentDialog> createState() => _PaymentDialogState();
}

class _Tender {
  _Tender(this.id, this.method, String amount)
    : controller = TextEditingController(text: amount),
      focus = FocusNode();
  final int id;
  TenderMethod method;
  final TextEditingController controller;
  final FocusNode focus;

  void dispose() {
    controller.dispose();
    focus.dispose();
  }
}

class _PaymentDialogState extends State<PaymentDialog> {
  final _tenders = <_Tender>[];
  var _nextId = 0;
  int _active = 0;
  late PayMode _mode = widget.allowCredit ? widget.initialMode : PayMode.full;
  late CreditCustomer? _customer = widget.customer;
  DuePreset _due = DuePreset.week;
  DateTime? _customDue;

  @override
  void initState() {
    super.initState();
    _add(
      TenderMethod.cash,
      _mode == PayMode.partial ? Money.zero : widget.total,
    );
  }

  @override
  void dispose() {
    for (final tender in _tenders) {
      tender.dispose();
    }
    super.dispose();
  }

  void _add(TenderMethod method, Money amount) {
    final tender = _Tender(_nextId++, method, widget.money.editable(amount));
    tender.controller.selection = TextSelection(
      baseOffset: 0,
      extentOffset: tender.controller.text.length,
    );
    tender.controller.addListener(() => setState(() {}));
    _tenders.add(tender);
    _active = _tenders.length - 1;
  }

  Money _amountOf(_Tender tender) {
    final value = widget.money.parse(tender.controller.text) ?? 0;
    return Money.fromMajor(value < 0 ? 0 : value);
  }

  Money get _paid => _mode == PayMode.credit
      ? Money.zero
      : _tenders.fold(Money.zero, (sum, tender) => sum + _amountOf(tender));

  Money get _cash => _tenders
      .where((tender) => tender.method == TenderMethod.cash)
      .fold(Money.zero, (sum, tender) => sum + _amountOf(tender));

  Money get _remaining => (widget.total - _paid).max(Money.zero);
  Money get _change => (_paid - widget.total).max(Money.zero);

  bool get _changeExceedsCash => _change.compareTo(_cash) > 0;

  bool get _onAccount => _mode != PayMode.full;

  DateTime? get _dueDate {
    if (!_onAccount) return null;
    final today = DateTime.now();
    final start = DateTime(today.year, today.month, today.day);
    return switch (_due) {
      DuePreset.none => null,
      DuePreset.custom => _customDue,
      _ => start.add(Duration(days: _due.days!)),
    };
  }

  bool get _ready => switch (_mode) {
    PayMode.full =>
      _paid.compareTo(widget.total) >= 0 &&
          !_changeExceedsCash &&
          _tenders.any((tender) => _amountOf(tender).minorUnits > 0),
    PayMode.partial =>
      _customer != null &&
          _paid.minorUnits > 0 &&
          _paid.compareTo(widget.total) < 0 &&
          (_due != DuePreset.custom || _customDue != null),
    PayMode.credit =>
      _customer != null && (_due != DuePreset.custom || _customDue != null),
  };

  void _complete() {
    if (!_ready) return;
    Navigator.pop(
      context,
      PaymentDecision(
        payments: [
          if (_mode != PayMode.credit)
            for (final tender in _tenders)
              if (_amountOf(tender).minorUnits > 0)
                PaymentInput(
                  method: tender.method.name,
                  amount: _amountOf(tender),
                ),
        ],
        dueDate: _dueDate,
        customerId: _customer?.id,
      ),
    );
  }

  void _setMode(PayMode mode) {
    setState(() {
      _mode = mode;
      if (mode == PayMode.full) {
        // Back to paying everything: top up the active tender.
        final missing = _remaining;
        if (missing.minorUnits > 0) {
          final tender = _tenders[_active];
          tender.controller.text = widget.money.editable(
            _amountOf(tender) + missing,
          );
        }
      } else if (mode == PayMode.partial &&
          _paid.compareTo(widget.total) >= 0) {
        for (final tender in _tenders) {
          tender.controller.text = widget.money.editable(Money.zero);
        }
      }
    });
    if (mode != PayMode.credit) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final tender = _tenders[_active];
        tender.focus.requestFocus();
        tender.controller.selection = TextSelection(
          baseOffset: 0,
          extentOffset: tender.controller.text.length,
        );
      });
    }
  }

  Future<void> _pickCustomer() async {
    final pick = widget.onPickCustomer;
    if (pick == null) return;
    final customer = await pick();
    if (customer != null && mounted) setState(() => _customer = customer);
  }

  Future<void> _pickDue(DuePreset preset) async {
    if (preset != DuePreset.custom) {
      setState(() => _due = preset);
      return;
    }
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: DateTime(now.year + 2),
      initialDate: _customDue ?? now.add(const Duration(days: 45)),
    );
    if (picked != null && mounted) {
      setState(() {
        _due = DuePreset.custom;
        _customDue = picked;
      });
    }
  }

  void _setActiveAmount(Money amount) {
    final tender = _tenders[_active];
    tender.controller.text = widget.money.editable(amount);
    tender.controller.selection = TextSelection.collapsed(
      offset: tender.controller.text.length,
    );
    tender.focus.requestFocus();
  }

  void _addSplit() {
    setState(() {
      _add(
        _tenders.any((tender) => tender.method == TenderMethod.card)
            ? TenderMethod.bank
            : TenderMethod.card,
        _mode == PayMode.partial ? Money.zero : _remaining,
      );
    });
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _tenders.last.focus.requestFocus(),
    );
  }

  void _remove(int index) {
    setState(() {
      _tenders.removeAt(index).dispose();
      _active = _active.clamp(0, _tenders.length - 1);
    });
  }

  /// Exact amount plus the next sensible round-up notes.
  List<Money> _suggestions() {
    final due = _remaining.minorUnits == 0 ? widget.total : _remaining;
    final major = due.majorUnits;
    final values = <double>{major};
    for (final step in const [10, 50, 100, 500, 1000, 5000]) {
      final rounded = (major / step).ceilToDouble() * step;
      if (rounded > major) values.add(rounded);
    }
    for (final note in widget.denominations) {
      if (note >= major) values.add(note.toDouble());
    }
    final sorted = values.toList()..sort();
    return sorted.take(6).map(Money.fromMajor).toList();
  }

  @override
  Widget build(BuildContext context) {
    final money = widget.money;
    final tokens = context.tokens;
    final ready = _ready;
    final credit = _mode == PayMode.credit;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.f10): _complete,
        const SingleActivator(LogicalKeyboardKey.enter, control: true):
            _complete,
        const SingleActivator(LogicalKeyboardKey.f3): _pickCustomer,
      },
      child: Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 660, maxHeight: 720),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const IconTile(icon: Icons.payments_rounded, size: 42),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Take payment',
                            style: context.text.titleLarge?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          Text(
                            switch (_mode) {
                              PayMode.full => 'Enter amounts received. Split across methods if needed.',
                              PayMode.partial => 'Take part now; the rest goes on the customer account.',
                              PayMode.credit => 'Nothing paid now; the whole invoice goes on account.',
                            },
                            style: TextStyle(
                              color: context.colors.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Cancel (Esc)',
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
                if (widget.allowCredit) ...[
                  const SizedBox(height: 14),
                  AppSegmented<PayMode>(
                    expand: true,
                    items: [
                      for (final mode in PayMode.values)
                        SegmentItem(mode, mode.label, icon: mode.icon),
                    ],
                    value: _mode,
                    onChanged: _setMode,
                  ),
                ],
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: context.colors.primaryContainer,
                    borderRadius: tokens.borderRadius,
                  ),
                  child: Row(
                    children: [
                      Text(
                        _onAccount ? 'Invoice total' : 'Amount due',
                        style: TextStyle(
                          color: context.colors.onPrimaryContainer,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        money.format(widget.total),
                        style: context.text.headlineMedium?.copyWith(
                          fontWeight: FontWeight.w900,
                          color: context.colors.onPrimaryContainer,
                          letterSpacing: -0.5,
                        ),
                      ),
                    ],
                  ),
                ),
                if (_onAccount) ...[
                  const SizedBox(height: 12),
                  _customerPanel(context, money),
                ],
                const SizedBox(height: 16),
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      if (!credit)
                        for (var index = 0; index < _tenders.length; index++)
                          _TenderRow(
                            key: ValueKey(_tenders[index].id),
                            tender: _tenders[index],
                            active: index == _active,
                            money: money,
                            removable: _tenders.length > 1,
                            onFocus: () => setState(() => _active = index),
                            onMethod: (method) =>
                                setState(() => _tenders[index].method = method),
                            onRemove: () => _remove(index),
                            onSubmit: _complete,
                          ),
                      if (_onAccount) _dueDatePicker(context),
                    ],
                  ),
                ),
                if (!credit)
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if (_mode == PayMode.full)
                        for (final amount in _suggestions())
                          ActionChip(
                            avatar: const Icon(Icons.bolt_rounded, size: 16),
                            label: Text(money.format(amount)),
                            onPressed: () => _setActiveAmount(amount),
                          ),
                      ActionChip(
                        avatar: const Icon(Icons.call_split_rounded, size: 16),
                        label: const Text('Split payment'),
                        onPressed:
                            _mode == PayMode.full && _remaining.minorUnits == 0
                            ? null
                            : _addSplit,
                      ),
                    ],
                  ),
                const SizedBox(height: 18),
                const Divider(),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _Figure(
                        label: _onAccount ? 'Paid now' : 'Received',
                        value: money.format(_paid),
                      ),
                    ),
                    Expanded(
                      child: _onAccount
                          ? _Figure(
                              label: 'Remaining on account',
                              value: money.format(_remaining),
                              color: tokens.warning,
                              large: true,
                            )
                          : _remaining.minorUnits > 0
                          ? _Figure(
                              label: 'Remaining',
                              value: money.format(_remaining),
                              color: context.colors.error,
                            )
                          : _Figure(
                              label: 'Change to return',
                              value: money.format(_change),
                              color: tokens.success,
                              large: true,
                            ),
                    ),
                  ],
                ),
                if (_mode == PayMode.full && _changeExceedsCash)
                  _Warning(
                    'Change can only be given from cash. Reduce the card/bank amount.',
                  ),
                if (_mode == PayMode.partial &&
                    _paid.compareTo(widget.total) >= 0)
                  _Warning(
                    'The amount covers the whole invoice. Use "Pay in full" instead.',
                  ),
                const SizedBox(height: 18),
                SizedBox(
                  height: 54,
                  child: FilledButton(
                    onPressed: ready ? _complete : null,
                    style: FilledButton.styleFrom(
                      backgroundColor: _onAccount
                          ? tokens.warning
                          : tokens.success,
                      foregroundColor: _onAccount
                          ? Colors.white
                          : tokens.onSuccess,
                      textStyle: context.text.labelLarge?.copyWith(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          _onAccount
                              ? Icons.account_balance_wallet_rounded
                              : Icons.check_circle_rounded,
                        ),
                        const SizedBox(width: 10),
                        Text(
                          _onAccount ? 'Complete credit sale' : 'Complete sale',
                        ),
                        const SizedBox(width: 10),
                        KeyHint('F10', onPrimary: ready),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _customerPanel(BuildContext context, MoneyFormatter money) {
    final customer = _customer;
    final tokens = context.tokens;
    if (customer == null) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: tokens.warningContainer,
          borderRadius: tokens.borderRadius,
        ),
        child: Row(
          children: [
            Icon(Icons.person_search_rounded, color: tokens.warning),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'Select a customer to create a credit sale. Walk-in sales must be paid in full.',
              ),
            ),
            const SizedBox(width: 12),
            FilledButton.tonalIcon(
              onPressed: widget.onPickCustomer == null ? null : _pickCustomer,
              icon: const Icon(Icons.person_add_alt_1_rounded),
              label: const Text('Select customer (F3)'),
            ),
          ],
        ),
      );
    }
    final projected = customer.outstanding + _remaining;
    final over = projected.compareTo(customer.limit) > 0;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        border: Border.all(color: context.colors.outlineVariant),
        borderRadius: tokens.borderRadius,
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 18,
            child: Text(customer.name.characters.first.toUpperCase()),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  customer.name,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                Text(
                  'Owes ${money.format(customer.outstanding)} · '
                  'limit ${money.format(customer.limit)} · '
                  'after sale ${money.format(projected)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.text.bodySmall?.copyWith(
                    color: context.colors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          if (over)
            const StatusPill(
              'Over limit',
              tone: PillTone.danger,
              icon: Icons.block_rounded,
            )
          else
            const StatusPill(
              'Within limit',
              tone: PillTone.success,
              icon: Icons.verified_outlined,
            ),
          if (widget.onPickCustomer != null)
            IconButton(
              tooltip: 'Change customer (F3)',
              onPressed: _pickCustomer,
              icon: const Icon(Icons.swap_horiz_rounded),
            ),
        ],
      ),
    );
  }

  Widget _dueDatePicker(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10, top: 2),
    child: Row(
      children: [
        Icon(
          Icons.event_rounded,
          size: 18,
          color: context.colors.onSurfaceVariant,
        ),
        const SizedBox(width: 8),
        Text('Due', style: context.text.labelLarge),
        const SizedBox(width: 12),
        Expanded(
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final preset in DuePreset.values)
                ChoiceChip(
                  label: Text(
                    preset == DuePreset.custom && _customDue != null
                        ? DateFormat('d MMM y').format(_customDue!)
                        : preset.label,
                  ),
                  selected: _due == preset,
                  showCheckmark: false,
                  onSelected: (_) => _pickDue(preset),
                ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _Warning extends StatelessWidget {
  const _Warning(this.message);
  final String message;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 10),
    child: Row(
      children: [
        Icon(
          Icons.warning_amber_rounded,
          size: 18,
          color: context.tokens.warning,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(message, style: TextStyle(color: context.tokens.warning)),
        ),
      ],
    ),
  );
}

class _TenderRow extends StatelessWidget {
  const _TenderRow({
    required this.tender,
    required this.active,
    required this.money,
    required this.removable,
    required this.onFocus,
    required this.onMethod,
    required this.onRemove,
    required this.onSubmit,
    super.key,
  });

  final _Tender tender;
  final bool active;
  final MoneyFormatter money;
  final bool removable;
  final VoidCallback onFocus;
  final ValueChanged<TenderMethod> onMethod;
  final VoidCallback onRemove;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Row(
      children: [
        AppSegmented<TenderMethod>(
          items: [
            for (final method in TenderMethod.values)
              SegmentItem(
                method,
                null,
                icon: method.icon,
                tooltip: method.label,
              ),
          ],
          value: tender.method,
          onChanged: (value) => onMethod(value),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Focus(
            onFocusChange: (focused) {
              if (focused) onFocus();
            },
            child: TextField(
              controller: tender.controller,
              focusNode: tender.focus,
              autofocus: active,
              textAlign: TextAlign.end,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
              ],
              decoration: InputDecoration(
                labelText: tender.method.label,
                prefixText: '${money.symbol} ',
              ),
              onSubmitted: (_) => onSubmit(),
            ),
          ),
        ),
        if (removable)
          IconButton(
            tooltip: 'Remove',
            onPressed: onRemove,
            icon: const Icon(Icons.remove_circle_outline_rounded),
          ),
      ],
    ),
  );
}

class _Figure extends StatelessWidget {
  const _Figure({
    required this.label,
    required this.value,
    this.color,
    this.large = false,
  });
  final String label;
  final String value;
  final Color? color;
  final bool large;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: TextStyle(color: context.colors.onSurfaceVariant)),
      const SizedBox(height: 2),
      Text(
        value,
        style: (large ? context.text.headlineSmall : context.text.titleLarge)
            ?.copyWith(fontWeight: FontWeight.w800, color: color),
      ),
    ],
  );
}
