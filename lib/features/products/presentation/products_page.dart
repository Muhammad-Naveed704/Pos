import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/database_provider.dart';
import '../../../core/ui/ui_kit.dart';
import '../../auth/application/session_controller.dart';
import '../../auth/domain/permissions.dart';
import '../../settings/data/business_settings_repository.dart';
import '../data/product_repository.dart';

class ProductsPage extends ConsumerStatefulWidget {
  const ProductsPage({super.key});
  @override
  ConsumerState<ProductsPage> createState() => _ProductsPageState();
}

class _ProductsPageState extends ConsumerState<ProductsPage> {
  String _search = '';
  int _page = 0;
  Timer? _debounce;
  static const _pageSize = 50;
  late Future<List<CatalogProduct>> _rows = _load();

  /// Re-queries only when search, page or data actually change.
  void _reload([VoidCallback? change]) => setState(() {
    change?.call();
    _rows = _load();
  });

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  Future<List<CatalogProduct>> _load() {
    final session = ref.read(activeSessionProvider)!;
    return ref
        .read(productRepositoryProvider)
        .page(
          storeId: session.store.id,
          search: _search,
          page: _page,
          pageSize: _pageSize,
        );
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(24),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PageHeader(
          title: 'Products',
          subtitle:
              'Store-aware catalog, pricing and stock for ${ref.watch(activeSessionProvider)!.store.name}.',
          actions: [
            if (ref
                .watch(activeSessionProvider)!
                .can(Permissions.productsCreate))
              FilledButton.icon(
                onPressed: () => _edit(context),
                icon: const Icon(Icons.add_rounded),
                label: const Text('New product'),
              ),
          ],
        ),
        const SizedBox(height: 16),
        TextField(
          onChanged: (value) {
            _debounce?.cancel();
            _debounce = Timer(const Duration(milliseconds: 220), () {
              if (mounted) {
                _reload(() {
                  _search = value;
                  _page = 0;
                });
              }
            });
          },
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.search_rounded),
            hintText: 'Search SKU, barcode or product name',
          ),
        ),
        const SizedBox(height: 14),
        Expanded(
          child: Card(
            child: FutureBuilder<List<CatalogProduct>>(
              future: _rows,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return EmptyState(
                    icon: Icons.error_outline_rounded,
                    title: 'Products could not be loaded',
                    message: friendlyError(snapshot.error!),
                  );
                }
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final rows = snapshot.data!;
                final money = ref.watch(moneyFormatterProvider);
                if (rows.isEmpty) {
                  return EmptyState(
                    icon: Icons.inventory_2_outlined,
                    title: _search.isEmpty && _page == 0
                        ? 'No products yet'
                        : 'No products found',
                    message: _search.isEmpty
                        ? 'Create your first product to start selling.'
                        : 'Try a different SKU, barcode or name.',
                  );
                }
                return SingleChildScrollView(
                  child: SizedBox(
                    width: double.infinity,
                    child: DataTable(
                      columns: const [
                        DataColumn(label: Text('Product')),
                        DataColumn(label: Text('SKU / Barcode')),
                        DataColumn(label: Text('Price'), numeric: true),
                        DataColumn(label: Text('Stock'), numeric: true),
                        DataColumn(label: Text('Status')),
                        DataColumn(label: Text('')),
                      ],
                      rows: rows
                          .map(
                            (item) => DataRow(
                              cells: [
                                DataCell(
                                  Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        item.product.name,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      if (item.category != null)
                                        Text(
                                          item.category!.name,
                                          style: Theme.of(context)
                                              .textTheme
                                              .labelSmall,
                                        ),
                                    ],
                                  ),
                                ),
                                DataCell(
                                  Text(
                                    '${item.product.sku}${item.product.barcode == null ? '' : '\n${item.product.barcode}'}',
                                  ),
                                ),
                                DataCell(
                                  Text(
                                    money.major(item.effectivePrice),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                                DataCell(
                                  !item.product.trackInventory
                                      ? const Text('—')
                                      : StatusPill(
                                          money.number(item.store.stockQty),
                                          tone: item.store.stockQty <= 0
                                              ? PillTone.danger
                                              : item.store.stockQty <=
                                                    item.store.reorderLevel
                                              ? PillTone.warning
                                              : PillTone.success,
                                        ),
                                ),
                                DataCell(
                                  item.product.isActive &&
                                          item.store.isAvailable
                                      ? const StatusPill(
                                          'Active',
                                          tone: PillTone.success,
                                        )
                                      : const StatusPill('Inactive'),
                                ),
                                DataCell(
                                  PopupMenuButton<String>(
                                    onSelected: (value) =>
                                        _action(context, value, item),
                                    itemBuilder: (_) => const [
                                      PopupMenuItem(
                                        value: 'edit',
                                        child: Text('Edit'),
                                      ),
                                      PopupMenuItem(
                                        value: 'duplicate',
                                        child: Text('Duplicate'),
                                      ),
                                      PopupMenuItem(
                                        value: 'toggle',
                                        child: Text('Activate / deactivate'),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          )
                          .toList(),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            OutlinedButton(
              onPressed: _page == 0 ? null : () => _reload(() => _page -= 1),
              child: const Text('Previous'),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Text('Page ${_page + 1}'),
            ),
            FutureBuilder<List<CatalogProduct>>(
              future: _rows,
              builder: (context, snapshot) => OutlinedButton(
                onPressed: (snapshot.data?.length ?? 0) < _pageSize
                    ? null
                    : () => _reload(() => _page += 1),
                child: const Text('Next'),
              ),
            ),
          ],
        ),
      ],
    ),
  );

  Future<void> _action(
    BuildContext context,
    String action,
    CatalogProduct item,
  ) async {
    final repository = ref.read(productRepositoryProvider);
    final session = ref.read(activeSessionProvider)!;
    if (action == 'edit') await _edit(context, item: item);
    if (action == 'toggle') {
      await repository.setActive(
        session,
        item.product.id,
        !item.product.isActive,
      );
    }
    if (action == 'duplicate') {
      if (!context.mounted) return;
      final sku = await _textPrompt(
        context,
        'Duplicate product',
        'New unique SKU',
      );
      if (sku != null) {
        await repository.duplicate(session: session, source: item, newSku: sku);
      }
    }
    if (mounted) _reload();
  }

  Future<void> _edit(BuildContext context, {CatalogProduct? item}) async {
    final database = ref.read(databaseProvider);
    final categories = await (database.select(
      database.categories,
    )..where((row) => row.isActive.equals(true))).get();
    if (!context.mounted) return;
    final money = ref.read(moneyFormatterProvider);
    // Pre-fill numbers with the store's decimal separator so they parse back
    // exactly (e.g. 1.125 kg is not mistaken for 1,125).
    String n(num? value, [String empty = '0']) {
      if (value == null) return empty;
      final text = value == value.roundToDouble()
          ? value.toStringAsFixed(0)
          : value.toString();
      return money.decimalSeparator == ',' ? text.replaceAll('.', ',') : text;
    }

    final sku = TextEditingController(text: item?.product.sku ?? '');
    final barcode = TextEditingController(text: item?.product.barcode ?? '');
    final name = TextEditingController(text: item?.product.name ?? '');
    final shortName = TextEditingController(
      text: item?.product.shortName ?? '',
    );
    final cost = TextEditingController(text: n(item?.product.costPrice));
    final price = TextEditingController(text: n(item?.product.salePrice));
    final wholesale = TextEditingController(
      text: n(item?.product.wholesalePrice, ''),
    );
    final tax = TextEditingController(text: n(item?.product.taxRate));
    final discount = TextEditingController(
      text: n(item?.product.defaultDiscount),
    );
    final unit = TextEditingController(text: item?.product.unit ?? 'each');
    final stock = TextEditingController(text: n(item?.store.stockQty));
    final reorder = TextEditingController(text: n(item?.store.reorderLevel));
    final customPrice = TextEditingController(
      text: n(item?.store.customSalePrice, ''),
    );
    final customDiscount = TextEditingController(
      text: n(item?.store.customDiscount, ''),
    );
    final imagePath = TextEditingController(
      text: item?.product.imagePath ?? '',
    );
    String? categoryId = item?.product.categoryId;
    var active = item?.product.isActive ?? true;
    var tracked = item?.product.trackInventory ?? true;
    var available = item?.store.isAvailable ?? true;
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(item == null ? 'New product' : 'Edit product'),
          content: SizedBox(
            width: 720,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: name,
                          autofocus: true,
                          decoration: const InputDecoration(
                            labelText: 'Product name',
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: shortName,
                          decoration: const InputDecoration(
                            labelText: 'Short name',
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: sku,
                          decoration: const InputDecoration(labelText: 'SKU'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: barcode,
                          decoration: const InputDecoration(
                            labelText: 'Barcode',
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: DropdownButtonFormField<String?>(
                          menuMaxHeight: 360,
                          initialValue: categoryId,
                          decoration: const InputDecoration(
                            labelText: 'Category',
                          ),
                          items: [
                            const DropdownMenuItem(
                              value: null,
                              child: Text('Uncategorized'),
                            ),
                            ...categories.map(
                              (value) => DropdownMenuItem(
                                value: value.id,
                                child: Text(value.name),
                              ),
                            ),
                          ],
                          onChanged: (value) => categoryId = value,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: cost,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Cost price',
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: price,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Sale price',
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: wholesale,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Wholesale price',
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: tax,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(labelText: 'Tax %'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: discount,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Default discount %',
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: unit,
                          decoration: const InputDecoration(labelText: 'Unit'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: stock,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Store stock',
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: reorder,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Reorder level',
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: customPrice,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Store price override',
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        flex: 2,
                        child: TextField(
                          controller: imagePath,
                          decoration: const InputDecoration(
                            labelText: 'Product image path (optional)',
                            prefixIcon: Icon(Icons.image_outlined),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: customDiscount,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Store discount %',
                          ),
                        ),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: SwitchListTile(
                          value: active,
                          onChanged: (value) =>
                              setDialogState(() => active = value),
                          title: const Text('Active'),
                        ),
                      ),
                      Expanded(
                        child: SwitchListTile(
                          value: tracked,
                          onChanged: (value) =>
                              setDialogState(() => tracked = value),
                          title: const Text('Track stock'),
                        ),
                      ),
                      Expanded(
                        child: SwitchListTile(
                          value: available,
                          onChanged: (value) =>
                              setDialogState(() => available = value),
                          title: const Text('Available here'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Save product'),
            ),
          ],
        ),
      ),
    );
    if (saved != true) return;
    await ref
        .read(productRepositoryProvider)
        .save(
          session: ref.read(activeSessionProvider)!,
          id: item?.product.id,
          input: ProductInput(
            sku: sku.text,
            barcode: barcode.text,
            name: name.text,
            shortName: shortName.text,
            categoryId: categoryId,
            costPrice: money.parse(cost.text) ?? 0,
            salePrice: money.parse(price.text) ?? 0,
            wholesalePrice: money.parse(wholesale.text),
            taxRate: money.parse(tax.text) ?? 0,
            defaultDiscount: money.parse(discount.text) ?? 0,
            unit: unit.text,
            imagePath: imagePath.text,
            isActive: active,
            trackInventory: tracked,
            stockQty: money.parse(stock.text) ?? 0,
            reorderLevel: money.parse(reorder.text) ?? 0,
            customSalePrice: money.parse(customPrice.text),
            customDiscount: money.parse(customDiscount.text),
            isAvailable: available,
          ),
        );
    if (mounted) _reload();
  }

  Future<String?> _textPrompt(
    BuildContext context,
    String title,
    String label,
  ) async {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(labelText: label),
          onSubmitted: (value) => Navigator.pop(context, value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
  }
}
