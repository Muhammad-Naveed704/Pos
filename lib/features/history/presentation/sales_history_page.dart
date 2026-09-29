import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/money/money_format.dart';
import '../../../core/ui/ui_kit.dart';
import '../../auth/application/session_controller.dart';
import '../../receipts/data/receipt_service.dart';
import '../../settings/data/business_settings_repository.dart';
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

  String get _rangeLabel {
    final range = _range;
    if (range == null) return 'All dates';
    final format = DateFormat('d MMM y');
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    if (range.start == today && range.end == today) return 'Today';
    if (range.start == range.end) return format.format(range.start);
    return '${format.format(range.start)} – ${format.format(range.end)}';
  }

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
                  OutlinedButton.icon(
                    onPressed: _pickRange,
                    icon: const Icon(Icons.date_range_rounded, size: 18),
                    label: Text(_rangeLabel),
                  ),
                  if (_range != null)
                    IconButton(
                      tooltip: 'All dates',
                      onPressed: () => _refresh(() => _range = null),
                      icon: const Icon(Icons.close_rounded),
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
                      SalesFilterChoice('voided', 'Voided'),
                      SalesFilterChoice('refunded', 'Refunded'),
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
                  (item) => item.sale.saleStatus == 'completed',
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

  Future<void> _pickRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(now.year, now.month, now.day),
      initialDateRange: _range,
    );
    if (picked != null) _refresh(() => _range = picked);
  }

  Widget _filterDropdown({
    required String label,
    required String? value,
    required List<SalesFilterChoice> choices,
    required ValueChanged<String?> onChanged,
    double width = 170,
  }) => SizedBox(
    width: width,
    child: DropdownButtonFormField<String?>(
      isExpanded: true,
      initialValue: value,
      decoration: InputDecoration(labelText: label),
      items: [
        const DropdownMenuItem(value: null, child: Text('All')),
        ...choices.map(
          (choice) => DropdownMenuItem(
            value: choice.id,
            child: Text(choice.label, overflow: TextOverflow.ellipsis),
          ),
        ),
      ],
      onChanged: onChanged,
    ),
  );

  Future<void> _receipt(String action, String saleId) async {
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
        case 'view':
          await showDialog<void>(
            context: context,
            builder: (context) => _SaleDetailsDialog(
              details: details,
              money: ref.read(moneyFormatterProvider),
              onPrint: () => receipts.printReceipt(details, settings),
            ),
          );
      }
    } catch (error) {
      if (mounted) Toast.error(context, error);
    }
  }
}

PillTone _statusTone(String status) => switch (status) {
  'completed' => PillTone.success,
  'voided' => PillTone.danger,
  'refunded' => PillTone.warning,
  _ => PillTone.neutral,
};

class _SaleRow extends StatelessWidget {
  const _SaleRow({
    required this.item,
    required this.money,
    required this.onAction,
  });
  final SaleSummary item;
  final MoneyFormatter money;
  final ValueChanged<String> onAction;

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
                sale.saleStatus[0].toUpperCase() + sale.saleStatus.substring(1),
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
              itemBuilder: (_) => const [
                PopupMenuItem(
                  value: 'view',
                  child: ListTile(
                    leading: Icon(Icons.visibility_outlined),
                    title: Text('View details'),
                  ),
                ),
                PopupMenuItem(
                  value: 'print',
                  child: ListTile(
                    leading: Icon(Icons.print_outlined),
                    title: Text('Print receipt'),
                  ),
                ),
                PopupMenuItem(
                  value: 'pdf',
                  child: ListTile(
                    leading: Icon(Icons.picture_as_pdf_outlined),
                    title: Text('Save receipt PDF'),
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

class _SaleDetailsDialog extends StatelessWidget {
  const _SaleDetailsDialog({
    required this.details,
    required this.money,
    required this.onPrint,
  });
  final SaleDetails details;
  final MoneyFormatter money;
  final VoidCallback onPrint;

  @override
  Widget build(BuildContext context) {
    final sale = details.summary.sale;
    String qty(double value) => value == value.roundToDouble()
        ? value.toStringAsFixed(0)
        : value.toString();
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
    return AlertDialog(
      title: Row(
        children: [
          Expanded(child: Text(sale.invoiceNumber)),
          StatusPill(sale.saleStatus, tone: _statusTone(sale.saleStatus)),
        ],
      ),
      content: SizedBox(
        width: 620,
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
                    '${item.skuSnapshot} · ${qty(item.qty)} × ${money.major(item.unitPrice)}'
                    '${item.discountAmount > 0 ? ' · discount ${money.major(item.discountAmount)}' : ''}',
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
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
        FilledButton.icon(
          onPressed: onPrint,
          icon: const Icon(Icons.print_outlined),
          label: const Text('Print receipt'),
        ),
      ],
    );
  }
}
