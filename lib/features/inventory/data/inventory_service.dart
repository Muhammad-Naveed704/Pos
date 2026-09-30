import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/database_provider.dart';
import '../../auth/domain/app_session.dart';
import '../../auth/domain/permission_guard.dart';
import '../../auth/domain/permissions.dart';

final inventoryServiceProvider = Provider<InventoryService>(
  (ref) => InventoryService(ref.watch(databaseProvider)),
);

class InventoryException implements Exception {
  const InventoryException(this.message);
  final String message;
  @override
  String toString() => message;
}

enum StockFilter { all, low, out, negative }

class StockRow {
  const StockRow({
    required this.productId,
    required this.sku,
    required this.name,
    required this.unit,
    required this.category,
    required this.stock,
    required this.reorderLevel,
    required this.costPrice,
    required this.salePrice,
    required this.isActive,
  });
  final String productId;
  final String sku;
  final String name;
  final String unit;
  final String? category;
  final double stock;
  final double reorderLevel;
  final double costPrice;
  final double salePrice;
  final bool isActive;

  bool get isOut => stock <= 0;
  bool get isLow => stock > 0 && stock <= reorderLevel;
}

class StockSummary {
  const StockSummary({
    required this.products,
    required this.units,
    required this.costValue,
    required this.retailValue,
    required this.low,
    required this.out,
  });
  final int products;
  final double units;
  final double costValue;
  final double retailValue;
  final int low;
  final int out;
}

class MovementRow {
  const MovementRow({
    required this.movement,
    required this.productName,
    required this.sku,
    required this.userName,
  });
  final StockMovement movement;
  final String productName;
  final String sku;
  final String userName;
}

enum AdjustMode { set, add, remove }

/// Reasons offered for manual adjustments.
const adjustmentReasons = [
  'Stock count correction',
  'Damaged / expired',
  'Theft / loss',
  'Found stock',
  'Internal use',
  'Returned by customer',
  'Other',
];

class InventoryService {
  InventoryService(this._database, {Uuid? uuid}) : _uuid = uuid ?? const Uuid();
  final AppDatabase _database;
  final Uuid _uuid;

  static const _stockSelect = '''
    SELECT p.id, p.sku, p.name, p.unit, p.cost_price, p.sale_price, p.is_active,
           c.name AS category, ps.stock_qty, ps.reorder_level
    FROM product_stores ps
    JOIN products p ON p.id = ps.product_id
    LEFT JOIN categories c ON c.id = p.category_id
    WHERE ps.store_id = ?1 AND p.track_inventory = 1
  ''';

  String _filterSql(StockFilter filter) => switch (filter) {
    StockFilter.all => '',
    StockFilter.low =>
      ' AND ps.stock_qty > 0 AND ps.stock_qty <= ps.reorder_level',
    StockFilter.out => ' AND ps.stock_qty <= 0',
    StockFilter.negative => ' AND ps.stock_qty < 0',
  };

  Stream<List<StockRow>> watchStock(
    AppSession session, {
    String search = '',
    StockFilter filter = StockFilter.all,
    int limit = 200,
  }) {
    PermissionGuard.require(session, Permissions.inventoryView);
    final term = search.trim();
    final searchSql = term.isEmpty
        ? ''
        : ' AND (p.name LIKE ?2 OR p.sku LIKE ?2 OR p.barcode LIKE ?2)';
    return _database
        .customSelect(
          '$_stockSelect${_filterSql(filter)}$searchSql '
          'ORDER BY (ps.stock_qty <= ps.reorder_level) DESC, p.name COLLATE NOCASE LIMIT $limit',
          variables: [
            Variable.withString(session.store.id),
            if (term.isNotEmpty) Variable.withString('%$term%'),
          ],
          readsFrom: {
            _database.products,
            _database.productStores,
            _database.categories,
          },
        )
        .watch()
        .map(
          (rows) => [
            for (final row in rows)
              StockRow(
                productId: row.read<String>('id'),
                sku: row.read<String>('sku'),
                name: row.read<String>('name'),
                unit: row.read<String>('unit'),
                category: row.readNullable<String>('category'),
                stock: row.read<double>('stock_qty'),
                reorderLevel: row.read<double>('reorder_level'),
                costPrice: row.read<double>('cost_price'),
                salePrice: row.read<double>('sale_price'),
                isActive: row.read<bool>('is_active'),
              ),
          ],
        );
  }

