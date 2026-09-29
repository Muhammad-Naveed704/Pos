import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../auth/application/session_controller.dart';
import '../../receipts/data/receipt_service.dart';
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
  DateTime? _date;
  late final Future<SalesFilterOptions> _filterOptions;

  @override
  void initState() {
    super.initState();
    _filterOptions = Future.microtask(
      () => ref
          .read(salesRepositoryProvider)
          .filterOptions(ref.read(activeSessionProvider)!),
    );
  }

  @override
  void dispose() {
    _invoice.dispose();
    super.dispose();
  }

  Future<List<SaleSummary>> _load() {
    final day = _date;
    return ref
        .read(salesRepositoryProvider)
        .search(
          session: ref.read(activeSessionProvider)!,
          invoice: _invoice.text,
          customerId: _customerId,
          cashierId: _cashierId,
          paymentMethod: _method,
          status: _status,
          from: day == null ? null : DateTime(day.year, day.month, day.day),
          to: day == null ? null : DateTime(day.year, day.month, day.day + 1),
        );
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(24),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Sales history', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 15),
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
                  width: 230,
                  child: TextField(
                    controller: _invoice,
                    onSubmitted: (_) => setState(() {}),
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search),
                      hintText: 'Invoice number',
                    ),
                  ),
                ),
                _filterDropdown(
                  label: 'Customer',
                  value: _customerId,
                  choices: options?.customers ?? const [],
                  onChanged: (value) => setState(() => _customerId = value),
                ),
                _filterDropdown(
                  label: 'Cashier',
                  value: _cashierId,
                  choices: options?.cashiers ?? const [],
                  onChanged: (value) => setState(() => _cashierId = value),
                ),
                SizedBox(
                  width: 135,
                  child: DropdownButtonFormField<String?>(
                    isExpanded: true,
                    initialValue: _method,
                    decoration: const InputDecoration(labelText: 'Payment'),
                    items: const [
                      DropdownMenuItem(value: null, child: Text('All')),
                      DropdownMenuItem(value: 'cash', child: Text('Cash')),
                      DropdownMenuItem(value: 'card', child: Text('Card')),
                      DropdownMenuItem(value: 'bank', child: Text('Bank')),
                      DropdownMenuItem(value: 'other', child: Text('Other')),
                    ],
                    onChanged: (value) => setState(() => _method = value),
                  ),
                ),
                SizedBox(
                  width: 140,
                  child: DropdownButtonFormField<String?>(
                    isExpanded: true,
                    initialValue: _status,
                    decoration: const InputDecoration(labelText: 'Status'),
                    items: const [
                      DropdownMenuItem(value: null, child: Text('All')),
                      DropdownMenuItem(
                        value: 'completed',
                        child: Text('Completed'),
                      ),
                      DropdownMenuItem(value: 'voided', child: Text('Voided')),
                      DropdownMenuItem(
                        value: 'refunded',
                        child: Text('Refunded'),
                      ),
                    ],
                    onChanged: (value) => setState(() => _status = value),
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: () async {
                    final selected = await showDatePicker(
                      context: context,
                      firstDate: DateTime(2020),
                      lastDate: DateTime.now(),
                      initialDate: _date ?? DateTime.now(),
                    );
                    if (selected != null) setState(() => _date = selected);
                  },
                  icon: const Icon(Icons.calendar_today_outlined, size: 17),
                  label: Text(
                    _date == null
                        ? 'Any date'
                        : DateFormat.yMMMd().format(_date!),
                  ),
                ),
                if (_date != null)
                  IconButton(
                    onPressed: () => setState(() => _date = null),
                    icon: const Icon(Icons.close),
                  ),
              ],
            );
          },
        ),
        const SizedBox(height: 14),
        Expanded(
          child: Card(
            child: FutureBuilder<List<SaleSummary>>(
              future: _load(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final sales = snapshot.data!;
                if (sales.isEmpty) {
                  return const Center(
                    child: Text('No sales match these filters.'),
                  );
                }
                return ListView.separated(
                  itemCount: sales.length,
                  separatorBuilder: (_, _) => const Divider(),
                  itemBuilder: (context, index) {
                    final item = sales[index];
                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 7,
                      ),
                      leading: const CircleAvatar(
                        child: Icon(Icons.receipt_long_outlined, size: 19),
                      ),
                      title: Text(
                        item.sale.invoiceNumber,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      subtitle: Text(
                        '${DateFormat('dd MMM yyyy, HH:mm').format(item.sale.createdAt)} · ${item.customerName ?? 'Walk-in'} · ${item.cashierName}',
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Rs ${item.sale.grandTotal.toStringAsFixed(2)}',
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                          const SizedBox(width: 14),
                          Chip(label: Text(item.paymentMethods.toUpperCase())),
                          PopupMenuButton<String>(
                            onSelected: (value) =>
                                _receipt(value, item.sale.id),
                            itemBuilder: (_) => const [
                              PopupMenuItem(
                                value: 'view',
                                child: Text('View details'),
                              ),
                              PopupMenuItem(
                                value: 'print',
                                child: Text('Print receipt'),
                              ),
                              PopupMenuItem(
                                value: 'pdf',
                                child: Text('Save receipt PDF'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ),
      ],
    ),
  );

  Widget _filterDropdown({
    required String label,
    required String? value,
    required List<SalesFilterChoice> choices,
    required ValueChanged<String?> onChanged,
  }) => SizedBox(
    width: 160,
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
    final details = await ref
        .read(salesRepositoryProvider)
        .details(ref.read(activeSessionProvider)!, saleId);
    if (!mounted) return;
    if (action == 'print') {
      await ref.read(receiptServiceProvider).printReceipt(details);
    }
    if (action == 'pdf') {
      await ref.read(receiptServiceProvider).savePdf(details);
    }
    if (action == 'view' && mounted) {
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(details.summary.sale.invoiceNumber),
          content: SizedBox(
            width: 600,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ...details.items.map(
                  (item) => ListTile(
                    dense: true,
                    title: Text(item.productNameSnapshot),
                    subtitle: Text(
                      '${item.qty} × Rs ${item.unitPrice.toStringAsFixed(2)}',
                    ),
                    trailing: Text('Rs ${item.lineTotal.toStringAsFixed(2)}'),
                  ),
                ),
                const Divider(),
                ListTile(
                  title: const Text(
                    'Grand total',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                  trailing: Text(
                    'Rs ${details.summary.sale.grandTotal.toStringAsFixed(2)}',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        ),
      );
    }
  }
}
