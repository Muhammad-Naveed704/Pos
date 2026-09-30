import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/csv/csv_table.dart';
import '../../../core/csv/import_models.dart';
import '../../../core/database/app_database.dart';
import '../../../core/database/database_provider.dart';
import '../../auth/domain/app_session.dart';
import '../../auth/domain/permission_guard.dart';
import '../../auth/domain/permissions.dart';

final productImportServiceProvider = Provider<ProductImportService>(
  (ref) => ProductImportService(ref.watch(databaseProvider)),
);

/// One validated product row. Nullable fields were not present in the CSV
/// and keep their existing value on update.
class _ProductRow {
  _ProductRow({
    required this.line,
    required this.sku,
    required this.name,
    required this.salePrice,
    this.existingId,
    this.barcode,
    this.shortName,
    this.categoryPath,
    this.costPrice,
    this.wholesalePrice,
    this.taxRate,
    this.discount,
    this.unit,
    this.stock,
    this.reorderLevel,
    this.trackStock,
    this.active,
  });

  final int line;
  final String sku;
  final String name;
  final double salePrice;
  final String? existingId;
  final String? barcode;
  final String? shortName;

  /// Category names from root to leaf, e.g. ['Grocery', 'Tea'].
  final List<String>? categoryPath;
  final double? costPrice;
  final double? wholesalePrice;
  final double? taxRate;
  final double? discount;
  final String? unit;
  final double? stock;
  final double? reorderLevel;
  final bool? trackStock;
  final bool? active;
}

class ProductImportPlan {
  const ProductImportPlan._(this.preview, this._rows, this._newCategories);
  final ImportPreview preview;
  final List<_ProductRow> _rows;
  final List<List<String>> _newCategories;
}

class ProductImportService {
  ProductImportService(this._database, {Uuid? uuid})
    : _uuid = uuid ?? const Uuid();

  final AppDatabase _database;
  final Uuid _uuid;

  static const columns = [
    'sku',
    'name',
    'sale_price',
    'barcode',
    'category',
    'short_name',
    'cost_price',
    'wholesale_price',
    'tax_rate',
    'discount',
    'unit',
    'stock',
    'reorder_level',
    'track_stock',
    'active',
  ];

  static const required = ['sku', 'name', 'sale_price'];

  static const aliases = {
    'product_name': 'name',
    'product': 'name',
    'item': 'name',
    'item_name': 'name',
    'code': 'sku',
    'item_code': 'sku',
    'product_code': 'sku',
    'price': 'sale_price',
    'selling_price': 'sale_price',
    'retail_price': 'sale_price',
    'mrp': 'sale_price',
    'cost': 'cost_price',
    'purchase_price': 'cost_price',
    'wholesale': 'wholesale_price',
    'tax': 'tax_rate',
    'tax_percent': 'tax_rate',
    'gst': 'tax_rate',
    'vat': 'tax_rate',
    'discount_percent': 'discount',
    'default_discount': 'discount',
    'qty': 'stock',
    'quantity': 'stock',
    'stock_qty': 'stock',
    'opening_stock': 'stock',
    'reorder': 'reorder_level',
    'min_stock': 'reorder_level',
    'category_name': 'category',
    'group': 'category',
    'ean': 'barcode',
    'upc': 'barcode',
    'uom': 'unit',
  };

  static List<List<Object?>> template() => [
    columns,
    [
      'TEA-500',
      'Premium Tea 500g',
      450,
      '8964000123456',
      'Grocery > Tea',
      'Tea 500g',
      380,
      420,
      0,
      0,
      'each',
      24,
      5,
      'yes',
      'yes',
    ],
    [
      'SUGAR-1KG',
      'Sugar',
      160,
      '',
      'Grocery',
      '',
      140,
      '',
      0,
      0,
      'kg',
      50.5,
      10,
      'yes',
      'yes',
    ],
  ];

  static List<String> _categoryPath(String value) => value
      .split(RegExp(r'\s*[>/\\]\s*'))
      .map((part) => part.trim())
      .where((part) => part.isNotEmpty)
      .toList();

