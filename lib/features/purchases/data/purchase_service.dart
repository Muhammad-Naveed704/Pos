import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/database_provider.dart';
import '../../../core/money/money.dart';
import '../../auth/domain/app_session.dart';
import '../../auth/domain/permission_guard.dart';
import '../../auth/domain/permissions.dart';

final purchaseServiceProvider = Provider<PurchaseService>(
  (ref) => PurchaseService(ref.watch(databaseProvider)),
);

class PurchaseException implements Exception {
  const PurchaseException(this.message);
  final String message;
  @override
  String toString() => message;
}

class PurchaseLineInput {
  const PurchaseLineInput({
    required this.productId,
    required this.quantity,
    required this.unitCost,
  });
  final String productId;
  final double quantity;
  final Money unitCost;

  Money get total => unitCost.multiply(quantity);
}

class PurchaseSummary {
  const PurchaseSummary({
    required this.purchase,
    required this.supplierName,
    required this.itemCount,
  });
  final Purchase purchase;
  final String? supplierName;
  final int itemCount;

  bool get isReturn => purchase.status == PurchaseService.statusReturn;
}

class PurchaseLineDetail {
  const PurchaseLineDetail(this.item, this.productName, this.sku, this.unit);
  final PurchaseItem item;
  final String productName;
  final String sku;
  final String unit;
}

class PurchaseTotals {
  const PurchaseTotals(this.subtotal, this.discount, this.tax, this.total);
  final Money subtotal;
  final Money discount;
  final Money tax;
  final Money total;
}

class PurchaseService {
  PurchaseService(this._database, {Uuid? uuid}) : _uuid = uuid ?? const Uuid();
  final AppDatabase _database;
  final Uuid _uuid;

  static const statusReceived = 'received';
  static const statusReturn = 'returned';

  static PurchaseTotals totals(
    List<PurchaseLineInput> lines, {
    Money discount = Money.zero,
    Money tax = Money.zero,
  }) {
    final subtotal = lines.fold(Money.zero, (sum, line) => sum + line.total);
    final appliedDiscount = discount.clamp(Money.zero, subtotal);
    final appliedTax = tax.max(Money.zero);
    return PurchaseTotals(
      subtotal,
      appliedDiscount,
      appliedTax,
      subtotal - appliedDiscount + appliedTax,
    );
  }

  // --- Suppliers -----------------------------------------------------------

  Stream<List<Supplier>> watchSuppliers(
    AppSession session, {
    String search = '',
    bool activeOnly = false,
  }) {
    PermissionGuard.require(session, Permissions.purchasesView);
    final term = search.trim();
    return (_database.select(_database.suppliers)
          ..where((s) {
            Expression<bool> condition = const Constant(true);
            if (activeOnly) condition = condition & s.isActive.equals(true);
            if (term.isNotEmpty) {
              condition =
                  condition &
                  (s.name.like('%$term%') | s.phone.like('%$term%'));
            }
            return condition;
          })
          ..orderBy([(s) => OrderingTerm.asc(s.name)]))
        .watch();
  }

  Future<String> saveSupplier(
    AppSession session, {
    String? id,
    required String name,
    String? phone,
    String? email,
    String address = '',
    bool isActive = true,
  }) async {
    PermissionGuard.require(session, Permissions.purchasesManage);
    if (name.trim().isEmpty) {
      throw const PurchaseException('Supplier name is required.');
    }
    final supplierId = id ?? _uuid.v4();
    final now = DateTime.now();
    final existing = id == null
        ? null
        : await (_database.select(
            _database.suppliers,
          )..where((s) => s.id.equals(id))).getSingleOrNull();
    String? clean(String? value) =>
        value == null || value.trim().isEmpty ? null : value.trim();
    await _database
        .into(_database.suppliers)
        .insertOnConflictUpdate(
          SuppliersCompanion.insert(
            id: supplierId,
            name: name.trim(),
            phone: Value(clean(phone)),
            email: Value(clean(email)),
            address: Value(address.trim()),
            isActive: Value(isActive),
            createdAt: existing?.createdAt ?? now,
            updatedAt: now,
          ),
        );
    return supplierId;
  }

  // --- Purchases -----------------------------------------------------------

