import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:storeflow_pos/features/auth/domain/app_session.dart';
import 'package:storeflow_pos/features/auth/domain/permission_guard.dart';
import 'package:storeflow_pos/features/auth/domain/permissions.dart';
import 'package:storeflow_pos/features/inventory/data/inventory_service.dart';
import 'package:storeflow_pos/features/products/data/product_repository.dart';
import 'package:storeflow_pos/features/stores/data/store_repository.dart';

import 'support/storeflow_fixture.dart';

void main() {
  late StoreFlowFixture fixture;
  late InventoryService inventory;
  late AppSession owner;
  late String productId;

  setUp(() async {
    fixture = StoreFlowFixture();
    inventory = InventoryService(fixture.database);
    owner = await fixture.initialize();
    productId = await ProductRepository(fixture.database).save(
      session: owner,
      input: const ProductInput(
        sku: 'RICE',
        name: 'Rice',
        salePrice: 200,
        costPrice: 150,
        stockQty: 10,
        reorderLevel: 3,
      ),
    );
  });
  tearDown(() => fixture.close());

  Future<double> stockIn(String storeId) async {
    final row =
        await (fixture.database.select(fixture.database.productStores)..where(
              (r) => r.productId.equals(productId) & r.storeId.equals(storeId),
            ))
            .getSingleOrNull();
    return row?.stockQty ?? 0;
  }

  test(
    'adjustments record movements and respect negative stock rule',
    () async {
      expect(
        await inventory.adjust(
          owner,
          productId: productId,
          mode: AdjustMode.add,
          quantity: 2.5,
          reason: 'Found stock',
        ),
        12.5,
      );
      expect(
        await inventory.adjust(
          owner,
          productId: productId,
          mode: AdjustMode.remove,
          quantity: 0.5,
          reason: 'Damaged / expired',
        ),
        12,
      );
      await expectLater(
        inventory.adjust(
          owner,
          productId: productId,
          mode: AdjustMode.remove,
          quantity: 20,
          reason: 'Theft / loss',
        ),
        throwsA(isA<InventoryException>()),
      );
      expect(await stockIn(owner.store.id), 12);

      final movements = await inventory.watchMovements(owner).first;
      final adjustments = movements.where(
        (m) => m.movement.type == 'adjustment',
      );
      expect(adjustments, hasLength(2));
      expect(adjustments.first.movement.note, contains('Damaged'));

      final viewer = AppSession(
        user: owner.user,
        role: owner.role,
        store: owner.store,
        permissions: const {Permissions.inventoryView},
      );
      await expectLater(
        inventory.adjust(
          viewer,
          productId: productId,
          mode: AdjustMode.set,
          quantity: 1,
          reason: 'Other',
        ),
        throwsA(isA<PermissionDeniedException>()),
      );

      final summary = await inventory.watchSummary(owner).first;
      expect(summary.products, 1);
      expect(summary.costValue, 12 * 150);
    },
  );

  test('stock count only records changed products', () async {
    final second = await ProductRepository(fixture.database).save(
      session: owner,
      input: const ProductInput(
        sku: 'OIL',
        name: 'Oil',
        salePrice: 500,
        stockQty: 4,
      ),
    );
    final changed = await inventory.applyCount(owner, {
      productId: 8,
      second: 4,
    }, note: 'Monthly');
    expect(changed, 1);
    expect(await stockIn(owner.store.id), 8);
    final counts = (await inventory.watchMovements(owner).first)
        .where((m) => m.movement.type == 'count')
        .toList();
    expect(counts, hasLength(1));
    expect(counts.single.movement.quantity, -2);
  });

  test('transfer moves stock between stores atomically', () async {
    final branchId = await StoreRepository(fixture.database)
        .create(session: owner, name: 'Branch', code: 'BR');
    await expectLater(
      inventory.transfer(
        owner,
        toStoreId: branchId,
        quantities: {productId: 50},
      ),
      throwsA(isA<InventoryException>()),
    );
    expect(await stockIn(owner.store.id), 10);
    expect(await stockIn(branchId), 0);

    final transferId = await inventory.transfer(
      owner,
      toStoreId: branchId,
      quantities: {productId: 4},
      note: 'Weekly',
    );
    expect(await stockIn(owner.store.id), 6);
    expect(await stockIn(branchId), 4);
    final movements = await fixture.database
        .select(fixture.database.stockMovements)
        .get();
    final pair = movements.where((m) => m.referenceId == transferId).toList();
    expect(
      pair.map((m) => m.type),
      containsAll(['transfer_out', 'transfer_in']),
    );
    expect(pair.map((m) => m.storeId).toSet(), {owner.store.id, branchId});

    await expectLater(
      inventory.transfer(
        owner,
        toStoreId: owner.store.id,
        quantities: {productId: 1},
      ),
      throwsA(isA<InventoryException>()),
    );
  });
}