  Future<ProductImportPlan> prepare(
    AppSession session,
    CsvTable table, {
    bool updateExisting = true,
  }) async {
    PermissionGuard.require(session, Permissions.productsImport);
    final missing = required.where((header) => !table.has(header)).toList();
    if (missing.isNotEmpty) {
      throw ImportFormatException(
        'Missing required column(s): ${missing.join(', ')}. '
        'Download the template to see the expected headers.',
      );
    }

    final existing = await _database
        .customSelect('SELECT id, sku, barcode FROM products')
        .get();
    final idBySku = {
      for (final row in existing)
        row.read<String>('sku').toUpperCase(): row.read<String>('id'),
    };
    final skuByBarcode = {
      for (final row in existing)
        if (row.readNullable<String>('barcode') != null)
          row.read<String>('barcode'): row.read<String>('sku').toUpperCase(),
    };
    final categoryKeys = await _categoryKeys();

    final results = <ImportRowResult>[];
    final rows = <_ProductRow>[];
    final seenSkus = <String, int>{};
    final seenBarcodes = <String, String>{};
    final newCategories = <String, List<String>>{};

    for (final row in table.rows) {
      final messages = <String>[];
      final sku = row.text('sku').toUpperCase();
      final name = row.text('name');
      final label = [sku, name].where((part) => part.isNotEmpty).join(' · ');
      if (sku.isEmpty) messages.add('SKU is required.');
      if (sku.length > 80) messages.add('SKU is longer than 80 characters.');
      if (name.isEmpty) messages.add('Name is required.');
      if (name.length > 180) {
        messages.add('Name is longer than 180 characters.');
      }
      if (seenSkus.containsKey(sku) && sku.isNotEmpty) {
        messages.add('Duplicate SKU (also on line ${seenSkus[sku]}).');
      }

      double? number(String key, {double? min, double? max}) {
        if (row.text(key).isEmpty) return null;
        final value = row.number(key);
        if (value == null) {
          messages.add('“${row.text(key)}” is not a valid $key.');
          return null;
        }
        if (min != null && value < min) {
          messages.add('$key cannot be below $min.');
        }
        if (max != null && value > max) {
          messages.add('$key cannot exceed $max.');
        }
        return value;
      }

      bool? flag(String key) {
        if (row.text(key).isEmpty) return null;
        final value = row.flag(key);
        if (value == null) messages.add('$key must be yes or no.');
        return value;
      }

      final salePrice = number('sale_price', min: 0);
      if (row.text('sale_price').isEmpty) {
        messages.add('Sale price is required.');
      }
      final barcode = row.optional('barcode');
      if (barcode != null) {
        final owner = skuByBarcode[barcode];
        if (owner != null && owner != sku) {
          messages.add('Barcode $barcode already belongs to SKU $owner.');
        }
        final inFile = seenBarcodes[barcode];
        if (inFile != null && inFile != sku) {
          messages.add('Barcode $barcode is repeated for SKU $inFile.');
        }
      }
      final path = row.optional('category') == null
          ? null
          : _categoryPath(row.text('category'));
      final parsed = _ProductRow(
        line: row.line,
        sku: sku,
        name: name,
        salePrice: salePrice ?? 0,
        existingId: idBySku[sku],
        barcode: barcode,
        shortName: row.optional('short_name'),
        categoryPath: path == null || path.isEmpty ? null : path,
        costPrice: number('cost_price', min: 0),
        wholesalePrice: number('wholesale_price', min: 0),
        taxRate: number('tax_rate', min: 0, max: 100),
        discount: number('discount', min: 0, max: 100),
        unit: row.optional('unit'),
        stock: number('stock'),
        reorderLevel: number('reorder_level', min: 0),
        trackStock: flag('track_stock'),
        active: flag('active'),
      );

      if (sku.isNotEmpty) seenSkus.putIfAbsent(sku, () => row.line);
      if (barcode != null && sku.isNotEmpty) {
        seenBarcodes.putIfAbsent(barcode, () => sku);
      }

      final ImportAction action;
      if (messages.isNotEmpty) {
        action = ImportAction.error;
      } else if (parsed.existingId != null) {
        action = updateExisting ? ImportAction.update : ImportAction.skip;
        if (!updateExisting) messages.add('SKU exists; left unchanged.');
      } else {
        action = ImportAction.create;
      }
      if (action == ImportAction.create || action == ImportAction.update) {
        rows.add(parsed);
        final categoryPath = parsed.categoryPath;
        if (categoryPath != null) {
          for (var depth = 1; depth <= categoryPath.length; depth++) {
            final prefix = categoryPath.sublist(0, depth);
            final key = _pathKey(prefix);
            if (!categoryKeys.containsKey(key)) newCategories[key] = prefix;
          }
        }
      }
      results.add(
        ImportRowResult(
          line: row.line,
          action: action,
          label: label.isEmpty ? '(blank)' : label,
          messages: messages,
        ),
      );
    }

    return ProductImportPlan._(
      ImportPreview(
        rows: results,
        notes: [
          if (newCategories.isNotEmpty)
            '${newCategories.length} new categor${newCategories.length == 1 ? 'y' : 'ies'} will be created: '
                '${newCategories.values.map((path) => path.join(' › ')).take(8).join(', ')}'
                '${newCategories.length > 8 ? '…' : ''}',
          'Stock and availability apply to ${session.store.name}.',
        ],
      ),
      rows,
      newCategories.values.toList(),
    );
  }