  Stream<StockSummary> watchSummary(AppSession session) {
    PermissionGuard.require(session, Permissions.inventoryView);
    return _database
        .customSelect(
          '''
          SELECT COUNT(*) AS products,
                 COALESCE(SUM(CASE WHEN ps.stock_qty > 0 THEN ps.stock_qty ELSE 0 END), 0.0) AS units,
                 COALESCE(SUM(CASE WHEN ps.stock_qty > 0 THEN ps.stock_qty * p.cost_price ELSE 0 END), 0.0) AS cost_value,
                 COALESCE(SUM(CASE WHEN ps.stock_qty > 0 THEN ps.stock_qty * COALESCE(ps.custom_sale_price, p.sale_price) ELSE 0 END), 0.0) AS retail_value,
                 COALESCE(SUM(CASE WHEN ps.stock_qty > 0 AND ps.stock_qty <= ps.reorder_level THEN 1 ELSE 0 END), 0) AS low,
                 COALESCE(SUM(CASE WHEN ps.stock_qty <= 0 THEN 1 ELSE 0 END), 0) AS out_count
          FROM product_stores ps
          JOIN products p ON p.id = ps.product_id
          WHERE ps.store_id = ? AND p.track_inventory = 1 AND p.is_active = 1
          ''',
          variables: [Variable.withString(session.store.id)],
          readsFrom: {_database.products, _database.productStores},
        )
        .watchSingle()
        .map(
          (row) => StockSummary(
            products: row.read<int>('products'),
            units: row.read<double>('units'),
            costValue: session.can(Permissions.inventoryViewCost)
                ? row.read<double>('cost_value')
                : 0,
            retailValue: row.read<double>('retail_value'),
            low: row.read<int>('low'),
            out: row.read<int>('out_count'),
          ),
        );
  }

  Stream<List<MovementRow>> watchMovements(
    AppSession session, {
    String? productId,
    String? type,
    DateTime? from,
    DateTime? to,
    int limit = 300,
  }) {
    PermissionGuard.require(session, Permissions.inventoryView);
    final movements = _database.stockMovements;
    final products = _database.products;
    final users = _database.users;
    final query = _database.select(movements).join([
      innerJoin(products, products.id.equalsExp(movements.productId)),
      innerJoin(users, users.id.equalsExp(movements.userId)),
    ]);
    Expression<bool> condition = movements.storeId.equals(session.store.id);
    if (productId != null) {
      condition = condition & movements.productId.equals(productId);
    }
    if (type != null) condition = condition & movements.type.equals(type);
    if (from != null) {
      condition = condition & movements.createdAt.isBiggerOrEqualValue(from);
    }
    if (to != null) {
      condition = condition & movements.createdAt.isSmallerThanValue(to);
    }
    query
      ..where(condition)
      // created_at has one-second precision; rowid keeps insertion order.
      ..orderBy([
        OrderingTerm.desc(movements.createdAt),
        OrderingTerm.desc(const CustomExpression<int>('stock_movements.rowid')),
      ])
      ..limit(limit);
    return query.watch().map(
      (rows) => [
        for (final row in rows)
          MovementRow(
            movement: row.readTable(movements),
            productName: row.readTable(products).name,
            sku: row.readTable(products).sku,
            userName: row.readTable(users).displayName,
          ),
      ],
    );
  }

  Future<ProductStore?> _storeRow(String productId, String storeId) =>
      (_database.select(_database.productStores)..where(
            (row) =>
                row.productId.equals(productId) & row.storeId.equals(storeId),
          ))
          .getSingleOrNull();

