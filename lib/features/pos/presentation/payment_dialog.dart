import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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

/// Opens the tender dialog and returns the payments, or null if cancelled.
Future<List<PaymentInput>?> showPaymentDialog(
  BuildContext context, {
  required Money total,
  required MoneyFormatter money,
  required List<int> denominations,
}) => showDialog<List<PaymentInput>>(
  context: context,
  builder: (context) =>
      PaymentDialog(total: total, money: money, denominations: denominations),
);

class PaymentDialog extends StatefulWidget {
  const PaymentDialog({
    required this.total,
    required this.money,
    required this.denominations,
    super.key,
  });

  final Money total;
  final MoneyFormatter money;
  final List<int> denominations;

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

  @override
  void initState() {
    super.initState();
    _add(TenderMethod.cash, widget.total);
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

  Money get _paid =>
      _tenders.fold(Money.zero, (sum, tender) => sum + _amountOf(tender));

  Money get _cash => _tenders
      .where((tender) => tender.method == TenderMethod.cash)
      .fold(Money.zero, (sum, tender) => sum + _amountOf(tender));

  Money get _remaining => (widget.total - _paid).max(Money.zero);
  Money get _change => (_paid - widget.total).max(Money.zero);

  bool get _changeExceedsCash => _change.compareTo(_cash) > 0;

  bool get _ready =>
      _paid.compareTo(widget.total) >= 0 &&
      !_changeExceedsCash &&
      _tenders.any((tender) => _amountOf(tender).minorUnits > 0);

  void _complete() {
    if (!_ready) return;
    Navigator.pop(context, [
      for (final tender in _tenders)
        if (_amountOf(tender).minorUnits > 0)
          PaymentInput(method: tender.method.name, amount: _amountOf(tender)),
    ]);
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
        _remaining,
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
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.f10): _complete,
        const SingleActivator(LogicalKeyboardKey.enter, control: true):
            _complete,
      },
      child: Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640, maxHeight: 640),
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
                            'Enter amounts received. Split across methods if needed.',
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
                const SizedBox(height: 18),
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: context.colors.primaryContainer,
                    borderRadius: tokens.borderRadius,
                  ),
                  child: Row(
                    children: [
                      Text(
                        'Amount due',
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
                const SizedBox(height: 16),
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    children: [
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
                    ],
                  ),
                ),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final amount in _suggestions())
                      ActionChip(
                        avatar: const Icon(Icons.bolt_rounded, size: 16),
                        label: Text(money.format(amount)),
                        onPressed: () => _setActiveAmount(amount),
                      ),
                    ActionChip(
                      avatar: const Icon(Icons.call_split_rounded, size: 16),
                      label: const Text('Split payment'),
                      onPressed: _remaining.minorUnits == 0 ? null : _addSplit,
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
                        label: 'Received',
                        value: money.format(_paid),
                      ),
                    ),
                    Expanded(
                      child: _remaining.minorUnits > 0
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
                if (_changeExceedsCash) ...[
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Icon(
                        Icons.warning_amber_rounded,
                        size: 18,
                        color: tokens.warning,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Change can only be given from cash. Reduce the card/bank amount.',
                          style: TextStyle(color: tokens.warning),
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 18),
                SizedBox(
                  height: 54,
                  child: FilledButton(
                    onPressed: ready ? _complete : null,
                    style: FilledButton.styleFrom(
                      backgroundColor: tokens.success,
                      foregroundColor: tokens.onSuccess,
                      textStyle: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.check_circle_rounded),
                        const SizedBox(width: 10),
                        const Text('Complete sale'),
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
        SegmentedButton<TenderMethod>(
          showSelectedIcon: false,
          segments: [
            for (final method in TenderMethod.values)
              ButtonSegment(
                value: method,
                icon: Icon(method.icon, size: 18),
                tooltip: method.label,
              ),
          ],
          selected: {tender.method},
          onSelectionChanged: (value) => onMethod(value.first),
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