  static String _pathKey(List<String> path) =>
      path.map((part) => part.toLowerCase()).join('\u0000');

  /// Maps lower-cased category paths to ids.
  Future<Map<String, String>> _categoryKeys() async {
    final categories = await _database.select(_database.categories).get();
    final byId = {for (final category in categories) category.id: category};
    List<String> pathOf(Category category) {
      final path = <String>[];
      Category? current = category;
      final guard = <String>{};
      while (current != null && guard.add(current.id)) {
        path.insert(0, current.name);
        current = current.parentId == null ? null : byId[current.parentId];
      }
      return path;
    }

    return {
      for (final category in categories)
        _pathKey(pathOf(category)): category.id,
      // Plain names also match (first one wins) so "Tea" finds "Grocery › Tea".
      for (final category in categories.reversed)
        category.name.toLowerCase(): category.id,
    };
  }

  Future<ImportOutcome> apply(
    AppSession session,
    ProductImportPlan plan,
  ) async {
    PermissionGuard.require(session, Permissions.productsImport);
    final rows = plan._rows;
    if (rows.any((row) => row.existingId == null)) {
      PermissionGuard.require(session, Permissions.productsCreate);
    }
    if (rows.any((row) => row.existingId != null)) {
      PermissionGuard.require(session, Permissions.productsEdit);
    }
    final now = DateTime.now();
    var created = 0;
    var updated = 0;
    var categoriesCreated = 0;
    var movements = 0;

    await _database.transaction(() async {
      final categoryKeys = await _categoryKeys();
      final usedCodes =
          (await _database.customSelect('SELECT code FROM categories').get())
              .map((row) => row.read<String>('code'))
              .toSet();
      String uniqueCode(String name) {
        var base = name.toUpperCase().replaceAll(RegExp('[^A-Z0-9]'), '');
        if (base.isEmpty) base = 'CAT';
        if (base.length > 24) base = base.substring(0, 24);
        var code = base;
        var suffix = 2;
        while (usedCodes.contains(code)) {
          code = '$base$suffix';
          suffix++;
        }
        usedCodes.add(code);
        return code;
      }

      // Parents before children.
      final pending = [...plan._newCategories]
        ..sort((a, b) => a.length.compareTo(b.length));
      for (final path in pending) {
        final key = _pathKey(path);
        if (categoryKeys.containsKey(key)) continue;
        final parentId = path.length == 1
            ? null
            : categoryKeys[_pathKey(path.sublist(0, path.length - 1))];
        final id = _uuid.v4();
        await _database
            .into(_database.categories)
            .insert(
              CategoriesCompanion.insert(
                id: id,
                name: path.last,
                code: uniqueCode(path.last),
                parentId: Value(parentId),
                createdAt: now,
                updatedAt: now,
              ),
            );
        categoryKeys[key] = id;
        categoryKeys.putIfAbsent(path.last.toLowerCase(), () => id);
        categoriesCreated++;
      }

      final storeId = session.store.id;
      for (final row in rows) {
        final path = row.categoryPath;
        final categoryId = path == null
            ? null
            : categoryKeys[_pathKey(path)] ??
                  categoryKeys[path.last.toLowerCase()];
        final productId = row.existingId ?? _uuid.v4();
        final current = row.existingId == null
            ? null
            : await (_database.select(
                _database.products,
              )..where((p) => p.id.equals(productId))).getSingle();
        await _database
            .into(_database.products)
            .insertOnConflictUpdate(
              ProductsCompanion.insert(
                id: productId,
                sku: row.sku,
                barcode: Value(row.barcode ?? current?.barcode),
                name: row.name,
                shortName: Value(row.shortName ?? current?.shortName),
                categoryId: Value(
                  path == null ? current?.categoryId : categoryId,
                ),
                costPrice: Value(row.costPrice ?? current?.costPrice ?? 0),
                salePrice: row.salePrice,
                wholesalePrice: Value(
                  row.wholesalePrice ?? current?.wholesalePrice,
                ),
                taxRate: Value(row.taxRate ?? current?.taxRate ?? 0),
                defaultDiscount: Value(
                  row.discount ?? current?.defaultDiscount ?? 0,
                ),
                unit: Value(row.unit ?? current?.unit ?? 'each'),
                imagePath: Value(current?.imagePath),
                isActive: Value(row.active ?? current?.isActive ?? true),
                trackInventory: Value(
                  row.trackStock ?? current?.trackInventory ?? true,
                ),
                createdAt: current?.createdAt ?? now,
                updatedAt: now,
              ),
            );
        final store =
            await (_database.select(_database.productStores)..where(
                  (s) =>
                      s.productId.equals(productId) & s.storeId.equals(storeId),
                ))
                .getSingleOrNull();
        final previous = store?.stockQty ?? 0;
        final next = row.stock ?? previous;
        await _database
            .into(_database.productStores)
            .insertOnConflictUpdate(
              ProductStoresCompanion.insert(
                productId: productId,
                storeId: storeId,
                stockQty: Value(next),
                reorderLevel: Value(
                  row.reorderLevel ?? store?.reorderLevel ?? 0,
                ),
                customSalePrice: Value(store?.customSalePrice),
                customDiscount: Value(store?.customDiscount),
                isAvailable: Value(store?.isAvailable ?? true),
                updatedAt: now,
              ),
            );
        if (next != previous) {
          PermissionGuard.require(session, Permissions.inventoryAdjust);
          await _database
              .into(_database.stockMovements)
              .insert(
                StockMovementsCompanion.insert(
                  id: _uuid.v4(),
                  storeId: storeId,
                  productId: productId,
                  type: store == null ? 'opening' : 'adjustment',
                  quantity: next - previous,
                  previousQty: previous,
                  newQty: next,
                  referenceType: 'import',
                  note: Value('CSV import (line ${row.line})'),
                  userId: session.user.id,
                  createdAt: now,
                ),
              );
          movements++;
        }
        if (row.existingId == null) {
          created++;
        } else {
          updated++;
        }
      }

      await _database
          .into(_database.auditLogs)
          .insert(
            AuditLogsCompanion.insert(
              id: _uuid.v4(),
              userId: Value(session.user.id),
              storeId: Value(session.store.id),
              action: 'products.imported',
              entityType: 'product',
              description:
                  'CSV import: $created created, $updated updated, '
                  '$categoriesCreated categories created.',
              newValueJson: Value(
                jsonEncode({
                  'created': created,
                  'updated': updated,
                  'categories': categoriesCreated,
                  'stockMovements': movements,
                }),
              ),
              createdAt: now,
            ),
          );
    });

    return ImportOutcome(
      created: created,
      updated: updated,
      skipped: plan.preview.count(ImportAction.skip),
      extra: [
        if (categoriesCreated > 0) '$categoriesCreated categories created',
        if (movements > 0) '$movements stock movements recorded',
      ],
    );
  }