  Stream<List<PurchaseSummary>> watchPurchases(
    AppSession session, {
    DateTime? from,
    DateTime? to,
    String? supplierId,
    String? status,
    int limit = 300,
  }) {
    PermissionGuard.require(session, Permissions.purchasesView);
    final where = <String>['p.store_id = ?'];
    final variables = <Variable>[Variable.withString(session.store.id)];
    if (from != null) {
      where.add('p.created_at >= ?');
      variables.add(Variable.withDateTime(from));
    }
    if (to != null) {
      where.add('p.created_at < ?');
      variables.add(Variable.withDateTime(to));
    }
    if (supplierId != null) {
      where.add('p.supplier_id = ?');
      variables.add(Variable.withString(supplierId));
    }
    if (status != null) {
      where.add('p.status = ?');
      variables.add(Variable.withString(status));
    }
    return _database
        .customSelect(
          '''
          SELECT p.*, s.name AS supplier_name,
                 (SELECT COUNT(*) FROM purchase_items i WHERE i.purchase_id = p.id) AS item_count
          FROM purchases p
          LEFT JOIN suppliers s ON s.id = p.supplier_id
          WHERE ${where.join(' AND ')}
          ORDER BY p.created_at DESC, p.rowid DESC
          LIMIT $limit
          ''',
          variables: variables,
          readsFrom: {
            _database.purchases,
            _database.suppliers,
            _database.purchaseItems,
          },
        )
        .watch()
        .map(
          (rows) => [
            for (final row in rows)
              PurchaseSummary(
                purchase: _database.purchases.map(row.data),
                supplierName: row.readNullable<String>('supplier_name'),
                itemCount: row.read<int>('item_count'),
              ),
          ],
        );
  }

  Future<List<PurchaseLineDetail>> lines(
    AppSession session,
    String purchaseId,
  ) async {
    PermissionGuard.require(session, Permissions.purchasesView);
    final items = _database.purchaseItems;
    final products = _database.products;
    final rows = await (_database.select(items).join([
      innerJoin(products, products.id.equalsExp(items.productId)),
    ])..where(items.purchaseId.equals(purchaseId))).get();
    return [
      for (final row in rows)
        PurchaseLineDetail(
          row.readTable(items),
          row.readTable(products).name,
          row.readTable(products).sku,
          row.readTable(products).unit,
        ),
    ];
  }

  String _documentNumber(String prefix, String storeCode, DateTime now) =>
      '$prefix-$storeCode-${DateFormat('yyMMdd').format(now)}-'
      '${_uuid.v4().substring(0, 4).toUpperCase()}';

  void _validate(List<PurchaseLineInput> lines) {
    if (lines.isEmpty) {
      throw const PurchaseException('Add at least one product.');
    }
    final ids = <String>{};
    for (final line in lines) {
      if (line.quantity <= 0 || line.quantity.isNaN) {
        throw const PurchaseException('Quantities must be greater than zero.');
      }
      if (line.unitCost.minorUnits < 0) {
        throw const PurchaseException('Costs cannot be negative.');
      }
      if (!ids.add(line.productId)) {
        throw const PurchaseException('Each product can appear only once.');
      }
    }
  }

  /// Receives stock from a supplier (goods received note).
  Future<String> receive(
    AppSession session, {
    String? supplierId,
    String supplierReference = '',
    required List<PurchaseLineInput> lines,
    Money discount = Money.zero,
    Money tax = Money.zero,
    bool updateCostPrice = true,
  }) async {
    PermissionGuard.require(session, Permissions.purchasesManage);
    _validate(lines);
    final sums = totals(lines, discount: discount, tax: tax);
    final purchaseId = _uuid.v4();
    await _database.transaction(() async {
      final now = DateTime.now();
      final number = supplierReference.trim().isNotEmpty
          ? supplierReference.trim()
          : _documentNumber('GRN', session.store.code, now);
      await _database
          .into(_database.purchases)
          .insert(
            PurchasesCompanion.insert(
              id: purchaseId,
              storeId: session.store.id,
              supplierId: Value(supplierId),
              invoiceNumber: number,
              subtotal: sums.subtotal.majorUnits,
              discount: Value(sums.discount.majorUnits),
              tax: Value(sums.tax.majorUnits),
              total: sums.total.majorUnits,
              status: statusReceived,
              createdAt: now,
              updatedAt: now,
            ),
          );
      for (final line in lines) {
        final product = await (_database.select(
          _database.products,
        )..where((p) => p.id.equals(line.productId))).getSingleOrNull();
        if (product == null) {
          throw const PurchaseException('A product no longer exists.');
        }
        await _database
            .into(_database.purchaseItems)
            .insert(
              PurchaseItemsCompanion.insert(
                id: _uuid.v4(),
                purchaseId: purchaseId,
                productId: line.productId,
                qty: line.quantity,
                costPrice: line.unitCost.majorUnits,
                lineTotal: line.total.majorUnits,
              ),
            );
        await _moveStock(
          session,
          product: product,
          delta: line.quantity,
          type: 'purchase',
          referenceId: purchaseId,
          note: 'Received $number',
          now: now,
          allowNegative: true,
        );
        if (updateCostPrice && line.unitCost.majorUnits != product.costPrice) {
          await (_database.update(
            _database.products,
          )..where((p) => p.id.equals(product.id))).write(
            ProductsCompanion(
              costPrice: Value(line.unitCost.majorUnits),
              updatedAt: Value(now),
            ),
          );
        }
      }
      await _audit(
        session,
        'purchases.received',
        purchaseId,
        'Received $number: ${lines.length} line(s), total ${sums.total}.',
      );
    });
    return purchaseId;
  }

