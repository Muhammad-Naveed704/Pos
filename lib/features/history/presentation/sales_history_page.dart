import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/database/app_database.dart';
import '../../../core/money/money_format.dart';
import '../../../core/ui/ui_kit.dart';
import '../../auth/application/session_controller.dart';
import '../../receipts/data/receipt_service.dart';
import '../../receipts/presentation/receipt_preview.dart';
import '../../settings/data/business_settings_repository.dart';
import '../../auth/domain/permissions.dart';
import '../../returns/data/refund_service.dart';
import '../../returns/presentation/refund_dialog.dart';
import '../data/sales_repository.dart';

class SalesHistoryPage extends ConsumerStatefulWidget {
  const SalesHistoryPage({super.key});
  @override
  ConsumerState<SalesHistoryPage> createState() => _SalesHistoryPageState();
}

class _SalesHistoryPageState extends ConsumerState<SalesHistoryPage> {
  final _invoice = TextEditingController();
  String? _method;
  String? _customerId;
  String? _cashierId;
  String? _status;
  DateTimeRange? _range;
  late final Future<SalesFilterOptions> _filterOptions;
  late Future<List<SaleSummary>> _sales;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    _range = DateTimeRange(start: today, end: today);
    _filterOptions = Future.microtask(
      () => ref
          .read(salesRepositoryProvider)
          .filterOptions(ref.read(activeSessionProvider)!),
    );
    _sales = _load();
  }

  @override
  void dispose() {
    _invoice.dispose();
    super.dispose();
  }

  Future<List<SaleSummary>> _load() {
    final range = _range;
    return ref
        .read(salesRepositoryProvider)
        .search(
          session: ref.read(activeSessionProvider)!,
          invoice: _invoice.text,
          customerId: _customerId,
          cashierId: _cashierId,
          paymentMethod: _method,
          status: _status,
          from: range?.start,
          to: range == null
              ? null
              : DateTime(range.end.year, range.end.month, range.end.day + 1),
        );
  }

  /// Re-runs the query only when a filter actually changes.
  void _refresh(VoidCallback change) => setState(() {
    change();
    _sales = _load();
  });

  @override
  Widget build(BuildContext context) {
    final money = ref.watch(moneyFormatterProvider);
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PageHeader(
            title: 'Sales history',
            subtitle: 'Search invoices, reprint receipts and review payments.',
            actions: [
              IconButton.outlined(
                tooltip: 'Refresh',
                onPressed: () => _refresh(() {}),
                icon: const Icon(Icons.refresh_rounded),
              ),
            ],
          ),
          const SizedBox(height: 18),
          FutureBuilder<SalesFilterOptions>(
            future: _filterOptions,
            builder: (context, snapshot) {
              final options = snapshot.data;
              return Wrap(
                spacing: 10,
                runSpacing: 10,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SizedBox(
                    width: 220,
                    child: TextField(
                      controller: _invoice,
                      onSubmitted: (_) => _refresh(() {}),
                      decoration: InputDecoration(
                        prefixIcon: const Icon(Icons.search_rounded),
                        hintText: 'Invoice number',
                        suffixIcon: IconButton(
                          tooltip: 'Search',
                          onPressed: () => _refresh(() {}),
                          icon: const Icon(Icons.arrow_forward_rounded),
                        ),
                      ),
                    ),
                  ),
                  DateRangeButton(
                    value: _range,
                    onChanged: (range) => _refresh(() => _range = range),
                  ),
                  _filterDropdown(
                    label: 'Customer',
                    value: _customerId,
                    choices: options?.customers ?? const [],
                    onChanged: (value) => _refresh(() => _customerId = value),
                  ),
                  _filterDropdown(
                    label: 'Cashier',
                    value: _cashierId,
                    choices: options?.cashiers ?? const [],
                    onChanged: (value) => _refresh(() => _cashierId = value),
                  ),
                  _filterDropdown(
                    label: 'Payment',
                    value: _method,
                    width: 140,
                    choices: const [
                      SalesFilterChoice('cash', 'Cash'),
                      SalesFilterChoice('card', 'Card'),
                      SalesFilterChoice('bank', 'Bank'),
                      SalesFilterChoice('other', 'Other'),
                    ],
                    onChanged: (value) => _refresh(() => _method = value),
                  ),
                  _filterDropdown(
                    label: 'Status',
                    value: _status,
                    width: 150,
                    choices: const [
                      SalesFilterChoice('completed', 'Completed'),
                      SalesFilterChoice(
                        'partially_refunded',
                        'Partly refunded',
                      ),
                      SalesFilterChoice('refunded', 'Refunded'),
                      SalesFilterChoice('voided', 'Voided'),
                    ],
                    onChanged: (value) => _refresh(() => _status = value),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 16),
          Expanded(
            child: FutureBuilder<List<SaleSummary>>(
              future: _sales,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Card(
                    child: EmptyState(
                      icon: Icons.error_outline_rounded,
                      title: 'Sales could not be loaded',
                      message: friendlyError(snapshot.error!),
                    ),
                  );
                }
                if (!snapshot.hasData) {
                  return const Card(
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                final sales = snapshot.data!;
                final completed = sales.where(
                  (item) => item.sale.saleStatus != SaleStatus.voided,
                );
                final revenue = completed.fold<double>(
                  0,
                  (sum, item) => sum + item.sale.grandTotal,
                );
                return Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: StatCard(
                            label: 'Invoices',
                            value: '${sales.length}',
                            icon: Icons.receipt_long_rounded,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: StatCard(
                            label: 'Revenue',
                            value: money.major(revenue),
                            icon: Icons.trending_up_rounded,
                            color: context.tokens.success,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: StatCard(
                            label: 'Average sale',
                            value: money.major(
                              completed.isEmpty
                                  ? 0
                                  : revenue / completed.length,
                            ),
                            icon: Icons.analytics_outlined,
                            color: context.colors.tertiary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: Card(
                        clipBehavior: Clip.antiAlias,
                        child: sales.isEmpty
                            ? const EmptyState(
                                icon: Icons.receipt_long_outlined,
                                title: 'No sales match these filters',
                                message:
                                    'Change the date range or clear filters.',
                              )
                            : ListView.separated(
                                itemCount: sales.length,
                                separatorBuilder: (_, _) => const Divider(),
                                itemBuilder: (context, index) => _SaleRow(
                                  item: sales[index],
                                  money: money,
                                  canRefund: ref
                                      .watch(activeSessionProvider)!
                                      .can(Permissions.posRefund),
                                  canVoid: ref
                                      .watch(activeSessionProvider)!
                                      .can(Permissions.posVoidSale),
                                  onAction: (action) =>
                                      _receipt(action, sales[index].sale.id),
                                ),
                              ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _filterDropdown({
    required String label,
    required String? value,
    required List<SalesFilterChoice> choices,
    required ValueChanged<String?> onChanged,
    double width = 170,
  }) => SizedBox(
    width: width,
    child: AppSelect<String?>(
      items: [
        SelectItem(null, 'All'),
        ...choices.map((choice) => SelectItem(choice.id, choice.label)),
      ],
      value: value,
      onChanged: onChanged,
      label: label,
    ),
  );

  Future<void> _receipt(String action, String saleId) async {
    if (action == 'refund') {
      if (await showRefundDialog(context, saleId)) _refresh(() {});
      return;
    }
    if (action == 'void') {
      if (await showVoidDialog(context, saleId)) _refresh(() {});
      return;
    }
    try {
      final details = await ref
          .read(salesRepositoryProvider)
          .details(ref.read(activeSessionProvider)!, saleId);
      if (!mounted) return;
      final settings = ref.read(currentBusinessSettingsProvider);
      final receipts = ref.read(receiptServiceProvider);
      switch (action) {
        case 'print':
          await receipts.printReceipt(details, settings);
        case 'pdf':
          final path = await receipts.savePdf(details, settings);
          if (path != null && mounted) Toast.success(context, 'Saved $path');
        case 'preview':
          await showReceiptPreview(context, ref, details);
        case 'view':
          await showDialog<void>(
            context: context,
            builder: (context) => _SaleDetailsDialog(
              details: details,
              money: ref.read(moneyFormatterProvider),
              onPrint: () => showReceiptPreview(context, ref, details),
            ),
          );
          if (mounted) _refresh(() {});
      }
    } catch (error) {
      if (mounted) Toast.error(context, error);
    }
  }
}

PillTone _statusTone(String status) => switch (status) {
  SaleStatus.completed => PillTone.success,
  SaleStatus.voided => PillTone.danger,
  SaleStatus.refunded => PillTone.warning,
  SaleStatus.partiallyRefunded => PillTone.info,
  _ => PillTone.neutral,
};

bool _isToday(DateTime value) {
  final local = value.toLocal();
  final now = DateTime.now();
  return local.year == now.year &&
      local.month == now.month &&
      local.day == now.day;
}

class _SaleRow extends StatelessWidget {
  const _SaleRow({
    required this.item,
    required this.money,
    required this.onAction,
    this.canRefund = false,
    this.canVoid = false,
  });
  final SaleSummary item;
  final MoneyFormatter money;
  final ValueChanged<String> onAction;
  final bool canRefund;
  final bool canVoid;

  @override
  Widget build(BuildContext context) {
    final sale = item.sale;
    return InkWell(
      onTap: () => onAction('view'),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        child: Row(
          children: [
            const IconTile(icon: Icons.receipt_long_rounded, size: 38),
            const SizedBox(width: 14),
            Expanded(
              flex: 3,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    sale.invoiceNumber,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  Text(
                    DateFormat('d MMM y · h:mm a').format(sale.createdAt),
                    style: context.text.bodySmall?.copyWith(
                      color: context.colors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              flex: 3,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.customerName ?? 'Walk-in customer',
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    'by ${item.cashierName}',
                    overflow: TextOverflow.ellipsis,
                    style: context.text.bodySmall?.copyWith(
                      color: context.colors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              flex: 2,
              child: Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  for (final method in item.paymentMethods.split(','))
                    if (method.trim().isNotEmpty)
                      StatusPill(method.trim().toUpperCase()),
                ],
              ),
            ),
            SizedBox(
              width: 100,
              child: StatusPill(
                SaleStatus.label(sale.saleStatus),
                tone: _statusTone(sale.saleStatus),
              ),
            ),
            SizedBox(
              width: 130,
              child: Text(
                money.major(sale.grandTotal),
                textAlign: TextAlign.end,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
            const SizedBox(width: 6),
            PopupMenuButton<String>(
              tooltip: 'Receipt actions',
              onSelected: onAction,
              itemBuilder: (_) => [
                const PopupMenuItem(
                  value: 'view',
                  child: ListTile(
                    leading: Icon(Icons.visibility_outlined),
                    title: Text('View details'),
                  ),
                ),
                const PopupMenuItem(
                  value: 'preview',
                  child: ListTile(
                    leading: Icon(Icons.receipt_long_outlined),
                    title: Text('Preview receipt'),
                  ),
                ),
                const PopupMenuItem(
                  value: 'print',
                  child: ListTile(
                    leading: Icon(Icons.print_outlined),
                    title: Text('Print receipt'),
                  ),
                ),
                const PopupMenuItem(
                  value: 'pdf',
                  child: ListTile(
                    leading: Icon(Icons.picture_as_pdf_outlined),
                    title: Text('Save receipt PDF'),
                  ),
                ),
                if (canRefund &&
                    (sale.saleStatus == SaleStatus.completed ||
                        sale.saleStatus == SaleStatus.partiallyRefunded)) ...[
                  const PopupMenuDivider(),
                  const PopupMenuItem(
                    value: 'refund',
                    child: ListTile(
                      leading: Icon(Icons.assignment_return_outlined),
                      title: Text('Return / refund items'),
                    ),
                  ),
                ],
                if (canVoid &&
                    sale.saleStatus == SaleStatus.completed &&
                    _isToday(sale.createdAt))
                  const PopupMenuItem(
                    value: 'void',
                    child: ListTile(
                      leading: Icon(Icons.cancel_outlined),
                      title: Text('Void sale'),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SaleDetailsDialog extends ConsumerStatefulWidget {
  const _SaleDetailsDialog({
    required this.details,
    required this.money,
    required this.onPrint,
  });
  final SaleDetails details;
  final MoneyFormatter money;
  final VoidCallback onPrint;

  @override
  ConsumerState<_SaleDetailsDialog> createState() => _SaleDetailsDialogState();
}

class _SaleDetailsDialogState extends ConsumerState<_SaleDetailsDialog> {
  late Future<SaleReturnState> _returns = _loadReturns();

  Future<SaleReturnState> _loadReturns() => ref
      .read(refundServiceProvider)
      .load(ref.read(activeSessionProvider)!, widget.details.summary.sale.id);

  void _afterChange(bool changed) {
    if (changed && mounted) setState(() => _returns = _loadReturns());
  }

  static String _qty(double value) => value == value.roundToDouble()
      ? value.toStringAsFixed(0)
      : value.toString();

  String _returnedNote(SaleReturnState? state, SaleItem item) {
    final returned =
        state?.lines
            .where((line) => line.item.id == item.id)
            .firstOrNull
            ?.refundedQty ??
        0;
    return returned > 0 ? ' · returned ${_qty(returned)}' : '';
  }

  @override
  Widget build(BuildContext context) {
    final details = widget.details;
    final money = widget.money;
    final session = ref.watch(activeSessionProvider)!;
    Widget amount(String label, double value, {bool bold = false}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          Text(
            money.major(value),
            style: TextStyle(
              fontWeight: bold ? FontWeight.w900 : FontWeight.w600,
              fontSize: bold ? 17 : null,
            ),
          ),
        ],
      ),
    );
    return FutureBuilder<SaleReturnState>(
      future: _returns,
      builder: (context, snapshot) {
        final state = snapshot.data;
        final sale = state?.sale ?? details.summary.sale;
        return AlertDialog(
          title: Row(
            children: [
              Expanded(child: Text(sale.invoiceNumber)),
              StatusPill(
                SaleStatus.label(sale.saleStatus),
                tone: _statusTone(sale.saleStatus),
              ),
            ],
          ),
          content: SizedBox(
            width: 640,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    '${DateFormat('EEEE, d MMM y · h:mm a').format(sale.createdAt)}\n'
                    '${details.summary.customerName ?? 'Walk-in customer'} · cashier ${details.summary.cashierName} · ${details.store.name}',
                    style: TextStyle(color: context.colors.onSurfaceVariant),
                  ),
                  const SizedBox(height: 12),
                  const Divider(),
                  for (final item in details.items)
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        item.productNameSnapshot,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text(
                        '${item.skuSnapshot} · ${_qty(item.qty)} × ${money.major(item.unitPrice)}'
                        '${item.discountAmount > 0 ? ' · discount ${money.major(item.discountAmount)}' : ''}'
                        '${_returnedNote(state, item)}',
                      ),
                      trailing: Text(
                        money.major(item.lineTotal),
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  const Divider(),
                  amount('Subtotal', sale.subtotal),
                  if (sale.discountAmount > 0)
                    amount('Discount', -sale.discountAmount),
                  if (sale.taxAmount > 0) amount('Tax', sale.taxAmount),
                  amount('Grand total', sale.grandTotal, bold: true),
                  const SizedBox(height: 8),
                  for (final payment in details.payments)
                    amount(
                      'Paid · ${payment.method.toUpperCase()}',
                      payment.amount,
                    ),
                  amount('Change', sale.changeAmount),
                  if (sale.notes.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Text('Note: ${sale.notes}'),
                  ],
                  if (state != null && state.refunds.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    Text(
                      'Refunds & voids',
                      style: context.text.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    for (final record in state.refunds)
                      Card(
                        margin: const EdgeInsets.only(top: 6),
                        child: ListTile(
                          isThreeLine: true,
                          leading: Icon(
                            record.refund.kind == 'void'
                                ? Icons.cancel_outlined
                                : Icons.assignment_return_outlined,
                            color: context.colors.error,
                          ),
                          title: Text(
                            '${record.refund.number} · −${money.major(record.refund.amount)} '
                            'by ${record.refund.method.toUpperCase()}',
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          subtitle: Text(
                            '${DateFormat('d MMM y, h:mm a').format(record.refund.createdAt)} · ${record.userName}'
                            '${record.refund.reason.isEmpty ? '' : ' · ${record.refund.reason}'}\n'
                            '${record.items.map((e) => '${_qty(e.$1.qty)} × ${e.$2}${e.$1.restocked ? '' : ' (not restocked)'}').join(', ')}',
                          ),
                          trailing: IconButton(
                            tooltip: 'Print slip',
                            onPressed: () async {
                              try {
                                await printRefundSlip(ref, state, record);
                              } catch (error) {
                                if (context.mounted) {
                                  Toast.error(context, error);
                                }
                              }
                            },
                            icon: const Icon(Icons.print_outlined),
                          ),
                        ),
                      ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            if (state != null &&
                state.canVoid &&
                session.can(Permissions.posVoidSale))
              TextButton.icon(
                onPressed: () async =>
                    _afterChange(await showVoidDialog(context, sale.id)),
                icon: const Icon(Icons.cancel_outlined),
                label: const Text('Void'),
              ),
            if (state != null &&
                state.canRefund &&
                session.can(Permissions.posRefund))
              OutlinedButton.icon(
                onPressed: () async =>
                    _afterChange(await showRefundDialog(context, sale.id)),
                icon: const Icon(Icons.assignment_return_outlined),
                label: const Text('Return items'),
              ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
            FilledButton.icon(
              onPressed: widget.onPrint,
              icon: const Icon(Icons.print_outlined),
              label: const Text('Receipt'),
            ),
          ],
        );
      },
    );
  }
}
