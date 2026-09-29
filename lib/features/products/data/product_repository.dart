import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/database_provider.dart';
import '../../auth/domain/app_session.dart';
import '../../auth/domain/permission_guard.dart';
import '../../auth/domain/permissions.dart';

final productRepositoryProvider = Provider<ProductRepository>(
  (ref) => ProductRepository(ref.watch(databaseProvider)),
);

class CatalogProduct {
  const CatalogProduct({
    required this.product,
    required this.store,
    this.category,
  });

  final Product product;
  final ProductStore store;
  final Category? category;

  double get effectivePrice => store.customSalePrice ?? product.salePrice;
  double get effectiveDiscount =>
      store.customDiscount ?? product.defaultDiscount;
}

class ProductInput {
  const ProductInput({
    required this.sku,
    required this.name,
    required this.salePrice,
    this.barcode,
    this.shortName,
    this.categoryId,
    this.costPrice = 0,
    this.wholesalePrice,
    this.taxRate = 0,
    this.defaultDiscount = 0,
    this.unit = 'each',
    this.imagePath,
    this.isActive = true,
    this.trackInventory = true,
    this.stockQty = 0,
    this.reorderLevel = 0,
    this.customSalePrice,
    this.customDiscount,
    this.isAvailable = true,
  });

  final String sku;
  final String? barcode;
  final String name;
  final String? shortName;
  final String? categoryId;
  final double costPrice;
  final double salePrice;
  final double? wholesalePrice;
  final double taxRate;
  final double defaultDiscount;
  final String unit;
  final String? imagePath;
  final bool isActive;
  final bool trackInventory;
  final double stockQty;
  final double reorderLevel;
  final double? customSalePrice;
  final double? customDiscount;
  final bool isAvailable;
}

class ProductRepository {
  ProductRepository(this._database, {Uuid? uuid})
    : _uuid = uuid ?? const Uuid();
  final AppDatabase _database;
  final Uuid _uuid;

  Selectable<CatalogProduct> _catalogQuery({
    required String storeId,
    String search = '',
    String? categoryId,
    bool activeOnly = true,
    bool availableOnly = true,
    int limit = 60,
    int offset = 0,
  }) {
    final products = _database.products;
    final productStores = _database.productStores;
    final categories = _database.categories;
    final query = _database.select(products).join([
      innerJoin(
        productStores,
        productStores.productId.equalsExp(products.id) &
            productStores.storeId.equals(storeId),
      ),
      leftOuterJoin(categories, categories.id.equalsExp(products.categoryId)),
    ]);
    final term = search.trim();
    Expression<bool> condition = const Constant(true);
    if (activeOnly) condition = condition & products.isActive.equals(true);
    if (availableOnly) {
      condition = condition & productStores.isAvailable.equals(true);
    }
    if (categoryId != null) {
      condition = condition & products.categoryId.equals(categoryId);
    }
    if (term.isNotEmpty) {
      final pattern = '%$term%';
      condition =
          condition &
          (products.name.like(pattern) |
              products.sku.like(pattern) |
              products.barcode.like(pattern));
    }
    query
      ..where(condition)
      ..orderBy([OrderingTerm.asc(products.name)])
      ..limit(limit, offset: offset);
    return query.map(
      (row) => CatalogProduct(
        product: row.readTable(products),
        store: row.readTable(productStores),
        category: row.readTableOrNull(categories),
      ),
    );
  }

  Stream<List<CatalogProduct>> watchPosProducts({
    required String storeId,
    String search = '',
    String? categoryId,
    int limit = 60,
  }) => _catalogQuery(
    storeId: storeId,
    search: search,
    categoryId: categoryId,
    limit: limit,
  ).watch();

  Future<List<CatalogProduct>> page({
    required String storeId,
    String search = '',
    bool activeOnly = false,
    int page = 0,
    int pageSize = 50,
  }) => _catalogQuery(
    storeId: storeId,
    search: search,
    activeOnly: activeOnly,
    availableOnly: false,
    limit: pageSize,
    offset: page * pageSize,
  ).get();

  Future<CatalogProduct?> exactLookup({
    required String storeId,
    required String code,
  }) async {
    final products = _database.products;
    final productStores = _database.productStores;
    final query =
        _database.select(products).join([
            innerJoin(
              productStores,
              productStores.productId.equalsExp(products.id) &
                  productStores.storeId.equals(storeId),
            ),
          ])
          ..where(
            products.isActive.equals(true) &
                productStores.isAvailable.equals(true) &
                (products.barcode.equals(code) | products.sku.equals(code)),
          )
          ..limit(1);
    final row = await query.getSingleOrNull();
    return row == null
        ? null
        : CatalogProduct(
            product: row.readTable(products),
            store: row.readTable(productStores),
          );
  }

