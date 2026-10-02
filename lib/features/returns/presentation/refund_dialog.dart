import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/money/money.dart';
import '../../../core/ui/ui_kit.dart';
import '../../auth/application/session_controller.dart';
import '../../receipts/data/receipt_service.dart';
import '../../settings/data/business_settings_repository.dart';
import '../data/refund_service.dart';

String _qty(double value) => value == value.roundToDouble()
    ? value.toStringAsFixed(0)
    : value.toStringAsFixed(3).replaceFirst(RegExp(r'0+$'), '');

/// Opens the return/refund flow for a sale. Returns true when a refund was
/// recorded.
Future<bool> showRefundDialog(BuildContext context, String saleId) async =>
    await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _RefundDialog(saleId: saleId),
    ) ??
    false;

/// Asks for an invoice number (or a scanned receipt barcode) and opens the
/// refund flow for it.
Future<void> startReturnByInvoice(BuildContext context, WidgetRef ref) async {
  final invoice = await promptDialog(
    context,
    title: 'Return items',
    label: 'Invoice number',
    hint: 'Scan the receipt barcode or type the invoice number',
    confirmLabel: 'Find sale',
  );
  if (invoice == null || invoice.trim().isEmpty || !context.mounted) return;
  final saleId = await ref
      .read(refundServiceProvider)
      .findByInvoice(ref.read(activeSessionProvider)!, invoice);
  if (!context.mounted) return;
  if (saleId == null) {
    Toast.show(
      context,
      'No sale ${invoice.trim().toUpperCase()} in this store.',
      tone: PillTone.warning,
    );
    return;
  }
  await showRefundDialog(context, saleId);
}

class _Line {
  _Line(this.line)
    : quantity = TextEditingController(),
      restock = line.tracksStock;
  final RefundableLine line;
  final TextEditingController quantity;
  bool restock;
}

class _RefundDialog extends ConsumerStatefulWidget {
  const _RefundDialog({required this.saleId});
  final String saleId;
  @override
  ConsumerState<_RefundDialog> createState() => _RefundDialogState();
}

