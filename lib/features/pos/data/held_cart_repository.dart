import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/database_provider.dart';
import '../../../core/money/money.dart';
import '../../auth/domain/app_session.dart';
import '../../auth/domain/permission_guard.dart';
import '../../auth/domain/permissions.dart';
import '../../products/data/product_repository.dart';
import '../domain/pos_cart.dart';

final heldCartRepositoryProvider = Provider<HeldCartRepository>(
  (ref) => HeldCartRepository(
    ref.watch(databaseProvider),
    ref.watch(productRepositoryProvider),
  ),
);

class HeldCartRepository {
  HeldCartRepository(this._database, this._products, {Uuid? uuid})
    : _uuid = uuid ?? const Uuid();
  final AppDatabase _database;
  final ProductRepository _products;
  final Uuid _uuid;

  Stream<List<HeldCart>> watch(AppSession session) {
    PermissionGuard.require(session, Permissions.posView);
    return (_database.select(_database.heldCarts)
          ..where(
            (row) =>
                row.storeId.equals(session.store.id) &
                row.userId.equals(session.user.id),
          )
          ..orderBy([(row) => OrderingTerm.desc(row.updatedAt)]))
        .watch();
  }

  Future<String> save(
    AppSession session,
    PosCart cart, {
    String? id,
    String label = 'Held sale',
  }) async {
    PermissionGuard.require(session, Permissions.posCreateSale);
    if (cart.lines.isEmpty) throw ArgumentError('Cannot hold an empty cart.');
    final cartId = id ?? _uuid.v4();
    final now = DateTime.now();
    final payload = jsonEncode({
      'customerId': cart.customerId,
      'notes': cart.notes,
      'saleDiscountMinor': cart.saleDiscount.minorUnits,
      'saleDiscountPercent': cart.saleDiscountPercent,
      'lines': cart.lines
          .map(
            (line) => {
              'productId': line.productId,
              'quantityMilli': line.quantityMilli,
              'overridePriceMinor': line.overrideUnitPrice?.minorUnits,
              'manualDiscountMinor': line.manualDiscount.minorUnits,
              'manualDiscountPercent': line.manualDiscountPercent,
            },
          )
          .toList(),
    });
    await _database
        .into(_database.heldCarts)
        .insertOnConflictUpdate(
          HeldCartsCompanion.insert(
            id: cartId,
            storeId: session.store.id,
            userId: session.user.id,
            customerId: Value(cart.customerId),
            label: label.trim().isEmpty ? 'Held sale' : label.trim(),
            cartJson: payload,
            createdAt: now,
            updatedAt: now,
          ),
        );
    return cartId;
  }

  Future<PosCart> restore(AppSession session, HeldCart held) async {
    PermissionGuard.require(session, Permissions.posCreateSale);
    if (held.storeId != session.store.id || held.userId != session.user.id) {
      throw StateError('This held cart does not belong to the active session.');
    }
    final json = jsonDecode(held.cartJson) as Map<String, dynamic>;
    final lines = <CartLine>[];
    for (final raw in (json['lines'] as List<dynamic>)) {
      final data = raw as Map<String, dynamic>;
      final product = await _products.byId(
        storeId: session.store.id,
        productId: data['productId'] as String,
      );
      if (product == null ||
          !product.product.isActive ||
          !product.store.isAvailable) {
        continue;
      }
      final override = data['overridePriceMinor'] as int?;
      lines.add(
        CartLine(
          catalogProduct: product,
          quantityMilli: data['quantityMilli'] as int,
          overrideUnitPrice: override == null
              ? null
              : Money.fromMinor(override),
          manualDiscount: Money.fromMinor(data['manualDiscountMinor'] as int),
          manualDiscountPercent: (data['manualDiscountPercent'] as num)
              .toDouble(),
        ),
      );
    }
    return PosCart(
      lines: lines,
      customerId: json['customerId'] as String?,
      notes: json['notes'] as String? ?? '',
      saleDiscount: Money.fromMinor(json['saleDiscountMinor'] as int),
      saleDiscountPercent: (json['saleDiscountPercent'] as num).toDouble(),
    );
  }

  Future<void> remove(AppSession session, String id) async {
    PermissionGuard.require(session, Permissions.posCreateSale);
    await (_database.delete(_database.heldCarts)..where(
          (row) =>
              row.id.equals(id) &
              row.storeId.equals(session.store.id) &
              row.userId.equals(session.user.id),
        ))
        .go();
  }
}
