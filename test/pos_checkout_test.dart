import 'package:flutter_test/flutter_test.dart';
import 'package:storeflow_pos/core/money/money.dart';
import 'package:storeflow_pos/features/pos/data/checkout_service.dart';
import 'package:storeflow_pos/features/pos/domain/pos_cart.dart';
import 'package:storeflow_pos/features/products/data/product_repository.dart';

import 'support/storeflow_fixture.dart';

void main() {
  late StoreFlowFixture fixture;

  setUp(() => fixture = StoreFlowFixture());
  tearDown(() => fixture.close());

  test(
    'store price, product discount, sale discount and tax use minor units',
    () async {
      final session = await fixture.initialize();
      final products = ProductRepository(fixture.database);
      final id = await products.save(
        session: session,
        input: const ProductInput(
          sku: 'SKU-1',
          name: 'Product',
          salePrice: 100,
          customSalePrice: 120,
          defaultDiscount: 10,
          taxRate: 15,
          stockQty: 10,
        ),
      );
      final product = await products.byId(
        storeId: session.store.id,
        productId: id,
      );
      final cart = PosCart(
        lines: [CartLine(catalogProduct: product!, quantityMilli: 2000)],
        saleDiscountPercent: 5,
      );
      final totals = cart.totals(TaxMode.exclusive);

      expect(product.effectivePrice, 120);
      expect(totals.subtotal, const Money.fromMinor(24000));
      expect(totals.lineDiscount, const Money.fromMinor(2400));
      expect(totals.tax, const Money.fromMinor(3240));
      expect(totals.saleDiscount, const Money.fromMinor(1080));
      expect(totals.grandTotal, const Money.fromMinor(23760));
    },
  );

  test(
    'checkout commits sale, payment, stock, movement, audit and sequence',
    () async {
      final session = await fixture.initialize();
      final products = ProductRepository(fixture.database);
      final id = await products.save(
        session: session,
        input: const ProductInput(
          sku: 'SALE-1',
          name: 'Sellable',
          salePrice: 50,
          stockQty: 5,
        ),
      );
      final product = (await products.byId(
        storeId: session.store.id,
        productId: id,
      ))!;
      final result = await CheckoutService(fixture.database).checkout(
        session: session,
        cart: PosCart(
          lines: [CartLine(catalogProduct: product, quantityMilli: 2000)],
        ),
        payments: const [
          PaymentInput(method: 'cash', amount: Money.fromMinor(12000)),
        ],
      );

      expect(result.total, const Money.fromMinor(10000));
      expect(result.change, const Money.fromMinor(2000));
      expect(
        await fixture.database.select(fixture.database.sales).get(),
        hasLength(1),
      );
      expect(
        await fixture.database.select(fixture.database.payments).get(),
        hasLength(1),
      );
      expect(
        (await fixture.database
                .select(fixture.database.productStores)
                .getSingle())
            .stockQty,
        3,
      );
      expect(
        (await fixture.database.select(fixture.database.stockMovements).get())
            .where((row) => row.type == 'sale'),
        hasLength(1),
      );
      expect(
        (await fixture.database.select(fixture.database.auditLogs).get()).where(
          (row) => row.action == 'sale.created',
        ),
        hasLength(1),
      );
      expect(
        (await fixture.database
                .select(fixture.database.invoiceSequences)
                .getSingle())
            .lastValue,
        1,
      );
    },
  );

  test('POS lookup excludes inactive and unavailable products', () async {
    final session = await fixture.initialize();
    final products = ProductRepository(fixture.database);
    await products.save(
      session: session,
      input: const ProductInput(
        sku: 'VISIBLE',
        name: 'Visible product',
        salePrice: 10,
      ),
    );
    await products.save(
      session: session,
      input: const ProductInput(
        sku: 'INACTIVE',
        name: 'Inactive product',
        salePrice: 10,
        isActive: false,
      ),
    );
    await products.save(
      session: session,
      input: const ProductInput(
        sku: 'UNAVAILABLE',
        name: 'Unavailable product',
        salePrice: 10,
        isAvailable: false,
      ),
    );

    final visible = await products
        .watchPosProducts(storeId: session.store.id)
        .first;
    expect(visible.map((item) => item.product.sku), ['VISIBLE']);
    expect(
      await products.exactLookup(storeId: session.store.id, code: 'INACTIVE'),
      isNull,
    );
  });

  test(
    'split payment records each tender and calculates cash change',
    () async {
      final session = await fixture.initialize();
      final products = ProductRepository(fixture.database);
      final id = await products.save(
        session: session,
        input: const ProductInput(
          sku: 'SPLIT',
          name: 'Split tender product',
          salePrice: 100,
          stockQty: 2,
        ),
      );
      final product = (await products.byId(
        storeId: session.store.id,
        productId: id,
      ))!;
      final result = await CheckoutService(fixture.database).checkout(
        session: session,
        cart: PosCart(lines: [CartLine(catalogProduct: product)]),
        payments: const [
          PaymentInput(method: 'card', amount: Money.fromMinor(4000)),
          PaymentInput(method: 'cash', amount: Money.fromMinor(7000)),
        ],
      );

      expect(result.total, const Money.fromMinor(10000));
      expect(result.change, const Money.fromMinor(1000));
      final payments = await fixture.database
          .select(fixture.database.payments)
          .get();
      expect(payments, hasLength(2));
      expect(
        payments.map((payment) => payment.method),
        containsAll(['card', 'cash']),
      );
      final cash = await fixture.database
          .select(fixture.database.cashTransactions)
          .getSingle();
      expect(cash.amount, 60);
    },
  );

  test('forced checkout failure rolls back every write', () async {
    final session = await fixture.initialize();
    final products = ProductRepository(fixture.database);
    final id = await products.save(
      session: session,
      input: const ProductInput(
        sku: 'ROLLBACK',
        name: 'Rollback',
        salePrice: 25,
        stockQty: 4,
      ),
    );
    final product = (await products.byId(
      storeId: session.store.id,
      productId: id,
    ))!;
    final service = CheckoutService(
      fixture.database,
      transactionProbe: () async => throw StateError('forced failure'),
    );

    await expectLater(
      service.checkout(
        session: session,
        cart: PosCart(lines: [CartLine(catalogProduct: product)]),
        payments: const [
          PaymentInput(method: 'card', amount: Money.fromMinor(2500)),
        ],
      ),
      throwsStateError,
    );
    expect(
      await fixture.database.select(fixture.database.sales).get(),
      isEmpty,
    );
    expect(
      await fixture.database.select(fixture.database.payments).get(),
      isEmpty,
    );
    expect(
      (await fixture.database
              .select(fixture.database.productStores)
              .getSingle())
          .stockQty,
      4,
    );
    expect(
      (await fixture.database
              .select(fixture.database.invoiceSequences)
              .getSingle())
          .lastValue,
      0,
    );
  });
}
