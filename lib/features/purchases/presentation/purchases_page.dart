import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/database/app_database.dart';
import '../../../core/money/money.dart';
import '../../../core/money/money_format.dart';
import '../../../core/ui/ui_kit.dart';
import '../../auth/application/session_controller.dart';
import '../../auth/domain/permissions.dart';
import '../../products/data/product_repository.dart';
import '../../products/presentation/product_picker.dart';
import '../../settings/data/business_settings_repository.dart';
import '../data/purchase_service.dart';

String _qty(double value) => value == value.roundToDouble()
    ? value.toStringAsFixed(0)
    : value.toStringAsFixed(3).replaceFirst(RegExp(r'0+$'), '');

class PurchasesPage extends ConsumerWidget {
  const PurchasesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(activeSessionProvider)!;
    final canManage = session.can(Permissions.purchasesManage);
    return DefaultTabController(
      length: 2,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            PageHeader(
              title: 'Purchases',
              subtitle: 'Receive stock from suppliers, record returns and keep supplier details.',
              actions: [
                if (canManage) ...[
                  OutlinedButton.icon(
                    onPressed: () => _openDocument(context, isReturn: true),
                    icon: const Icon(Icons.assignment_return_outlined),
                    label: const Text('Return to supplier'),
                  ),
                  FilledButton.icon(
                    onPressed: () => _openDocument(context, isReturn: false),
                    icon: const Icon(Icons.move_to_inbox_rounded),
                    label: const Text('Receive stock'),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 10),
            const TabBar(
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              tabs: [
                Tab(icon: Icon(Icons.receipt_long_outlined), text: 'Purchases'),
                Tab(
                  icon: Icon(Icons.local_shipping_outlined),
                  text: 'Suppliers',
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Expanded(
              child: TabBarView(children: [_PurchaseList(), _SupplierList()]),
            ),
          ],
        ),
      ),
    );
  }

  static Future<void> _openDocument(
    BuildContext context, {
    required bool isReturn,
  }) => showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _PurchaseDocumentDialog(isReturn: isReturn),
  );
}

class _PurchaseList extends ConsumerStatefulWidget {
  const _PurchaseList();
  @override
  ConsumerState<_PurchaseList> createState() => _PurchaseListState();
}

class _PurchaseListState extends ConsumerState<_PurchaseList>
    with AutomaticKeepAliveClientMixin {
  DateTimeRange? _range;
  String? _status;
  late Stream<List<PurchaseSummary>> _stream;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _bind();
  }