  /// All products of the active store as CSV rows in template format.
  Future<List<List<Object?>>> export(AppSession session) async {
    PermissionGuard.require(session, Permissions.productsView);
    final rows = await _database
        .customSelect(
          '''
      SELECT p.sku, p.name, p.sale_price, p.barcode, p.short_name, p.cost_price,
             p.wholesale_price, p.tax_rate, p.default_discount, p.unit,
             p.track_inventory, p.is_active, p.category_id,
             ps.stock_qty, ps.reorder_level
      FROM products p
      LEFT JOIN product_stores ps ON ps.product_id = p.id AND ps.store_id = ?
      ORDER BY p.name COLLATE NOCASE
      ''',
          variables: [Variable.withString(session.store.id)],
        )
        .get();
    final categories = await _database.select(_database.categories).get();
    final byId = {for (final category in categories) category.id: category};
    String path(String? id) {
      final parts = <String>[];
      var current = id == null ? null : byId[id];
      final guard = <String>{};
      while (current != null && guard.add(current.id)) {
        parts.insert(0, current.name);
        current = current.parentId == null ? null : byId[current.parentId];
      }
      return parts.join(' > ');
    }

    return [
      columns,
      for (final row in rows)
        [
          row.read<String>('sku'),
          row.read<String>('name'),
          row.read<double>('sale_price'),
          row.readNullable<String>('barcode'),
          path(row.readNullable<String>('category_id')),
          row.readNullable<String>('short_name'),
          row.read<double>('cost_price'),
          row.readNullable<double>('wholesale_price'),
          row.read<double>('tax_rate'),
          row.read<double>('default_discount'),
          row.read<String>('unit'),
          row.readNullable<double>('stock_qty') ?? 0,
          row.readNullable<double>('reorder_level') ?? 0,
          row.read<bool>('track_inventory') ? 'yes' : 'no',
          row.read<bool>('is_active') ? 'yes' : 'no',
        ],
    ];
  }
}
