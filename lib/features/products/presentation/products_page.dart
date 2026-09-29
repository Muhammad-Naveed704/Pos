import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/database_provider.dart';
import '../../auth/application/session_controller.dart';
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

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  Future<List<CatalogProduct>> _load() {
    final session = ref.read(activeSessionProvider)!;
    return ref
        .read(productRepositoryProvider)
        .page(storeId: session.store.id, search: _search, page: _page);
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(24),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Products',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                Text(
                  'Store-aware catalog and inventory.',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const Spacer(),
            FilledButton.icon(
              onPressed: () => _edit(context),
              icon: const Icon(Icons.add),
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
                setState(() {
                  _search = value;
                  _page = 0;
                });
              }
            });
          },
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.search),
            hintText: 'Search SKU, barcode or product name',
          ),
        ),
        const SizedBox(height: 14),
        Expanded(
          child: Card(
            child: FutureBuilder<List<CatalogProduct>>(
              future: _load(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final rows = snapshot.data!;
                if (rows.isEmpty) {
                  return const Center(child: Text('No products found.'));
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
                                    'Rs ${item.effectivePrice.toStringAsFixed(2)}',
                                  ),
                                ),
                                DataCell(
                                  Text(
                                    item.product.trackInventory
                                        ? item.store.stockQty.toStringAsFixed(2)
                                        : '—',
                                  ),
                                ),
                                DataCell(
                                  Chip(
                                    label: Text(
                                      item.product.isActive &&
                                              item.store.isAvailable
                                          ? 'Active'
                                          : 'Inactive',
                                    ),
                                  ),
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
              onPressed: _page == 0 ? null : () => setState(() => _page -= 1),
              child: const Text('Previous'),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Text('Page ${_page + 1}'),
            ),
            OutlinedButton(
              onPressed: () => setState(() => _page += 1),
              child: const Text('Next'),
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
    if (mounted) setState(() {});
  }

  Future<void> _edit(BuildContext context, {CatalogProduct? item}) async {
    final database = ref.read(databaseProvider);
    final categories = await (database.select(
      database.categories,
    )..where((row) => row.isActive.equals(true))).get();
    if (!context.mounted) return;
    final sku = TextEditingController(text: item?.product.sku ?? '');
    final barcode = TextEditingController(text: item?.product.barcode ?? '');
    final name = TextEditingController(text: item?.product.name ?? '');
    final shortName = TextEditingController(
      text: item?.product.shortName ?? '',
    );
    final cost = TextEditingController(text: '${item?.product.costPrice ?? 0}');
    final price = TextEditingController(
      text: '${item?.product.salePrice ?? 0}',
    );
    final wholesale = TextEditingController(
      text: '${item?.product.wholesalePrice ?? ''}',
    );
    final tax = TextEditingController(text: '${item?.product.taxRate ?? 0}');
    final discount = TextEditingController(
      text: '${item?.product.defaultDiscount ?? 0}',
    );
    final unit = TextEditingController(text: item?.product.unit ?? 'each');
    final stock = TextEditingController(text: '${item?.store.stockQty ?? 0}');
    final reorder = TextEditingController(
      text: '${item?.store.reorderLevel ?? 0}',
    );
    final customPrice = TextEditingController(
      text: '${item?.store.customSalePrice ?? ''}',
    );
    final customDiscount = TextEditingController(
      text: '${item?.store.customDiscount ?? ''}',
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
            costPrice: double.tryParse(cost.text) ?? 0,
            salePrice: double.tryParse(price.text) ?? 0,
            wholesalePrice: double.tryParse(wholesale.text),
            taxRate: double.tryParse(tax.text) ?? 0,
            defaultDiscount: double.tryParse(discount.text) ?? 0,
            unit: unit.text,
            imagePath: imagePath.text,
            isActive: active,
            trackInventory: tracked,
            stockQty: double.tryParse(stock.text) ?? 0,
            reorderLevel: double.tryParse(reorder.text) ?? 0,
            customSalePrice: double.tryParse(customPrice.text),
            customDiscount: double.tryParse(customDiscount.text),
            isAvailable: available,
          ),
        );
    if (mounted) setState(() {});
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
