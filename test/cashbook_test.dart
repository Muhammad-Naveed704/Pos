import 'package:flutter_test/flutter_test.dart';
import 'package:storeflow_pos/core/money/money.dart';
import 'package:storeflow_pos/features/auth/domain/app_session.dart';
import 'package:storeflow_pos/features/auth/domain/permission_guard.dart';
import 'package:storeflow_pos/features/auth/domain/permissions.dart';
import 'package:storeflow_pos/features/cashbook/data/cashbook_service.dart';
import 'package:storeflow_pos/features/pos/data/checkout_service.dart';
import 'package:storeflow_pos/features/pos/domain/pos_cart.dart';
import 'package:storeflow_pos/features/products/data/product_repository.dart';

import 'support/storeflow_fixture.dart';

void main() {
  late StoreFlowFixture fixture;
  late CashbookService cashbook;
  late AppSession owner;

  setUp(() async {
    fixture = StoreFlowFixture();
    cashbook = CashbookService(fixture.database);
    owner = await fixture.initialize();
  });
  tearDown(() => fixture.close());

  Future<void> sell(double total, double tendered) async {
    final products = ProductRepository(fixture.database);
    final id = await products.save(
      session: owner,
      input: ProductInput(
        sku: 'P-$total-$tendered',
        name: 'Item',
        salePrice: total,
        stockQty: 5,
      ),
    );
    final product = (await products.byId(
      storeId: owner.store.id,
      productId: id,
    ))!;
    await CheckoutService(fixture.database).checkout(
      session: owner,
      cart: PosCart(lines: [CartLine(catalogProduct: product)]),
      payments: [
        PaymentInput(method: 'cash', amount: Money.fromMajor(tendered)),
      ],
    );
  }

  test(
    'session lifecycle: open, sales, pay-in/out, close with difference',
    () async {
      await cashbook.openSession(owner, Money.fromMajor(1000));
      await expectLater(
        cashbook.openSession(owner, Money.zero),
        throwsA(isA<CashbookException>()),
      );

      await sell(250, 300); // 50 change → 250 net cash into the session
      await cashbook.record(
        owner,
        type: CashType.payIn,
        amount: Money.fromMajor(200),
        category: 'Change float top-up',
      );
      await cashbook.record(
        owner,
        type: CashType.payOut,
        amount: Money.fromMajor(100),
        category: 'Expenses',
        description: 'Tea',
      );
      await expectLater(
        cashbook.record(
          owner,
          type: CashType.payOut,
          amount: Money.fromMajor(99999),
          category: 'Expenses',
        ),
        throwsA(isA<CashbookException>()),
        reason: 'cannot pay out more than the drawer holds',
      );

      final current = (await cashbook.watchCurrent(owner).first)!;
      expect(current.cashSales, Money.fromMajor(250));
      expect(current.payIns, Money.fromMajor(200));
      expect(current.payOuts, Money.fromMajor(100));
      expect(current.expected, Money.fromMajor(1350));

      final closed = await cashbook.closeSession(
        owner,
        counted: Money.fromMajor(1340),
        denominations: const {'1000': 1, '100': 3, '10': 4},
      );
      expect(closed.isOpen, isFalse);
      expect(closed.difference, Money.fromMajor(-10));
      expect(await cashbook.watchCurrent(owner).first, isNull);

      // Sales after closing are not attached to the closed session.
      await sell(40, 40);
      final history = await cashbook.watchSessions(owner).first;
      expect(history.single.cashSales, Money.fromMajor(250));
    },
  );

  test('entries need an open session and the right permission', () async {
    await expectLater(
      cashbook.record(
        owner,
        type: CashType.payIn,
        amount: Money.fromMajor(10),
        category: 'Other',
      ),
      throwsA(isA<CashbookException>()),
    );
    final viewer = AppSession(
      user: owner.user,
      role: owner.role,
      store: owner.store,
      permissions: const {Permissions.posView},
    );
    await expectLater(
      cashbook.openSession(viewer, Money.zero),
      throwsA(isA<PermissionDeniedException>()),
    );
  });
}