  void _bind() {
    final range = _range;
    _stream = ref
        .read(purchaseServiceProvider)
        .watchPurchases(
          ref.read(activeSessionProvider)!,
          from: range?.start,
          to: range == null
              ? null
              : DateTime(range.end.year, range.end.month, range.end.day + 1),
          status: _status,
        );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final money = ref.watch(moneyFormatterProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 10,
          runSpacing: 10,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            for (final (status, label) in const [
              (null, 'All'),
              (PurchaseService.statusReceived, 'Received'),
              (PurchaseService.statusReturn, 'Returns'),
            ])
              ChoiceChip(
                label: Text(label),
                selected: _status == status,
                onSelected: (_) => setState(() {
                  _status = status;
                  _bind();
                }),
              ),
            DateRangeButton(
              value: _range,
              onChanged: (range) => setState(() {
                _range = range;
                _bind();
              }),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Expanded(
          child: Card(
            clipBehavior: Clip.antiAlias,
            child: StreamBuilder<List<PurchaseSummary>>(
              stream: _stream,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return EmptyState(
                    icon: Icons.error_outline_rounded,
                    title: 'Purchases could not be loaded',
                    message: friendlyError(snapshot.error!),
                  );
                }
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final rows = snapshot.data!;
                if (rows.isEmpty) {
                  return const EmptyState(
                    icon: Icons.move_to_inbox_outlined,
                    title: 'No purchases yet',
                    message: 'Use “Receive stock” when goods arrive from a supplier.',
                  );
                }
                return ListView.separated(
                  itemCount: rows.length,
                  separatorBuilder: (_, _) => const Divider(),
                  itemBuilder: (context, index) {
                    final row = rows[index];
                    final p = row.purchase;
                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 4,
                      ),
                      leading: IconTile(
                        icon: row.isReturn
                            ? Icons.assignment_return_outlined
                            : Icons.move_to_inbox_rounded,
                        color: row.isReturn
                            ? context.tokens.warning
                            : context.colors.primary,
                        size: 38,
                      ),
                      title: Text(
                        p.invoiceNumber,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      subtitle: Text(
                        '${row.supplierName ?? 'No supplier'} · ${row.itemCount} item(s) · '
                        '${DateFormat('d MMM y, h:mm a').format(p.createdAt)}',
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          StatusPill(
                            row.isReturn ? 'Return' : 'Received',
                            tone: row.isReturn
                                ? PillTone.warning
                                : PillTone.success,
                          ),
                          const SizedBox(width: 14),
                          SizedBox(
                            width: 130,
                            child: Text(
                              '${row.isReturn ? '−' : ''}${money.major(p.total)}',
                              textAlign: TextAlign.end,
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ],
                      ),
                      onTap: () => showDialog<void>(
                        context: context,
                        builder: (_) => _PurchaseDetails(summary: row),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

class _PurchaseDetails extends ConsumerStatefulWidget {
  const _PurchaseDetails({required this.summary});
  final PurchaseSummary summary;
  @override
  ConsumerState<_PurchaseDetails> createState() => _PurchaseDetailsState();
}

class _PurchaseDetailsState extends ConsumerState<_PurchaseDetails> {
  late final Future<List<PurchaseLineDetail>> _lines = ref
      .read(purchaseServiceProvider)
      .lines(ref.read(activeSessionProvider)!, widget.summary.purchase.id);

  @override
  Widget build(BuildContext context) {
    final summary = widget.summary;
    final money = ref.watch(moneyFormatterProvider);
    final p = summary.purchase;
    final lines = _lines;
    Widget amount(String label, double value, {bool bold = false}) => Row(
      children: [
        Expanded(child: Text(label)),
        Text(
          money.major(value),
          style: TextStyle(
            fontWeight: bold ? FontWeight.w900 : FontWeight.w600,
          ),
        ),
      ],
    );
    return AlertDialog(
      title: Row(
        children: [
          Expanded(child: Text(p.invoiceNumber)),
          StatusPill(
            summary.isReturn ? 'Supplier return' : 'Received',
            tone: summary.isReturn ? PillTone.warning : PillTone.success,
          ),
        ],
      ),
      content: SizedBox(
        width: 620,
        child: FutureBuilder<List<PurchaseLineDetail>>(
          future: lines,
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const SizedBox(
                height: 120,
                child: Center(child: CircularProgressIndicator()),
              );
            }
            return SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    '${summary.supplierName ?? 'No supplier'} · ${DateFormat('EEEE, d MMM y · h:mm a').format(p.createdAt)}',
                    style: TextStyle(color: context.colors.onSurfaceVariant),
                  ),
                  const Divider(height: 24),
                  for (final line in snapshot.data!)
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(line.productName),
                      subtitle: Text(
                        '${line.sku} · ${_qty(line.item.qty)} ${line.unit} × ${money.major(line.item.costPrice)}',
                      ),
                      trailing: Text(
                        money.major(line.item.lineTotal),
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  const Divider(),
                  amount('Subtotal', p.subtotal),
                  if (p.discount > 0) amount('Discount', -p.discount),
                  if (p.tax > 0) amount('Tax', p.tax),
                  amount('Total', p.total, bold: true),
                ],
              ),
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    );
  }
}

class _DocLine {
  _DocLine(this.product, String cost)
    : quantity = TextEditingController(text: '1'),
      cost = TextEditingController(text: cost);
  final CatalogProduct product;
  final TextEditingController quantity;
  final TextEditingController cost;

  void dispose() {
    quantity.dispose();
    cost.dispose();
  }
}

class _PurchaseDocumentDialog extends ConsumerStatefulWidget {
  const _PurchaseDocumentDialog({required this.isReturn});
  final bool isReturn;
  @override
  ConsumerState<_PurchaseDocumentDialog> createState() =>
      _PurchaseDocumentDialogState();
}

class _PurchaseDocumentDialogState
    extends ConsumerState<_PurchaseDocumentDialog> {
  final _lines = <_DocLine>[];
  final _reference = TextEditingController();
  final _discount = TextEditingController();
  final _tax = TextEditingController();
  final _reason = TextEditingController();
  String? _supplierId;
  late final Stream<List<Supplier>> _suppliers = ref
      .read(purchaseServiceProvider)
      .watchSuppliers(ref.read(activeSessionProvider)!, activeOnly: true);
  bool _updateCost = true;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    for (final line in _lines) {
      line.dispose();
    }
    _reference.dispose();
    _discount.dispose();
    _tax.dispose();
    _reason.dispose();
    super.dispose();
  }

  MoneyFormatter get _money => ref.read(moneyFormatterProvider);

  void _add(CatalogProduct product) {
    final existing = _lines
        .where((line) => line.product.product.id == product.product.id)
        .firstOrNull;
    setState(() {
      if (existing != null) {
        final value = (_money.parse(existing.quantity.text) ?? 0) + 1;
        existing.quantity.text = _qty(value);
      } else {
        _lines.add(
          _DocLine(
            product,
            _money.editable(Money.fromMajor(product.product.costPrice)),
          ),
        );
      }
    });
  }

  List<PurchaseLineInput>? _inputs({bool report = false}) {
    final inputs = <PurchaseLineInput>[];
    for (final line in _lines) {
      final quantity = _money.parse(line.quantity.text);
      final cost = _money.parse(line.cost.text);
      if (quantity == null || quantity <= 0 || cost == null || cost < 0) {
        if (report) {
          setState(
            () => _error =
                'Check quantity and cost for ${line.product.product.name}.',
          );
        }
        return null;
      }
      inputs.add(
        PurchaseLineInput(
          productId: line.product.product.id,
          quantity: quantity,
          unitCost: Money.fromMajor(cost),
        ),
      );
    }
    return inputs;
  }

  Future<void> _newSupplier() async {
    final name = await promptDialog(
      context,
      title: 'New supplier',
      label: 'Supplier name',
      confirmLabel: 'Create',
    );
    if (name == null || name.trim().isEmpty) return;
    try {
      final id = await ref
          .read(purchaseServiceProvider)
          .saveSupplier(ref.read(activeSessionProvider)!, name: name);
      setState(() => _supplierId = id);
    } catch (error) {
      if (mounted) Toast.error(context, error);
    }
  }

  Future<void> _save() async {
    final inputs = _inputs(report: true);
    if (inputs == null) return;
    if (inputs.isEmpty) {
      setState(() => _error = 'Add at least one product.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final service = ref.read(purchaseServiceProvider);
      final session = ref.read(activeSessionProvider)!;
      if (widget.isReturn) {
        await service.returnToSupplier(
          session,
          supplierId: _supplierId,
          reference: _reference.text,
          lines: inputs,
          reason: _reason.text,
        );
      } else {
        await service.receive(
          session,
          supplierId: _supplierId,
          supplierReference: _reference.text,
          lines: inputs,
          discount: Money.fromMajor(_money.parse(_discount.text) ?? 0),
          tax: Money.fromMajor(_money.parse(_tax.text) ?? 0),
          updateCostPrice: _updateCost,
        );
      }
      if (mounted) {
        Navigator.pop(context);
        Toast.success(
          context,
          widget.isReturn
              ? 'Supplier return recorded. Stock reduced.'
              : 'Stock received and added to inventory.',
        );
      }
    } catch (error) {
      if (mounted) setState(() => _error = friendlyError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(activeSessionProvider)!;
    final money = ref.watch(moneyFormatterProvider);
    final inputs = _inputs() ?? const <PurchaseLineInput>[];
    final totals = PurchaseService.totals(
      inputs,
      discount: widget.isReturn
          ? Money.zero
          : Money.fromMajor(money.parse(_discount.text) ?? 0),
      tax: widget.isReturn
          ? Money.zero
          : Money.fromMajor(money.parse(_tax.text) ?? 0),
    );
    final numeric = [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))];
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 900, maxHeight: 760),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              PageHeader(
                icon: widget.isReturn
                    ? Icons.assignment_return_outlined
                    : Icons.move_to_inbox_rounded,
                title: widget.isReturn ? 'Return to supplier' : 'Receive stock',
                subtitle: widget.isReturn
                    ? 'Stock leaves ${session.store.name}.'
                    : 'Stock is added to ${session.store.name}.',
                actions: [
                  IconButton(
                    onPressed: _busy ? null : () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: StreamBuilder<List<Supplier>>(
                      stream: _suppliers,
                      builder: (context, snapshot) {
                        final suppliers = snapshot.data ?? const <Supplier>[];
                        return AppSelect<String?>(
                          items: [
                            SelectItem(null, 'No supplier'),
                            for (final supplier in suppliers)
                              SelectItem(supplier.id, supplier.name),
                          ],
                          value: suppliers.any((s) => s.id == _supplierId)
                              ? _supplierId
                              : null,
                          onChanged: (value) =>
                              setState(() => _supplierId = value),
                          label: 'Supplier',
                          key: ValueKey('${suppliers.length}-$_supplierId'),
                        );
                      },
                    ),
                  ),
                  IconButton(
                    tooltip: 'New supplier',
                    onPressed: _newSupplier,
                    icon: const Icon(Icons.add_business_outlined),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _reference,
                      decoration: InputDecoration(
                        labelText: widget.isReturn
                            ? 'Return reference (optional)'
                            : 'Supplier bill / invoice no. (optional)',
                        helperText: 'Leave empty to number automatically.',
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ProductPicker(onSelected: _add, autofocus: true),
              const SizedBox(height: 10),
              Expanded(
                child: _lines.isEmpty
                    ? const EmptyState(
                        icon: Icons.qr_code_scanner_rounded,
                        title: 'No items yet',
                        message: 'Scan or search products to add them.',
                      )
                    : ListView.separated(
                        itemCount: _lines.length,
                        separatorBuilder: (_, _) => const Divider(),
                        itemBuilder: (context, index) {
                          final line = _lines[index];
                          final q = money.parse(line.quantity.text);
                          final c = money.parse(line.cost.text);
                          return Padding(
                            key: ValueKey(line.product.product.id),
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        line.product.product.name,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      Text(
                                        '${line.product.product.sku} · in stock ${_qty(line.product.store.stockQty)}',
                                        style: context.text.bodySmall,
                                      ),
                                    ],
                                  ),
                                ),
                                SizedBox(
                                  width: 110,
                                  child: TextField(
                                    controller: line.quantity,
                                    textAlign: TextAlign.end,
                                    inputFormatters: numeric,
                                    decoration: InputDecoration(
                                      labelText: 'Qty',
                                      suffixText: line.product.product.unit,
                                    ),
                                    onChanged: (_) => setState(() {}),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                SizedBox(
                                  width: 130,
                                  child: TextField(
                                    controller: line.cost,
                                    textAlign: TextAlign.end,
                                    inputFormatters: numeric,
                                    decoration: InputDecoration(
                                      labelText: 'Unit cost',
                                      prefixText: '${money.symbol} ',
                                    ),
                                    onChanged: (_) => setState(() {}),
                                  ),
                                ),
                                SizedBox(
                                  width: 130,
                                  child: Text(
                                    q == null || c == null
                                        ? '—'
                                        : money.major(q * c),
                                    textAlign: TextAlign.end,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                                IconButton(
                                  onPressed: () => setState(
                                    () => _lines.removeAt(index).dispose(),
                                  ),
                                  icon: const Icon(Icons.close_rounded),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
              ),
              const Divider(),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: widget.isReturn
                        ? TextField(
                            controller: _reason,
                            decoration: const InputDecoration(
                              labelText:
                                  'Reason (e.g. damaged, expired, wrong item)',
                            ),
                          )
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: TextField(
                                      controller: _discount,
                                      inputFormatters: numeric,
                                      decoration: InputDecoration(
                                        labelText: 'Bill discount',
                                        prefixText: '${money.symbol} ',
                                      ),
                                      onChanged: (_) => setState(() {}),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: TextField(
                                      controller: _tax,
                                      inputFormatters: numeric,
                                      decoration: InputDecoration(
                                        labelText: 'Tax on bill',
                                        prefixText: '${money.symbol} ',
                                      ),
                                      onChanged: (_) => setState(() {}),
                                    ),
                                  ),
                                ],
                              ),
                              CheckboxListTile(
                                contentPadding: EdgeInsets.zero,
                                controlAffinity:
                                    ListTileControlAffinity.leading,
                                value: _updateCost,
                                onChanged: (value) =>
                                    setState(() => _updateCost = value ?? true),
                                title: const Text(
                                  'Update product cost prices to these costs',
                                ),
                              ),
                            ],
                          ),
                  ),
                  const SizedBox(width: 24),
                  SizedBox(
                    width: 260,
                    child: Column(
                      children: [
                        _TotalRow('Subtotal', money.format(totals.subtotal)),
                        if (!widget.isReturn && totals.discount.minorUnits > 0)
                          _TotalRow('Discount', money.format(-totals.discount)),
                        if (!widget.isReturn && totals.tax.minorUnits > 0)
                          _TotalRow('Tax', money.format(totals.tax)),
                        const SizedBox(height: 4),
                        _TotalRow(
                          'Total',
                          money.format(totals.total),
                          large: true,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(_error!, style: TextStyle(color: context.colors.error)),
              ],
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.icon(
                  onPressed: _busy || _lines.isEmpty ? null : _save,
                  icon: const Icon(Icons.check_rounded),
                  label: Text(
                    widget.isReturn ? 'Record return' : 'Receive into stock',
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TotalRow extends StatelessWidget {
  const _TotalRow(this.label, this.value, {this.large = false});
  final String label;
  final String value;
  final bool large;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(
      children: [
        Expanded(child: Text(label)),
        Text(
          value,
          style: (large ? context.text.titleLarge : context.text.bodyMedium)
              ?.copyWith(fontWeight: FontWeight.w800),
        ),
      ],
    ),
  );
}

class _SupplierList extends ConsumerStatefulWidget {
  const _SupplierList();
  @override
  ConsumerState<_SupplierList> createState() => _SupplierListState();
}

class _SupplierListState extends ConsumerState<_SupplierList>
    with AutomaticKeepAliveClientMixin {
  String _search = '';
  late Stream<List<Supplier>> _stream;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _bind();
  }

  void _bind() => _stream = ref
      .read(purchaseServiceProvider)
      .watchSuppliers(ref.read(activeSessionProvider)!, search: _search);

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final canManage = ref
        .watch(activeSessionProvider)!
        .can(Permissions.purchasesManage);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            SizedBox(
              width: 340,
              child: TextField(
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search_rounded),
                  hintText: 'Search suppliers',
                ),
                onChanged: (value) => setState(() {
                  _search = value;
                  _bind();
                }),
              ),
            ),
            const Spacer(),
            if (canManage)
              FilledButton.tonalIcon(
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) => const _SupplierEditor(),
                ),
                icon: const Icon(Icons.add_business_outlined),
                label: const Text('New supplier'),
              ),
          ],
        ),
        const SizedBox(height: 12),
        Expanded(
          child: Card(
            clipBehavior: Clip.antiAlias,
            child: StreamBuilder<List<Supplier>>(
              stream: _stream,
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final suppliers = snapshot.data!;
                if (suppliers.isEmpty) {
                  return const EmptyState(
                    icon: Icons.local_shipping_outlined,
                    title: 'No suppliers yet',
                    message: 'Add the companies you buy stock from.',
                  );
                }
                return ListView.separated(
                  itemCount: suppliers.length,
                  separatorBuilder: (_, _) => const Divider(),
                  itemBuilder: (context, index) {
                    final s = suppliers[index];
                    return ListTile(
                      leading: CircleAvatar(
                        child: Text(s.name.characters.first.toUpperCase()),
                      ),
                      title: Text(
                        s.name,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      subtitle: Text(
                        [
                          ?s.phone,
                          ?s.email,
                          if (s.address.isNotEmpty) s.address,
                        ].join(' · '),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          s.isActive
                              ? const StatusPill(
                                  'Active',
                                  tone: PillTone.success,
                                )
                              : const StatusPill('Inactive'),
                          if (canManage)
                            IconButton(
                              onPressed: () => showDialog<void>(
                                context: context,
                                builder: (_) => _SupplierEditor(supplier: s),
                              ),
                              icon: const Icon(Icons.edit_outlined),
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
    );
  }
}

class _SupplierEditor extends ConsumerStatefulWidget {
  const _SupplierEditor({this.supplier});
  final Supplier? supplier;
  @override
  ConsumerState<_SupplierEditor> createState() => _SupplierEditorState();
}

class _SupplierEditorState extends ConsumerState<_SupplierEditor> {
  late final _name = TextEditingController(text: widget.supplier?.name ?? '');
  late final _phone = TextEditingController(text: widget.supplier?.phone ?? '');
  late final _email = TextEditingController(text: widget.supplier?.email ?? '');
  late final _address = TextEditingController(
    text: widget.supplier?.address ?? '',
  );
  late bool _active = widget.supplier?.isActive ?? true;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _email.dispose();
    _address.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    try {
      await ref
          .read(purchaseServiceProvider)
          .saveSupplier(
            ref.read(activeSessionProvider)!,
            id: widget.supplier?.id,
            name: _name.text,
            phone: _phone.text,
            email: _email.text,
            address: _address.text,
            isActive: _active,
          );
      if (mounted) Navigator.pop(context);
    } catch (error) {
      if (mounted) setState(() => _error = friendlyError(error));
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.supplier == null ? 'New supplier' : 'Edit supplier'),
    content: SizedBox(
      width: 480,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _name,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Name'),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _phone,
                  decoration: const InputDecoration(labelText: 'Phone'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _email,
                  decoration: const InputDecoration(labelText: 'Email'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _address,
            maxLines: 2,
            decoration: const InputDecoration(labelText: 'Address'),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _active,
            onChanged: (value) => setState(() => _active = value),
            title: const Text('Active'),
          ),
          if (_error != null)
            Text(_error!, style: TextStyle(color: context.colors.error)),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(onPressed: _save, child: const Text('Save')),
    ],
  );
}
