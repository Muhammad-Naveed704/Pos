import 'dart:async';

import 'package:drift/drift.dart' show OrderingTerm;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/database_provider.dart';
import '../../../core/ui/ui_kit.dart';
import '../../auth/application/session_controller.dart';
import '../../backup/application/backup_providers.dart';
import '../../auth/domain/permissions.dart';
import '../../settings/data/business_settings_repository.dart';
import '../../../core/ui/import_dialog.dart';
import '../data/product_import_service.dart';
import '../data/product_repository.dart';
import 'product_editor.dart';

class ProductsPage extends ConsumerStatefulWidget {
  const ProductsPage({this.initialSearch = '', super.key});

  /// From the top-bar search (`/products?q=`).
  final String initialSearch;
  @override
  ConsumerState<ProductsPage> createState() => _ProductsPageState();
}

class _ProductsPageState extends ConsumerState<ProductsPage> {
  late String _search = widget.initialSearch;
  late final _searchController = TextEditingController(text: _search);
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
  void didUpdateWidget(ProductsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialSearch != widget.initialSearch) {
      _searchController.text = widget.initialSearch;
      _reload(() {
        _search = widget.initialSearch;
        _page = 0;
      });
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
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

  Widget _status(CatalogProduct item) {
    if (!item.product.isActive || !item.store.isAvailable) {
      return const StatusPill('Inactive', icon: Icons.circle);
    }
    if (item.product.trackInventory) {
      if (item.store.stockQty <= 0) {
        return const StatusPill(
          'Out of stock',
          tone: PillTone.danger,
          icon: Icons.circle,
        );
      }
      if (item.store.stockQty <= item.store.reorderLevel) {
        return const StatusPill(
          'Low stock',
          tone: PillTone.warning,
          icon: Icons.circle,
        );
      }
    }
    return const StatusPill(
      'Active',
      tone: PillTone.success,
      icon: Icons.circle,
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
            DataMenu(
              canImport: ref
                  .watch(activeSessionProvider)!
                  .can(Permissions.productsImport),
              onImport: () => _import(context),
              onTemplate: () => saveCsvFile(
                ProductImportService.template(),
                fileName: 'storeflow-products-template.csv',
              ),
              onExport: () => _export(context),
            ),
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
          controller: _searchController,
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
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                Expanded(
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
                                        Row(
                                          children: [
                                            ProductThumb(
                                              name: item.product.name,
                                              path: item.product.imagePath,
                                              size: 44,
                                            ),
                                            const SizedBox(width: 14),
                                            Flexible(
                                              child: Column(
                                                mainAxisAlignment:
                                                    MainAxisAlignment.center,
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    item.product.name,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: const TextStyle(
                                                      fontWeight:
                                                          FontWeight.w700,
                                                    ),
                                                  ),
                                                  Text(
                                                    item.category?.name ??
                                                        'Uncategorized',
                                                    style: context
                                                        .text
                                                        .bodySmall
                                                        ?.copyWith(
                                                          color: context
                                                              .colors
                                                              .onSurfaceVariant,
                                                        ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ),
                                        onTap: () =>
                                            _action(context, 'edit', item),
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
                                                '${_qty(item.store.stockQty)} in stock',
                                                tone: item.store.stockQty <= 0
                                                    ? PillTone.danger
                                                    : item.store.stockQty <=
                                                          item
                                                              .store
                                                              .reorderLevel
                                                    ? PillTone.warning
                                                    : PillTone.success,
                                              ),
                                      ),
                                      DataCell(_status(item)),
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
                                              child: Text(
                                                'Activate / deactivate',
                                              ),
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
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 10,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      FutureBuilder<List<CatalogProduct>>(
                        future: _rows,
                        builder: (context, snapshot) {
                          final count = snapshot.data?.length ?? 0;
                          return Text(
                            count == 0
                                ? ''
                                : 'Showing ${_page * _pageSize + 1} to ${_page * _pageSize + count} products',
                            style: context.text.bodyMedium?.copyWith(
                              color: context.colors.onSurfaceVariant,
                            ),
                          );
                        },
                      ),
                      const Spacer(),
                      OutlinedButton(
                        onPressed: _page == 0
                            ? null
                            : () => _reload(() => _page -= 1),
                        child: const Text('Previous'),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        child: FilledButton(
                          onPressed: () {},
                          style: FilledButton.styleFrom(
                            minimumSize: const Size(44, 44),
                          ),
                          child: Text('${_page + 1}'),
                        ),
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
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  );

  Future<void> _import(BuildContext context) async {
    final service = ref.read(productImportServiceProvider);
    final session = ref.read(activeSessionProvider)!;
    final changed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => ImportDialog<ProductImportPlan>(
        title: 'Import products',
        subject: 'products',
        templateFileName: 'storeflow-products-template.csv',
        template: ProductImportService.template,
        aliases: ProductImportService.aliases,
        columnsHelp: const [
          ('sku', 'Required. Unique product code; matches existing products.'),
          ('name', 'Required.'),
          ('sale_price', 'Required. Selling price.'),
          ('barcode', 'Optional, must be unique.'),
          (
            'category',
            'Optional. Missing categories are created. Use Parent > Child.',
          ),
          ('cost_price', 'Optional.'),
          (
            'stock',
            'Optional. Stock in the current store (records a stock movement).',
          ),
          ('tax_rate', 'Optional percent 0-100.'),
          ('discount', 'Optional percent 0-100.'),
          ('unit', 'Optional, e.g. each, kg, box.'),
          ('reorder_level', 'Optional.'),
          ('track_stock', 'Optional yes/no.'),
          ('active', 'Optional yes/no.'),
        ],
        prepare: (table, update) =>
            service.prepare(session, table, updateExisting: update),
        previewOf: (plan) => plan.preview,
        apply: (plan) async {
          // Safety backup first (if enabled in Data & backup).
          await ref
              .read(backupServiceProvider)
              .beforeRiskyOperation(session, 'product import');
          return service.apply(session, plan);
        },
      ),
    );
    if (changed == true) _reload();
  }

  Future<void> _export(BuildContext context) async {
    try {
      final rows = await ref
          .read(productImportServiceProvider)
          .export(ref.read(activeSessionProvider)!);
      final path = await saveCsvFile(rows, fileName: 'storeflow-products.csv');
      if (path != null && context.mounted) {
        Toast.success(context, '${rows.length - 1} products exported.');
      }
    } catch (error) {
      if (context.mounted) Toast.error(context, error);
    }
  }

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
    final categories =
        await (database.select(database.categories)
              ..where((row) => row.isActive.equals(true))
              ..orderBy([(row) => OrderingTerm.asc(row.name)]))
            .get();
    if (!context.mounted) return;
    final saved = await showProductEditor(
      context,
      categories: categories,
      item: item,
    );
    if (saved && mounted) _reload();
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

String _qty(double value) => value == value.roundToDouble()
    ? value.toStringAsFixed(0)
    : value.toStringAsFixed(3).replaceFirst(RegExp(r'0+$'), '');
