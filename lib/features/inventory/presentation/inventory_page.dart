import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/money/money_format.dart';
import '../../../core/ui/ui_kit.dart';
import '../../auth/application/session_controller.dart';
import '../../auth/domain/permissions.dart';
import '../../products/data/product_repository.dart';
import '../../products/presentation/product_picker.dart';
import '../../settings/data/business_settings_repository.dart';
import '../../stores/data/store_repository.dart';
import '../data/inventory_service.dart';

String _qty(double value) => value == value.roundToDouble()
    ? value.toStringAsFixed(0)
    : value.toStringAsFixed(3).replaceFirst(RegExp(r'0+$'), '');

const _movementLabels = {
  'opening': 'Opening',
  'adjustment': 'Adjustment',
  'count': 'Stock count',
  'sale': 'Sale',
  'transfer_in': 'Transfer in',
  'transfer_out': 'Transfer out',
  'purchase': 'Purchase',
  'purchase_return': 'Supplier return',
  'refund': 'Refund',
};

class InventoryPage extends ConsumerStatefulWidget {
  const InventoryPage({super.key});
  @override
  ConsumerState<InventoryPage> createState() => _InventoryPageState();
}

class _InventoryPageState extends ConsumerState<InventoryPage>
    with SingleTickerProviderStateMixin {
  late final _tabs = TabController(length: 2, vsync: this);
  String? _historyProductId;
  String? _historyProductName;

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  void _showHistory(StockRow row) {
    setState(() {
      _historyProductId = row.productId;
      _historyProductName = row.name;
    });
    _tabs.animateTo(1);
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(activeSessionProvider)!;
    final canAdjust = session.can(Permissions.inventoryAdjust);
    final canTransfer = session.can(Permissions.inventoryTransfer);
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PageHeader(
            title: 'Inventory',
            subtitle:
                'Stock levels, counts, transfers and movement history for ${session.store.name}.',
            actions: [
              if (canTransfer)
                OutlinedButton.icon(
                  onPressed: () => showDialog<void>(
                    context: context,
                    builder: (_) => const _TransferDialog(),
                  ),
                  icon: const Icon(Icons.swap_horiz_rounded),
                  label: const Text('Transfer'),
                ),
              if (canAdjust)
                FilledButton.icon(
                  onPressed: () => showDialog<void>(
                    context: context,
                    barrierDismissible: false,
                    builder: (_) => const _StockCountDialog(),
                  ),
                  icon: const Icon(Icons.fact_check_outlined),
                  label: const Text('Stock count'),
                ),
            ],
          ),
          const SizedBox(height: 10),
          TabBar(
            controller: _tabs,
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: const [
              Tab(icon: Icon(Icons.inventory_2_outlined), text: 'Stock'),
              Tab(icon: Icon(Icons.history_rounded), text: 'Movements'),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: TabBarView(
              controller: _tabs,
              children: [
                _StockTab(onHistory: _showHistory),
                _MovementsTab(
                  productId: _historyProductId,
                  productName: _historyProductName,
                  onClearProduct: () => setState(() {
                    _historyProductId = null;
                    _historyProductName = null;
                  }),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StockTab extends ConsumerStatefulWidget {
  const _StockTab({required this.onHistory});
  final ValueChanged<StockRow> onHistory;
  @override
  ConsumerState<_StockTab> createState() => _StockTabState();
}

class _StockTabState extends ConsumerState<_StockTab>
    with AutomaticKeepAliveClientMixin {
  String _search = '';
  StockFilter _filter = StockFilter.all;
  Timer? _debounce;
  late Stream<List<StockRow>> _rows;
  late Stream<StockSummary> _summary;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _bind();
  }

  void _bind() {
    final session = ref.read(activeSessionProvider)!;
    final service = ref.read(inventoryServiceProvider);
    _rows = service.watchStock(session, search: _search, filter: _filter);
    _summary = service.watchSummary(session);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final session = ref.watch(activeSessionProvider)!;
    final money = ref.watch(moneyFormatterProvider);
    final canCost = session.can(Permissions.inventoryViewCost);
    final canAdjust = session.can(Permissions.inventoryAdjust);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        StreamBuilder<StockSummary>(
          stream: _summary,
          builder: (context, snapshot) {
            final s = snapshot.data;
            final cards = [
              StatCard(
                label: 'Tracked products',
                value: s == null ? '—' : '${s.products}',
                icon: Icons.inventory_2_rounded,
                footnote: s == null ? null : '${_qty(s.units)} units in stock',
              ),
              if (canCost)
                StatCard(
                  label: 'Stock value (cost)',
                  value: s == null ? '—' : money.major(s.costValue),
                  icon: Icons.account_balance_wallet_outlined,
                  color: context.tokens.success,
                  footnote: s == null
                      ? null
                      : 'Retail value ${money.major(s.retailValue)}',
                ),
              StatCard(
                label: 'Low stock',
                value: s == null ? '—' : '${s.low}',
                icon: Icons.warning_amber_rounded,
                color: context.tokens.warning,
                footnote: 'At or below reorder level',
              ),
              StatCard(
                label: 'Out of stock',
                value: s == null ? '—' : '${s.out}',
                icon: Icons.remove_shopping_cart_outlined,
                color: context.colors.error,
                footnote: 'Zero or negative',
              ),
            ];
            return Row(
              children: [
                for (var i = 0; i < cards.length; i++) ...[
                  if (i > 0) const SizedBox(width: 12),
                  Expanded(child: cards[i]),
                ],
              ],
            );
          },
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            SizedBox(
              width: 340,
              child: TextField(
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search_rounded),
                  hintText: 'Search name, SKU or barcode',
                ),
                onChanged: (value) {
                  _debounce?.cancel();
                  _debounce = Timer(const Duration(milliseconds: 220), () {
                    if (mounted) {
                      setState(() {
                        _search = value;
                        _bind();
                      });
                    }
                  });
                },
              ),
            ),
            const SizedBox(width: 12),
            for (final (filter, label) in const [
              (StockFilter.all, 'All'),
              (StockFilter.low, 'Low'),
              (StockFilter.out, 'Out of stock'),
              (StockFilter.negative, 'Negative'),
            ])
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: ChoiceChip(
                  label: Text(label),
                  selected: _filter == filter,
                  onSelected: (_) => setState(() {
                    _filter = filter;
                    _bind();
                  }),
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
        Expanded(
          child: Card(
            clipBehavior: Clip.antiAlias,
            child: StreamBuilder<List<StockRow>>(
              stream: _rows,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return EmptyState(
                    icon: Icons.error_outline_rounded,
                    title: 'Stock could not be loaded',
                    message: friendlyError(snapshot.error!),
                  );
                }
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final rows = snapshot.data!;
                if (rows.isEmpty) {
                  return const EmptyState(
                    icon: Icons.inventory_2_outlined,
                    title: 'No products here',
                    message: 'Only products that track stock are listed.',
                  );
                }
                return ListView.separated(
                  itemCount: rows.length,
                  separatorBuilder: (_, _) => const Divider(),
                  itemBuilder: (context, index) => _StockTile(
                    row: rows[index],
                    money: money,
                    showCost: canCost,
                    canAdjust: canAdjust,
                    onHistory: () => widget.onHistory(rows[index]),
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

class _StockTile extends ConsumerWidget {
  const _StockTile({
    required this.row,
    required this.money,
    required this.showCost,
    required this.canAdjust,
    required this.onHistory,
  });
  final StockRow row;
  final MoneyFormatter money;
  final bool showCost;
  final bool canAdjust;
  final VoidCallback onHistory;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tone = row.isOut
        ? PillTone.danger
        : row.isLow
        ? PillTone.warning
        : PillTone.success;
    return InkWell(
      onTap: canAdjust
          ? () => showDialog<void>(
              context: context,
              builder: (_) => _AdjustDialog(row: row),
            )
          : onHistory,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        child: Row(
          children: [
            Expanded(
              flex: 4,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          row.name,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                      if (!row.isActive) ...[
                        const SizedBox(width: 6),
                        const StatusPill('Inactive'),
                      ],
                    ],
                  ),
                  Text(
                    [row.sku, ?row.category].join(' · '),
                    style: context.text.bodySmall?.copyWith(
                      color: context.colors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(
              width: 140,
              child: Align(
                alignment: Alignment.centerLeft,
                child: StatusPill('${_qty(row.stock)} ${row.unit}', tone: tone),
              ),
            ),
            SizedBox(
              width: 110,
              child: Text(
                'Reorder at ${_qty(row.reorderLevel)}',
                style: context.text.bodySmall,
              ),
            ),
            if (showCost)
              SizedBox(
                width: 140,
                child: Text(
                  money.major(row.stock > 0 ? row.stock * row.costPrice : 0),
                  textAlign: TextAlign.end,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            const SizedBox(width: 8),
            PopupMenuButton<String>(
              tooltip: 'Actions',
              onSelected: (action) async {
                switch (action) {
                  case 'adjust':
                    await showDialog<void>(
                      context: context,
                      builder: (_) => _AdjustDialog(row: row),
                    );
                  case 'reorder':
                    final value = await promptDialog(
                      context,
                      title: 'Reorder level · ${row.name}',
                      label: 'Warn when stock falls to',
                      initialValue: _qty(row.reorderLevel),
                      numeric: true,
                      confirmLabel: 'Save',
                    );
                    final level = value == null
                        ? null
                        : ref.read(moneyFormatterProvider).parse(value);
                    if (level == null) return;
                    try {
                      await ref
                          .read(inventoryServiceProvider)
                          .setReorderLevel(
                            ref.read(activeSessionProvider)!,
                            row.productId,
                            level,
                          );
                    } catch (error) {
                      if (context.mounted) Toast.error(context, error);
                    }
                  case 'history':
                    onHistory();
                }
              },
              itemBuilder: (_) => [
                if (canAdjust) ...const [
                  PopupMenuItem(
                    value: 'adjust',
                    child: ListTile(
                      leading: Icon(Icons.tune_rounded),
                      title: Text('Adjust stock'),
                    ),
                  ),
                  PopupMenuItem(
                    value: 'reorder',
                    child: ListTile(
                      leading: Icon(Icons.notification_important_outlined),
                      title: Text('Reorder level'),
                    ),
                  ),
                ],
                const PopupMenuItem(
                  value: 'history',
                  child: ListTile(
                    leading: Icon(Icons.history_rounded),
                    title: Text('Movement history'),
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

class _AdjustDialog extends ConsumerStatefulWidget {
  const _AdjustDialog({required this.row});
  final StockRow row;
  @override
  ConsumerState<_AdjustDialog> createState() => _AdjustDialogState();
}

class _AdjustDialogState extends ConsumerState<_AdjustDialog> {
  AdjustMode _mode = AdjustMode.add;
  final _quantity = TextEditingController();
  final _note = TextEditingController();
  String _reason = adjustmentReasons.first;
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _quantity.dispose();
    _note.dispose();
    super.dispose();
  }

  double? get _value => ref.read(moneyFormatterProvider).parse(_quantity.text);

  double? get _preview {
    final value = _value;
    if (value == null) return null;
    final current = widget.row.stock;
    return switch (_mode) {
      AdjustMode.set => value,
      AdjustMode.add => current + value,
      AdjustMode.remove => current - value,
    };
  }

  Future<void> _save() async {
    final value = _value;
    if (value == null || value < 0) {
      setState(() => _error = 'Enter a valid quantity.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(inventoryServiceProvider)
          .adjust(
            ref.read(activeSessionProvider)!,
            productId: widget.row.productId,
            mode: _mode,
            quantity: value,
            reason: _reason,
            note: _note.text,
          );
      if (mounted) {
        Navigator.pop(context);
        Toast.success(context, 'Stock updated.');
      }
    } catch (error) {
      if (mounted) setState(() => _error = friendlyError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final preview = _preview;
    return AlertDialog(
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Adjust stock'),
          Text(
            '${widget.row.name} · currently ${_qty(widget.row.stock)} ${widget.row.unit}',
            style: context.text.bodySmall?.copyWith(
              color: context.colors.onSurfaceVariant,
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppSegmented<AdjustMode>(
              items: const [
                SegmentItem(AdjustMode.add, 'Add', icon: Icons.add_rounded),
                SegmentItem(
                  AdjustMode.remove,
                  'Remove',
                  icon: Icons.remove_rounded,
                ),
                SegmentItem(AdjustMode.set, 'Set to', icon: Icons.edit_rounded),
              ],
              value: _mode,
              onChanged: (value) => setState(() => _mode = value),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _quantity,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
              ],
              decoration: InputDecoration(
                labelText: 'Quantity',
                suffixText: widget.row.unit,
                helperText: preview == null
                    ? ' '
                    : 'New stock will be ${_qty(preview)} ${widget.row.unit}',
              ),
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) => _save(),
            ),
            const SizedBox(height: 10),
            AppSelect<String>(
              items: [
                for (final reason in adjustmentReasons)
                  SelectItem(reason, reason),
              ],
              value: _reason,
              onChanged: (value) => setState(() => _reason = value ?? _reason),
              label: 'Reason',
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
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _busy ? null : _save,
          child: const Text('Save adjustment'),
        ),
      ],
    );
  }
}

class _CountLine {
  _CountLine(this.product) : counted = TextEditingController();
  final CatalogProduct product;
  final TextEditingController counted;
}

class _StockCountDialog extends ConsumerStatefulWidget {
  const _StockCountDialog();
  @override
  ConsumerState<_StockCountDialog> createState() => _StockCountDialogState();
}

class _StockCountDialogState extends ConsumerState<_StockCountDialog> {
  final _lines = <_CountLine>[];
  final _note = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    for (final line in _lines) {
      line.counted.dispose();
    }
    _note.dispose();
    super.dispose();
  }

  void _add(CatalogProduct product) {
    final existing = _lines
        .where((line) => line.product.product.id == product.product.id)
        .firstOrNull;
    setState(() {
      if (existing != null) {
        // Scanning the same item again counts one more.
        final money = ref.read(moneyFormatterProvider);
        final value = (money.parse(existing.counted.text) ?? 0) + 1;
        existing.counted.text = _qty(value);
      } else {
        _lines.insert(0, _CountLine(product)..counted.text = '1');
      }
    });
  }

  Future<void> _apply() async {
    final money = ref.read(moneyFormatterProvider);
    final counts = <String, double>{};
    for (final line in _lines) {
      final value = money.parse(line.counted.text);
      if (value == null || value < 0) {
        setState(
          () => _error =
              'Enter a counted quantity for ${line.product.product.name}.',
        );
        return;
      }
      counts[line.product.product.id] = value;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final changed = await ref
          .read(inventoryServiceProvider)
          .applyCount(
            ref.read(activeSessionProvider)!,
            counts,
            note: _note.text,
          );
      if (mounted) {
        Navigator.pop(context);
        Toast.success(
          context,
          'Stock count saved. $changed product(s) changed.',
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
    final money = ref.watch(moneyFormatterProvider);
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 820, maxHeight: 700),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              PageHeader(
                icon: Icons.fact_check_outlined,
                title: 'Stock count',
                subtitle:
                    'Scan or search items and enter what is physically on the shelf. '
                    'Scanning an item again adds one.',
                actions: [
                  IconButton(
                    onPressed: _busy ? null : () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              ProductPicker(onSelected: _add, autofocus: true),
              const SizedBox(height: 12),
              Expanded(
                child: _lines.isEmpty
                    ? const EmptyState(
                        icon: Icons.qr_code_scanner_rounded,
                        title: 'Nothing counted yet',
                        message: 'Scan barcodes or search above to add items.',
                      )
                    : ListView.separated(
                        itemCount: _lines.length,
                        separatorBuilder: (_, _) => const Divider(),
                        itemBuilder: (context, index) {
                          final line = _lines[index];
                          final system = line.product.store.stockQty;
                          final counted = money.parse(line.counted.text);
                          final diff = counted == null
                              ? null
                              : counted - system;
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
                                        '${line.product.product.sku} · system ${_qty(system)} ${line.product.product.unit}',
                                        style: context.text.bodySmall,
                                      ),
                                    ],
                                  ),
                                ),
                                SizedBox(
                                  width: 130,
                                  child: TextField(
                                    controller: line.counted,
                                    textAlign: TextAlign.end,
                                    keyboardType:
                                        const TextInputType.numberWithOptions(
                                          decimal: true,
                                        ),
                                    decoration: const InputDecoration(
                                      labelText: 'Counted',
                                    ),
                                    onChanged: (_) => setState(() {}),
                                  ),
                                ),
                                SizedBox(
                                  width: 110,
                                  child: Align(
                                    alignment: Alignment.centerRight,
                                    child: diff == null
                                        ? const SizedBox.shrink()
                                        : StatusPill(
                                            diff == 0
                                                ? 'No change'
                                                : '${diff > 0 ? '+' : ''}${_qty(diff)}',
                                            tone: diff == 0
                                                ? PillTone.neutral
                                                : diff > 0
                                                ? PillTone.success
                                                : PillTone.danger,
                                          ),
                                  ),
                                ),
                                IconButton(
                                  tooltip: 'Remove',
                                  onPressed: () => setState(
                                    () => _lines
                                        .removeAt(index)
                                        .counted
                                        .dispose(),
                                  ),
                                  icon: const Icon(Icons.close_rounded),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _note,
                decoration: const InputDecoration(
                  labelText: 'Note (e.g. aisle 3, monthly count)',
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(_error!, style: TextStyle(color: context.colors.error)),
              ],
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.icon(
                  onPressed: _busy || _lines.isEmpty ? null : _apply,
                  icon: const Icon(Icons.check_rounded),
                  label: Text('Apply count (${_lines.length} items)'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TransferLine {
  _TransferLine(this.product) : quantity = TextEditingController(text: '1');
  final CatalogProduct product;
  final TextEditingController quantity;
}

class _TransferDialog extends ConsumerStatefulWidget {
  const _TransferDialog();
  @override
  ConsumerState<_TransferDialog> createState() => _TransferDialogState();
}

class _TransferDialogState extends ConsumerState<_TransferDialog> {
  final _lines = <_TransferLine>[];
  final _note = TextEditingController();
  String? _toStoreId;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    for (final line in _lines) {
      line.quantity.dispose();
    }
    _note.dispose();
    super.dispose();
  }

  void _add(CatalogProduct product) {
    if (_lines.any((line) => line.product.product.id == product.product.id)) {
      return;
    }
    setState(() => _lines.add(_TransferLine(product)));
  }

  Future<void> _submit() async {
    final money = ref.read(moneyFormatterProvider);
    if (_toStoreId == null) {
      setState(() => _error = 'Choose the destination store.');
      return;
    }
    final quantities = <String, double>{};
    for (final line in _lines) {
      final value = money.parse(line.quantity.text);
      if (value == null || value <= 0) {
        setState(
          () => _error = 'Enter a quantity for ${line.product.product.name}.',
        );
        return;
      }
      quantities[line.product.product.id] = value;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(inventoryServiceProvider)
          .transfer(
            ref.read(activeSessionProvider)!,
            toStoreId: _toStoreId!,
            quantities: quantities,
            note: _note.text,
          );
      if (mounted) {
        Navigator.pop(context);
        Toast.success(context, 'Transfer completed.');
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
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760, maxHeight: 680),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              PageHeader(
                icon: Icons.swap_horiz_rounded,
                title: 'Transfer stock',
                subtitle: 'From ${session.store.name} to another branch.',
                actions: [
                  IconButton(
                    onPressed: _busy ? null : () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              CachedStreamBuilder(
                create: ref.read(storeRepositoryProvider).watchAll,
                builder: (context, snapshot) {
                  final stores = (snapshot.data ?? const [])
                      .where((s) => s.isActive && s.id != session.store.id)
                      .toList();
                  if (snapshot.hasData && stores.isEmpty) {
                    return const Text(
                      'Add another active store first (Administration → Stores).',
                    );
                  }
                  return AppSelect<String>(
                    items: [
                      for (final store in stores)
                        SelectItem(store.id, '${store.name} · ${store.code}'),
                    ],
                    value: _toStoreId,
                    onChanged: (value) => setState(() => _toStoreId = value),
                    label: 'Destination store',
                  );
                },
              ),
              const SizedBox(height: 12),
              ProductPicker(onSelected: _add),
              const SizedBox(height: 12),
              Expanded(
                child: _lines.isEmpty
                    ? const EmptyState(
                        icon: Icons.local_shipping_outlined,
                        title: 'No items yet',
                        message: 'Add the products to send.',
                      )
                    : ListView.separated(
                        itemCount: _lines.length,
                        separatorBuilder: (_, _) => const Divider(),
                        itemBuilder: (context, index) {
                          final line = _lines[index];
                          return Row(
                            key: ValueKey(line.product.product.id),
                            children: [
                              Expanded(
                                child: ListTile(
                                  dense: true,
                                  contentPadding: EdgeInsets.zero,
                                  title: Text(line.product.product.name),
                                  subtitle: Text(
                                    'Available ${_qty(line.product.store.stockQty)} ${line.product.product.unit}',
                                  ),
                                ),
                              ),
                              SizedBox(
                                width: 130,
                                child: TextField(
                                  controller: line.quantity,
                                  textAlign: TextAlign.end,
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                        decimal: true,
                                      ),
                                  decoration: InputDecoration(
                                    labelText: 'Quantity',
                                    suffixText: line.product.product.unit,
                                  ),
                                ),
                              ),
                              IconButton(
                                onPressed: () => setState(
                                  () =>
                                      _lines.removeAt(index).quantity.dispose(),
                                ),
                                icon: const Icon(Icons.close_rounded),
                              ),
                            ],
                          );
                        },
                      ),
              ),
              TextField(
                controller: _note,
                decoration: const InputDecoration(
                  labelText: 'Note / reference',
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(_error!, style: TextStyle(color: context.colors.error)),
              ],
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.icon(
                  onPressed: _busy || _lines.isEmpty ? null : _submit,
                  icon: const Icon(Icons.send_rounded),
                  label: const Text('Transfer now'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MovementsTab extends ConsumerStatefulWidget {
  const _MovementsTab({
    required this.productId,
    required this.productName,
    required this.onClearProduct,
  });
  final String? productId;
  final String? productName;
  final VoidCallback onClearProduct;
  @override
  ConsumerState<_MovementsTab> createState() => _MovementsTabState();
}

class _MovementsTabState extends ConsumerState<_MovementsTab> {
  String? _type;
  DateTimeRange? _range;
  late Stream<List<MovementRow>> _stream;

  @override
  void initState() {
    super.initState();
    _bind();
  }

  @override
  void didUpdateWidget(covariant _MovementsTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.productId != widget.productId) _bind();
  }

  /// Re-subscribes only when a filter changes.
  void _bind() {
    final range = _range;
    _stream = ref
        .read(inventoryServiceProvider)
        .watchMovements(
          ref.read(activeSessionProvider)!,
          productId: widget.productId,
          type: _type,
          from: range?.start,
          to: range == null
              ? null
              : DateTime(range.end.year, range.end.month, range.end.day + 1),
        );
  }

  @override
  Widget build(BuildContext context) {
    final stream = _stream;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 10,
          runSpacing: 10,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(
              width: 200,
              child: AppSelect<String?>(
                items: [
                  SelectItem(null, 'All types'),
                  for (final entry in _movementLabels.entries)
                    SelectItem(entry.key, entry.value),
                ],
                value: _type,
                onChanged: (value) => setState(() {
                  _type = value;
                  _bind();
                }),
                label: 'Type',
              ),
            ),
            DateRangeButton(
              value: _range,
              onChanged: (range) => setState(() {
                _range = range;
                _bind();
              }),
            ),
            if (widget.productName != null)
              InputChip(
                avatar: const Icon(Icons.inventory_2_outlined, size: 16),
                label: Text(widget.productName!),
                onDeleted: widget.onClearProduct,
              ),
          ],
        ),
        const SizedBox(height: 12),
        Expanded(
          child: Card(
            clipBehavior: Clip.antiAlias,
            child: StreamBuilder<List<MovementRow>>(
              stream: stream,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return EmptyState(
                    icon: Icons.error_outline_rounded,
                    title: 'Movements could not be loaded',
                    message: friendlyError(snapshot.error!),
                  );
                }
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final rows = snapshot.data!;
                if (rows.isEmpty) {
                  return const EmptyState(
                    icon: Icons.history_rounded,
                    title: 'No stock movements',
                    message: 'Sales, purchases, adjustments and transfers appear here.',
                  );
                }
                return ListView.separated(
                  itemCount: rows.length,
                  separatorBuilder: (_, _) => const Divider(),
                  itemBuilder: (context, index) {
                    final row = rows[index];
                    final m = row.movement;
                    final positive = m.quantity >= 0;
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: positive
                            ? context.tokens.successContainer
                            : context.colors.errorContainer,
                        child: Icon(
                          positive
                              ? Icons.arrow_downward_rounded
                              : Icons.arrow_upward_rounded,
                          color: positive
                              ? context.tokens.success
                              : context.colors.error,
                          size: 18,
                        ),
                      ),
                      title: Text(
                        row.productName,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      subtitle: Text(
                        [
                          _movementLabels[m.type] ?? m.type,
                          if (m.note.isNotEmpty) m.note,
                          row.userName,
                          DateFormat('d MMM y, h:mm a').format(m.createdAt),
                        ].join(' · '),
                      ),
                      trailing: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            '${positive ? '+' : ''}${_qty(m.quantity)}',
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              color: positive
                                  ? context.tokens.success
                                  : context.colors.error,
                            ),
                          ),
                          Text(
                            '${_qty(m.previousQty)} → ${_qty(m.newQty)}',
                            style: context.text.bodySmall,
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
