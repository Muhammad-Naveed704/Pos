import 'package:flutter_test/flutter_test.dart';
import 'package:storeflow_pos/core/money/money.dart';
import 'package:storeflow_pos/features/auth/domain/app_session.dart';
import 'package:storeflow_pos/features/auth/domain/permission_guard.dart';
import 'package:storeflow_pos/features/auth/domain/permissions.dart';
import 'package:storeflow_pos/features/products/data/product_repository.dart';
import 'package:storeflow_pos/features/purchases/data/purchase_service.dart';

import 'support/storeflow_fixture.dart';

void main() {
  late StoreFlowFixture fixture;
  late PurchaseService purchases;
  late AppSession owner;
  late String productId;

  setUp(() async {
    fixture = StoreFlowFixture();
    purchases = PurchaseService(fixture.database);
    owner = await fixture.initialize();
    productId = await ProductRepository(fixture.database).save(
      session: owner,
      input: const ProductInput(
        sku: 'SOAP',
        name: 'Soap',
        salePrice: 100,
        costPrice: 60,
        stockQty: 2,
      ),
    );
  });
  tearDown(() => fixture.close());

  Future<double> stock() async => (await (fixture.database.select(
    fixture.database.productStores,
  )..where((r) => r.productId.equals(productId))).getSingle()).stockQty;

  test('receiving stock adds quantity, movement, totals and cost', () async {
    final supplierId = await purchases.saveSupplier(
      owner,
      name: 'Acme Traders',
      phone: '0300',
    );
    final id = await purchases.receive(
      owner,
      supplierId: supplierId,
      supplierReference: 'INV-77',
      lines: [
        PurchaseLineInput(
          productId: productId,
          quantity: 10,
          unitCost: Money.fromMajor(55.5),
        ),
      ],
      discount: Money.fromMajor(5),
      tax: Money.fromMajor(10),
    );
    expect(await stock(), 12);
    final db = fixture.database;
    final purchase = await (db.select(
      db.purchases,
    )..where((p) => p.id.equals(id))).getSingle();
    expect(purchase.invoiceNumber, 'INV-77');
    expect(purchase.subtotal, 555);
    expect(purchase.total, 560);
    final product = await (db.select(
      db.products,
    )..where((p) => p.id.equals(productId))).getSingle();
    expect(product.costPrice, 55.5);
    final movement = await (db.select(
      db.stockMovements,
    )..where((m) => m.referenceId.equals(id))).getSingle();
    expect(movement.type, 'purchase');
    expect(movement.quantity, 10);

    final list = await purchases.watchPurchases(owner).first;
    expect(list.single.supplierName, 'Acme Traders');
    expect(list.single.itemCount, 1);
  });

  test('supplier returns reduce stock and cannot exceed it', () async {
    await expectLater(
      purchases.returnToSupplier(
        owner,
        lines: [
          PurchaseLineInput(
            productId: productId,
            quantity: 5,
            unitCost: Money.fromMajor(60),
          ),
        ],
      ),
      throwsA(isA<PurchaseException>()),
    );
    expect(await stock(), 2, reason: 'failed return rolled back');
    await purchases.returnToSupplier(
      owner,
      lines: [
        PurchaseLineInput(
          productId: productId,
          quantity: 1,
          unitCost: Money.fromMajor(60),
        ),
      ],
      reason: 'Damaged',
    );
    expect(await stock(), 1);
    final list = await purchases.watchPurchases(owner).first;
    expect(list.single.isReturn, isTrue);
  });

  test('validation and permissions', () async {
    await expectLater(
      purchases.receive(owner, lines: const []),
      throwsA(isA<PurchaseException>()),
    );
    final viewer = AppSession(
      user: owner.user,
      role: owner.role,
      store: owner.store,
      permissions: const {Permissions.purchasesView},
    );
    await expectLater(
      purchases.receive(
        viewer,
        lines: [
          PurchaseLineInput(
            productId: productId,
            quantity: 1,
            unitCost: Money.zero,
          ),
        ],
      ),
      throwsA(isA<PermissionDeniedException>()),
    );
    final totals = PurchaseService.totals([
      PurchaseLineInput(
        productId: productId,
        quantity: 2,
        unitCost: Money.fromMajor(10),
      ),
    ], discount: Money.fromMajor(50));
    expect(totals.total, Money.zero, reason: 'discount is clamped');
  });
}