  /// Returns stock to a supplier (debit note).
  Future<String> returnToSupplier(
    AppSession session, {
    String? supplierId,
    String reference = '',
    required List<PurchaseLineInput> lines,
    String reason = '',
  }) async {
    PermissionGuard.require(session, Permissions.purchasesManage);
    _validate(lines);
    final sums = totals(lines);
    final returnId = _uuid.v4();
    await _database.transaction(() async {
      final now = DateTime.now();
      final allowNegative = await _allowNegative();
      final number = reference.trim().isNotEmpty
          ? reference.trim()
          : _documentNumber('RTN', session.store.code, now);
      await _database
          .into(_database.purchases)
          .insert(
            PurchasesCompanion.insert(
              id: returnId,
              storeId: session.store.id,
              supplierId: Value(supplierId),
              invoiceNumber: number,
              subtotal: sums.subtotal.majorUnits,
              total: sums.total.majorUnits,
              status: statusReturn,
              createdAt: now,
              updatedAt: now,
            ),
          );
      for (final line in lines) {
        final product = await (_database.select(
          _database.products,
        )..where((p) => p.id.equals(line.productId))).getSingle();
        await _database
            .into(_database.purchaseItems)
            .insert(
              PurchaseItemsCompanion.insert(
                id: _uuid.v4(),
                purchaseId: returnId,
                productId: line.productId,
                qty: line.quantity,
                costPrice: line.unitCost.majorUnits,
                lineTotal: line.total.majorUnits,
              ),
            );
        await _moveStock(
          session,
          product: product,
          delta: -line.quantity,
          type: 'purchase_return',
          referenceId: returnId,
          note: [
            'Returned $number',
            if (reason.trim().isNotEmpty) reason.trim(),
          ].join(' · '),
          now: now,
          allowNegative: allowNegative,
        );
      }
      await _audit(
        session,
        'purchases.returned',
        returnId,
        'Supplier return $number: ${lines.length} line(s), total ${sums.total}.',
        json: jsonEncode({'reason': reason}),
      );
    });
    return returnId;
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

  Future<void> _moveStock(
    AppSession session, {
    required Product product,
    required double delta,
    required String type,
    required String referenceId,
    required String note,
    required DateTime now,
    required bool allowNegative,
  }) async {
    final storeId = session.store.id;
    final current =
        await (_database.select(_database.productStores)..where(
              (r) => r.productId.equals(product.id) & r.storeId.equals(storeId),
            ))
            .getSingleOrNull();
    final previous = current?.stockQty ?? 0;
    final next = previous + delta;
    if (next < 0 && !allowNegative && product.trackInventory) {
      throw PurchaseException(
        'Not enough ${product.name} in stock to return (${previous.toStringAsFixed(2)} available).',
      );
    }
    if (current == null) {
      await _database
          .into(_database.productStores)
          .insert(
            ProductStoresCompanion.insert(
              productId: product.id,
              storeId: storeId,
              stockQty: Value(next),
              updatedAt: now,
            ),
          );
    } else {
      await (_database.update(_database.productStores)..where(
            (r) => r.productId.equals(product.id) & r.storeId.equals(storeId),
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
            productId: product.id,
            type: type,
            quantity: delta,
            previousQty: previous,
            newQty: next,
            referenceType: 'purchase',
            referenceId: Value(referenceId),
            note: Value(note),
            userId: session.user.id,
            createdAt: now,
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
          entityType: 'purchase',
          entityId: Value(entityId),
          description: description,
          newValueJson: Value(json),
          createdAt: DateTime.now(),
        ),
      );
}