  Future<CatalogProduct?> byId({
    required String storeId,
    required String productId,
  }) async {
    final products = _database.products;
    final productStores = _database.productStores;
    final query =
        _database.select(products).join([
            innerJoin(
              productStores,
              productStores.productId.equalsExp(products.id) &
                  productStores.storeId.equals(storeId),
            ),
          ])
          ..where(products.id.equals(productId))
          ..limit(1);
    final row = await query.getSingleOrNull();
    return row == null
        ? null
        : CatalogProduct(
            product: row.readTable(products),
            store: row.readTable(productStores),
          );
  }

  Future<String> save({
    required AppSession session,
    String? id,
    required ProductInput input,
  }) async {
    PermissionGuard.require(
      session,
      id == null ? Permissions.productsCreate : Permissions.productsEdit,
    );
    final productId = id ?? _uuid.v4();
    final now = DateTime.now();
    await _database.transaction(() async {
      final existingProduct = await (_database.select(
        _database.products,
      )..where((row) => row.id.equals(productId))).getSingleOrNull();
      final existingStore =
          await (_database.select(_database.productStores)..where(
                (row) =>
                    row.productId.equals(productId) &
                    row.storeId.equals(session.store.id),
              ))
              .getSingleOrNull();
      await _database
          .into(_database.products)
          .insertOnConflictUpdate(
            ProductsCompanion.insert(
              id: productId,
              sku: input.sku.trim().toUpperCase(),
              barcode: Value(_emptyToNull(input.barcode)),
              name: input.name.trim(),
              shortName: Value(_emptyToNull(input.shortName)),
              categoryId: Value(input.categoryId),
              costPrice: Value(input.costPrice),
              salePrice: input.salePrice,
              wholesalePrice: Value(input.wholesalePrice),
              taxRate: Value(input.taxRate),
              defaultDiscount: Value(input.defaultDiscount),
              unit: Value(input.unit.trim()),
              imagePath: Value(_emptyToNull(input.imagePath)),
              isActive: Value(input.isActive),
              trackInventory: Value(input.trackInventory),
              createdAt: existingProduct?.createdAt ?? now,
              updatedAt: now,
            ),
          );
      await _database
          .into(_database.productStores)
          .insertOnConflictUpdate(
            ProductStoresCompanion.insert(
              productId: productId,
              storeId: session.store.id,
              stockQty: Value(input.stockQty),
              reorderLevel: Value(input.reorderLevel),
              customSalePrice: Value(input.customSalePrice),
              customDiscount: Value(input.customDiscount),
              isAvailable: Value(input.isAvailable),
              updatedAt: now,
            ),
          );
      final previous = existingStore?.stockQty ?? 0;
      if (input.stockQty != previous) {
        PermissionGuard.require(session, Permissions.inventoryAdjust);
        await _database
            .into(_database.stockMovements)
            .insert(
              StockMovementsCompanion.insert(
                id: _uuid.v4(),
                storeId: session.store.id,
                productId: productId,
                type: existingStore == null ? 'opening' : 'adjustment',
                quantity: input.stockQty - previous,
                previousQty: previous,
                newQty: input.stockQty,
                referenceType: 'product',
                referenceId: Value(productId),
                note: const Value('Product editor stock update'),
                userId: session.user.id,
                createdAt: now,
              ),
            );
      }
    });
    return productId;
  }

  Future<String> duplicate({
    required AppSession session,
    required CatalogProduct source,
    required String newSku,
  }) => save(
    session: session,
    input: ProductInput(
      sku: newSku,
      name: '${source.product.name} Copy',
      shortName: source.product.shortName,
      categoryId: source.product.categoryId,
      costPrice: source.product.costPrice,
      salePrice: source.product.salePrice,
      wholesalePrice: source.product.wholesalePrice,
      taxRate: source.product.taxRate,
      defaultDiscount: source.product.defaultDiscount,
      unit: source.product.unit,
      imagePath: source.product.imagePath,
      trackInventory: source.product.trackInventory,
      stockQty: 0,
      reorderLevel: source.store.reorderLevel,
      customSalePrice: source.store.customSalePrice,
      customDiscount: source.store.customDiscount,
      isAvailable: source.store.isAvailable,
    ),
  );

  Future<void> setActive(
    AppSession session,
    String productId,
    bool active,
  ) async {
    PermissionGuard.require(session, Permissions.productsDeactivate);
    await (_database.update(
      _database.products,
    )..where((row) => row.id.equals(productId))).write(
      ProductsCompanion(
        isActive: Value(active),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  static String? _emptyToNull(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }
}