  Future<void> _setStock({
    required AppSession session,
    required String storeId,
    required String productId,
    required ProductStore? current,
    required double next,
    required String type,
    required String referenceType,
    String? referenceId,
    required String note,
    required DateTime now,
  }) async {
    final previous = current?.stockQty ?? 0;
    if (current == null) {
      await _database
          .into(_database.productStores)
          .insert(
            ProductStoresCompanion.insert(
              productId: productId,
              storeId: storeId,
              stockQty: Value(next),
              updatedAt: now,
            ),
          );
    } else {
      await (_database.update(_database.productStores)..where(
            (row) =>
                row.productId.equals(productId) & row.storeId.equals(storeId),
          ))
          .write(
            ProductStoresCompanion(
              stockQty: Value(next),
              updatedAt: Value(now),
            ),
          );
    }
    await _database
        .into(_database.stockMovements)
        .insert(
          StockMovementsCompanion.insert(
            id: _uuid.v4(),
            storeId: storeId,
            productId: productId,
            type: type,
            quantity: next - previous,
            previousQty: previous,
            newQty: next,
            referenceType: referenceType,
            referenceId: Value(referenceId),
            note: Value(note),
            userId: session.user.id,
            createdAt: now,
          ),
        );
  }

  Future<bool> _allowNegative() async {
    final row =
        await (_database.select(_database.appSettings)..where(
              (r) =>
                  r.key.equals('inventory.allowNegative') & r.storeId.isNull(),
            ))
            .getSingleOrNull();
    return row?.value == 'true';
  }

  /// Manual adjustment of one product in the active store.
  Future<double> adjust(
    AppSession session, {
    required String productId,
    required AdjustMode mode,
    required double quantity,
    required String reason,
    String note = '',
  }) async {
    PermissionGuard.require(session, Permissions.inventoryAdjust);
    if (quantity < 0 || quantity.isNaN) {
      throw const InventoryException('Quantity cannot be negative.');
    }
    if (reason.trim().isEmpty) {
      throw const InventoryException('Choose a reason for the adjustment.');
    }
    late double next;
    await _database.transaction(() async {
      final now = DateTime.now();
      final current = await _storeRow(productId, session.store.id);
      final previous = current?.stockQty ?? 0;
      next = switch (mode) {
        AdjustMode.set => quantity,
        AdjustMode.add => previous + quantity,
        AdjustMode.remove => previous - quantity,
      };
      if (next < 0 && !await _allowNegative()) {
        throw InventoryException(
          'Only ${_fmt(previous)} in stock; negative stock is not allowed.',
        );
      }
      if (next == previous) return;
      await _setStock(
        session: session,
        storeId: session.store.id,
        productId: productId,
        current: current,
        next: next,
        type: 'adjustment',
        referenceType: 'adjustment',
        note: [
          reason.trim(),
          if (note.trim().isNotEmpty) note.trim(),
        ].join(' · '),
        now: now,
      );
      await _audit(
        session,
        'inventory.adjusted',
        productId,
        'Stock ${_fmt(previous)} → ${_fmt(next)} ($reason).',
      );
    });
    return next;
  }

  /// Applies a physical stock count for many products in one transaction.
  /// Returns the number of products whose stock changed.
  Future<int> applyCount(
    AppSession session,
    Map<String, double> counted, {
    String note = '',
  }) async {
    PermissionGuard.require(session, Permissions.inventoryAdjust);
    if (counted.values.any((value) => value < 0 || value.isNaN)) {
      throw const InventoryException('Counted quantities cannot be negative.');
    }
    var changed = 0;
    await _database.transaction(() async {
      final now = DateTime.now();
      final countId = _uuid.v4();
      for (final entry in counted.entries) {
        final current = await _storeRow(entry.key, session.store.id);
        if ((current?.stockQty ?? 0) == entry.value) continue;
        await _setStock(
          session: session,
          storeId: session.store.id,
          productId: entry.key,
          current: current,
          next: entry.value,
          type: 'count',
          referenceType: 'stock_count',
          referenceId: countId,
          note: note.trim().isEmpty
              ? 'Stock count'
              : 'Stock count · ${note.trim()}',
          now: now,
        );
        changed++;
      }
      await _audit(
        session,
        'inventory.counted',
        countId,
        'Stock count of ${counted.length} product(s); $changed changed.',
      );
    });
    return changed;
  }