class _RefundDialogState extends ConsumerState<_RefundDialog> {
  late final Future<SaleReturnState> _load = ref
      .read(refundServiceProvider)
      .load(ref.read(activeSessionProvider)!, widget.saleId);
  List<_Line>? _lines;
  String? _method;
  String _reason = refundReasons.first;
  final _note = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    for (final line in _lines ?? const <_Line>[]) {
      line.quantity.dispose();
    }
    _note.dispose();
    super.dispose();
  }

  double _entered(_Line line) =>
      ref.read(moneyFormatterProvider).parse(line.quantity.text) ?? 0;

  Money _preview(SaleReturnState state) {
    var total = Money.zero;
    var everything = true;
    for (final line in _lines!) {
      final qty = _entered(line).clamp(0, line.line.remaining).toDouble();
      total += line.line.amountFor(qty);
      if (line.line.remaining - qty > 1e-9) everything = false;
    }
    if (everything || total.compareTo(state.remaining) > 0) {
      return state.remaining;
    }
    return total;
  }

  void _returnAll() => setState(() {
    for (final line in _lines!) {
      line.quantity.text = _qty(line.line.remaining);
    }
  });

  Future<void> _submit(SaleReturnState state) async {
    final inputs = <RefundLineInput>[];
    for (final line in _lines!) {
      final qty = _entered(line);
      if (qty < 0 || qty > line.line.remaining + 1e-9) {
        setState(
          () => _error =
              'Check the quantity for ${line.line.item.productNameSnapshot} '
              '(max ${_qty(line.line.remaining)}).',
        );
        return;
      }
      if (qty > 0) {
        inputs.add(
          RefundLineInput(
            saleItemId: line.line.item.id,
            quantity: qty,
            restock: line.restock,
          ),
        );
      }
    }
    if (inputs.isEmpty) {
      setState(() => _error = 'Enter a quantity for at least one item.');
      return;
    }
    final reason = [
      _reason,
      if (_note.text.trim().isNotEmpty) _note.text.trim(),
    ].join(' · ');
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final session = ref.read(activeSessionProvider)!;
      final service = ref.read(refundServiceProvider);
      final result = await service.refund(
        session,
        saleId: widget.saleId,
        lines: inputs,
        method: _method ?? state.primaryMethod,
        reason: reason,
      );
      if (!mounted) return;
      final money = ref.read(moneyFormatterProvider);
      final print = await confirmDialog(
        context,
        title: 'Refund ${result.number} recorded',
        message:
            '${money.format(result.amount)} refunded by ${(_method ?? state.primaryMethod).toUpperCase()}. '
            'Print a refund slip for the customer?',
        confirmLabel: 'Print slip',
        icon: Icons.check_circle_outline_rounded,
      );
      if (print) {
        final fresh = await service.load(session, widget.saleId);
        final record = fresh.refunds.firstWhere(
          (r) => r.refund.id == result.refundId,
        );
        await printRefundSlip(ref, fresh, record);
      }
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) setState(() => _error = friendlyError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final money = ref.watch(moneyFormatterProvider);
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 880, maxHeight: 740),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: FutureBuilder<SaleReturnState>(
            future: _load,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return EmptyState(
                  icon: Icons.error_outline_rounded,
                  title: 'Sale could not be loaded',
                  message: friendlyError(snapshot.error!),
                  action: TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Close'),
                  ),
                );
              }
              if (!snapshot.hasData) {
                return const SizedBox(
                  height: 200,
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              final state = snapshot.data!;
              _lines ??= [for (final line in state.lines) _Line(line)];
              final sale = state.sale;
              final preview = _preview(state);
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  PageHeader(
                    icon: Icons.assignment_return_outlined,
                    title: 'Return items · ${sale.invoiceNumber}',
                    subtitle:
                        '${DateFormat('d MMM y, h:mm a').format(sale.createdAt)} · '
                        '${state.details.summary.customerName ?? 'Walk-in customer'} · '
                        'paid ${money.major(sale.grandTotal)}'
                        '${state.refunded.minorUnits > 0 ? ' · already refunded ${money.format(state.refunded)}' : ''}',
                    actions: [
                      IconButton(
                        onPressed: _busy
                            ? null
                            : () => Navigator.pop(context, false),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  if (!state.canRefund)
                    Expanded(
                      child: EmptyState(
                        icon: Icons.block_rounded,
                        title:
                            'This sale is ${SaleStatus.label(sale.saleStatus).toLowerCase()}',
                        message: 'There is nothing left to refund.',
                      ),
                    )
                  else ...[
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Enter how many of each item the customer is returning.',
                            style: TextStyle(
                              color: context.colors.onSurfaceVariant,
                            ),
                          ),
                        ),
                        TextButton.icon(
                          onPressed: _returnAll,
                          icon: const Icon(Icons.select_all_rounded),
                          label: const Text('Return everything'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Expanded(
                      child: Card(
                        margin: EdgeInsets.zero,
                        clipBehavior: Clip.antiAlias,
                        child: ListView.separated(
                          itemCount: _lines!.length,
                          separatorBuilder: (_, _) => const Divider(),
                          itemBuilder: (context, index) {
                            final line = _lines![index];
                            final item = line.line.item;
                            final done = line.line.remaining <= 0;
                            return Padding(
                              key: ValueKey(item.id),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 8,
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          item.productNameSnapshot,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                        Text(
                                          'Sold ${_qty(item.qty)} ${line.line.unit} · '
                                          '${money.major(item.lineTotal)}'
                                          '${line.line.refundedQty > 0 ? ' · returned ${_qty(line.line.refundedQty)}' : ''}',
                                          style: context.text.bodySmall,
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (done)
                                    const StatusPill('Fully returned')
                                  else ...[
                                    SizedBox(
                                      width: 120,
                                      child: TextField(
                                        controller: line.quantity,
                                        textAlign: TextAlign.end,
                                        inputFormatters: [
                                          FilteringTextInputFormatter.allow(
                                            RegExp(r'[0-9.,]'),
                                          ),
                                        ],
                                        decoration: InputDecoration(
                                          labelText: 'Return',
                                          hintText: '0',
                                          suffixText:
                                              '/ ${_qty(line.line.remaining)}',
                                        ),
                                        onChanged: (_) => setState(() {}),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    SizedBox(
                                      width: 150,
                                      child: CheckboxListTile(
                                        dense: true,
                                        contentPadding: EdgeInsets.zero,
                                        controlAffinity:
                                            ListTileControlAffinity.leading,
                                        value:
                                            line.restock &&
                                            line.line.tracksStock,
                                        onChanged: line.line.tracksStock
                                            ? (value) => setState(
                                                () => line.restock =
                                                    value ?? true,
                                              )
                                            : null,
                                        title: const Text('Back to stock'),
                                      ),
                                    ),
                                    SizedBox(
                                      width: 110,
                                      child: Text(
                                        money.format(
                                          line.line.amountFor(
                                            _entered(line)
                                                .clamp(0, line.line.remaining)
                                                .toDouble(),
                                          ),
                                        ),
                                        textAlign: TextAlign.end,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Row(
                                children: [
                                  const Text('Refund by  '),
                                  SegmentedButton<String>(
                                    showSelectedIcon: false,
                                    segments: const [
                                      ButtonSegment(
                                        value: 'cash',
                                        label: Text('Cash'),
                                      ),
                                      ButtonSegment(
                                        value: 'card',
                                        label: Text('Card'),
                                      ),
                                      ButtonSegment(
                                        value: 'bank',
                                        label: Text('Bank'),
                                      ),
                                      ButtonSegment(
                                        value: 'other',
                                        label: Text('Other'),
                                      ),
                                    ],
                                    selected: {_method ?? state.primaryMethod},
                                    onSelectionChanged: (value) =>
                                        setState(() => _method = value.first),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              Row(
                                children: [
                                  SizedBox(
                                    width: 240,
                                    child: DropdownButtonFormField<String>(
                                      menuMaxHeight: 360,
                                      initialValue: _reason,
                                      isExpanded: true,
                                      decoration: const InputDecoration(
                                        labelText: 'Reason',
                                      ),
                                      items: [
                                        for (final reason in refundReasons)
                                          DropdownMenuItem(
                                            value: reason,
                                            child: Text(reason),
                                          ),
                                      ],
                                      onChanged: (value) => setState(
                                        () => _reason = value ?? _reason,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
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
                            ],
                          ),
                        ),
                        const SizedBox(width: 20),
                        Container(
                          width: 220,
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: context.colors.errorContainer,
                            borderRadius: context.tokens.borderRadius,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                'Refund to customer',
                                style: TextStyle(
                                  color: context.colors.onErrorContainer,
                                ),
                              ),
                              Text(
                                money.format(
                                  _lines!.every((l) => _entered(l) <= 0)
                                      ? Money.zero
                                      : preview,
                                ),
                                style: context.text.headlineSmall?.copyWith(
                                  fontWeight: FontWeight.w900,
                                  color: context.colors.onErrorContainer,
                                ),
                              ),
                              Text(
                                'Includes the share of any sale discount',
                                style: context.text.labelSmall?.copyWith(
                                  color: context.colors.onErrorContainer,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        _error!,
                        style: TextStyle(color: context.colors.error),
                      ),
                    ],
                    const SizedBox(height: 14),
                    Align(
                      alignment: Alignment.centerRight,
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: context.colors.error,
                          foregroundColor: context.colors.onError,
                        ),
                        onPressed: _busy ? null : () => _submit(state),
                        icon: _busy
                            ? const SizedBox.square(
                                dimension: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.undo_rounded),
                        label: const Text('Confirm refund'),
                      ),
                    ),
                  ],
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

/// Voids a same-day sale after asking for a reason. Returns true on success.
Future<bool> showVoidDialog(BuildContext context, String saleId) async =>
    await showDialog<bool>(
      context: context,
      builder: (_) => _VoidDialog(saleId: saleId),
    ) ??
    false;

class _VoidDialog extends ConsumerStatefulWidget {
  const _VoidDialog({required this.saleId});
  final String saleId;
  @override
  ConsumerState<_VoidDialog> createState() => _VoidDialogState();
}

class _VoidDialogState extends ConsumerState<_VoidDialog> {
  String _reason = voidReasons.first;
  final _note = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(refundServiceProvider)
          .voidSale(
            ref.read(activeSessionProvider)!,
            saleId: widget.saleId,
            reason: [
              _reason,
              if (_note.text.trim().isNotEmpty) _note.text.trim(),
            ].join(' · '),
          );
      if (mounted) {
        Navigator.pop(context, true);
        Toast.success(context, 'Sale voided. Stock and cash were reversed.');
      }
    } catch (error) {
      if (mounted) setState(() => _error = friendlyError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    icon: Icon(Icons.cancel_outlined, color: context.colors.error, size: 36),
    title: const Text('Void this sale?'),
    content: SizedBox(
      width: 460,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'The whole sale is cancelled: all items go back to stock, cash is '
            'taken out of your drawer, loyalty points are removed and the sale '
            'no longer counts in reports. This cannot be undone.',
          ),
          const SizedBox(height: 14),
          DropdownButtonFormField<String>(
            menuMaxHeight: 360,
            initialValue: _reason,
            decoration: const InputDecoration(labelText: 'Reason'),
            items: [
              for (final reason in voidReasons)
                DropdownMenuItem(value: reason, child: Text(reason)),
            ],
            onChanged: (value) => setState(() => _reason = value ?? _reason),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _note,
            decoration: const InputDecoration(labelText: 'Note (optional)'),
          ),
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(_error!, style: TextStyle(color: context.colors.error)),
          ],
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: _busy ? null : () => Navigator.pop(context, false),
        child: const Text('Keep sale'),
      ),
      FilledButton(
        style: FilledButton.styleFrom(
          backgroundColor: context.colors.error,
          foregroundColor: context.colors.onError,
        ),
        onPressed: _busy ? null : _submit,
        child: const Text('Void sale'),
      ),
    ],
  );
}

/// Prints the slip for one refund or void.
Future<void> printRefundSlip(
  WidgetRef ref,
  SaleReturnState state,
  RefundRecord record,
) async {
  final settings = ref.read(currentBusinessSettingsProvider);
  final service = ref.read(receiptServiceProvider);
  final bytes = await buildReceiptPdfInBackground(
    ReceiptData.fromRefund(
      state.details,
      record.refund,
      record.items,
      settings,
    ),
  );
  await service.printBytes(
    bytes,
    name: 'Refund ${record.refund.number}',
    paper: settings.receipt.paper,
  );
}