  /// Moves stock from the active store to [toStoreId].
  Future<String> transfer(
    AppSession session, {
    required String toStoreId,
    required Map<String, double> quantities,
    String note = '',
  }) async {
    PermissionGuard.require(session, Permissions.inventoryTransfer);
    if (toStoreId == session.store.id) {
      throw const InventoryException('Choose a different destination store.');
    }
    final lines = {
      for (final entry in quantities.entries)
        if (entry.value > 0) entry.key: entry.value,
    };
    if (lines.isEmpty) {
      throw const InventoryException(
        'Add at least one product with a quantity.',
      );
    }
    final transferId = _uuid.v4();
    await _database.transaction(() async {
      final destination = await (_database.select(
        _database.stores,
      )..where((s) => s.id.equals(toStoreId))).getSingleOrNull();
      if (destination == null || !destination.isActive) {
        throw const InventoryException('The destination store is not active.');
      }
      final allowNegative = await _allowNegative();
      final now = DateTime.now();
      final label = note.trim().isEmpty ? '' : ' · ${note.trim()}';
      for (final entry in lines.entries) {
        final source = await _storeRow(entry.key, session.store.id);
        final available = source?.stockQty ?? 0;
        if (available - entry.value < 0 && !allowNegative) {
          final product = await (_database.select(
            _database.products,
          )..where((p) => p.id.equals(entry.key))).getSingle();
          throw InventoryException(
            'Not enough ${product.name}: ${_fmt(available)} available, ${_fmt(entry.value)} requested.',
          );
        }
        await _setStock(
          session: session,
          storeId: session.store.id,
          productId: entry.key,
          current: source,
          next: available - entry.value,
          type: 'transfer_out',
          referenceType: 'transfer',
          referenceId: transferId,
          note: 'To ${destination.name}$label',
          now: now,
        );
        final target = await _storeRow(entry.key, toStoreId);
        await _setStock(
          session: session,
          storeId: toStoreId,
          productId: entry.key,
          current: target,
          next: (target?.stockQty ?? 0) + entry.value,
          type: 'transfer_in',
          referenceType: 'transfer',
          referenceId: transferId,
          note: 'From ${session.store.name}$label',
          now: now,
        );
      }
      await _audit(
        session,
        'inventory.transferred',
        transferId,
        'Transferred ${lines.length} product(s) to ${destination.name}.',
        json: jsonEncode(lines),
      );
    });
    return transferId;
  }

  Future<void> setReorderLevel(
    AppSession session,
    String productId,
    double level,
  ) async {
    PermissionGuard.require(session, Permissions.inventoryAdjust);
    if (level < 0) {
      throw const InventoryException('Reorder level cannot be negative.');
    }
    await (_database.update(_database.productStores)..where(
          (row) =>
              row.productId.equals(productId) &
              row.storeId.equals(session.store.id),
        ))
        .write(
          ProductStoresCompanion(
            reorderLevel: Value(level),
            updatedAt: Value(DateTime.now()),
          ),
        );
  }

  Future<void> _audit(
    AppSession session,
    String action,
    String entityId,
    String description, {
    String? json,
  }) => _database
      .into(_database.auditLogs)
      .insert(
        AuditLogsCompanion.insert(
          id: _uuid.v4(),
          userId: Value(session.user.id),
          storeId: Value(session.store.id),
          action: action,
          entityType: 'inventory',
          entityId: Value(entityId),
          description: description,
          newValueJson: Value(json),
          createdAt: DateTime.now(),
        ),
      );

  static String _fmt(double value) => value == value.roundToDouble()
      ? value.toStringAsFixed(0)
      : value.toStringAsFixed(3).replaceFirst(RegExp(r'0+$'), '');
}
