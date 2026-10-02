import 'package:flutter_test/flutter_test.dart';
import 'package:storeflow_pos/core/money/money.dart';
import 'package:storeflow_pos/features/auth/domain/app_session.dart';
import 'package:storeflow_pos/features/auth/domain/permission_guard.dart';
import 'package:storeflow_pos/features/auth/domain/permissions.dart';
import 'package:storeflow_pos/features/cashbook/data/cashbook_service.dart';
import 'package:storeflow_pos/features/customers/data/customer_repository.dart';
import 'package:storeflow_pos/features/pos/data/checkout_service.dart';
import 'package:storeflow_pos/features/pos/domain/pos_cart.dart';
import 'package:storeflow_pos/features/products/data/product_repository.dart';
import 'package:storeflow_pos/features/returns/data/refund_service.dart';

import 'support/storeflow_fixture.dart';

void main() {
  late StoreFlowFixture fixture;
  late RefundService refunds;
  late AppSession owner;
  late String teaId;
  late String mugId;

  setUp(() async {
    fixture = StoreFlowFixture();
    refunds = RefundService(fixture.database);
    owner = await fixture.initialize();
    final products = ProductRepository(fixture.database);
    teaId = await products.save(
      session: owner,
      input: const ProductInput(
        sku: 'TEA',
        name: 'Tea',
        salePrice: 100,
        costPrice: 60,
        stockQty: 20,
      ),
    );
    mugId = await products.save(
      session: owner,
      input: const ProductInput(
        sku: 'MUG',
        name: 'Mug',
        salePrice: 300,
        costPrice: 200,
        stockQty: 5,
      ),
    );
  });
  tearDown(() => fixture.close());

  Future<double> stock(String productId) async =>
      (await (fixture.database.select(
        fixture.database.productStores,
      )..where((r) => r.productId.equals(productId))).getSingle()).stockQty;

  /// 4 × tea (400) + 1 × mug (300) = 700, 10% sale discount → 630 cash.
  Future<String> sale({String? customerId, double tendered = 630}) async {
    final products = ProductRepository(fixture.database);
    final tea = (await products.byId(
      storeId: owner.store.id,
      productId: teaId,
    ))!;
    final mug = (await products.byId(
      storeId: owner.store.id,
      productId: mugId,
    ))!;
    final result = await CheckoutService(fixture.database).checkout(
      session: owner,
      cart: PosCart(
        lines: [
          CartLine(catalogProduct: tea, quantityMilli: 4000),
          CartLine(catalogProduct: mug),
        ],
        saleDiscountPercent: 10,
        customerId: customerId,
      ),
      payments: [
        PaymentInput(method: 'cash', amount: Money.fromMajor(tendered)),
      ],
    );
    return result.saleId;
  }

  test('partial then full refund spreads the sale discount exactly', () async {
    final customers = CustomerRepository(fixture.database);
    final customerId = await customers.save(session: owner, name: 'Ali');
    final saleId = await sale(customerId: customerId);
    expect((await customers.byId(customerId))!.loyaltyPoints, 630);

    var state = await refunds.load(owner, saleId);
    final teaLine = state.lines.firstWhere((l) => l.item.productId == teaId);
    final mugLine = state.lines.firstWhere((l) => l.item.productId == mugId);

    // 1 tea of 4: 100 × 0.9 = 90, not restocked (damaged).
    final first = await refunds.refund(
      owner,
      saleId: saleId,
      lines: [
        RefundLineInput(
          saleItemId: teaLine.item.id,
          quantity: 1,
          restock: false,
        ),
      ],
      method: 'cash',
      reason: 'Damaged / defective',
    );
    expect(first.amount, Money.fromMajor(90));
    expect(first.number, endsWith('-R1'));
    expect(await stock(teaId), 16, reason: 'damaged item not restocked');

    state = await refunds.load(owner, saleId);
    expect(state.sale.saleStatus, SaleStatus.partiallyRefunded);
    expect(state.remaining, Money.fromMajor(540));
    await expectLater(
      refunds.refund(
        owner,
        saleId: saleId,
        lines: [RefundLineInput(saleItemId: teaLine.item.id, quantity: 4)],
        method: 'cash',
        reason: 'Other',
      ),
      throwsA(isA<RefundException>()),
      reason: 'only 3 teas remain returnable',
    );

    // Everything left: settles the exact remaining balance.
    final second = await refunds.refund(
      owner,
      saleId: saleId,
      lines: [
        RefundLineInput(saleItemId: teaLine.item.id, quantity: 3),
        RefundLineInput(saleItemId: mugLine.item.id, quantity: 1),
      ],
      method: 'card',
      reason: 'Customer changed mind',
    );
    expect(second.amount, Money.fromMajor(540));
    expect(await stock(teaId), 19);
    expect(await stock(mugId), 5);
    state = await refunds.load(owner, saleId);
    expect(state.sale.saleStatus, SaleStatus.refunded);
    expect(state.remaining, Money.zero);
    expect(state.canRefund, isFalse);
    expect(state.refunds, hasLength(2));
    expect((await customers.byId(customerId))!.loyaltyPoints, 0);

    // Only the cash refund leaves the drawer.
    final cash = await (fixture.database.select(
      fixture.database.cashTransactions,
    )..where((t) => t.type.equals('cash_refund'))).get();
    expect(cash.single.amount, 90);
  });

  test('cash refunds cannot exceed the open drawer', () async {
    final saleId = await sale();
    final cashbook = CashbookService(fixture.database);
    await cashbook.openSession(owner, Money.fromMajor(50));
    final state = await refunds.load(owner, saleId);
    final mug = state.lines.firstWhere((l) => l.item.productId == mugId);
    await expectLater(
      refunds.refund(
        owner,
        saleId: saleId,
        lines: [RefundLineInput(saleItemId: mug.item.id, quantity: 1)],
        method: 'cash',
        reason: 'Other',
      ),
      throwsA(isA<RefundException>()),
    );
    expect(await stock(mugId), 4, reason: 'failed refund rolled back');
    // Card refunds are not limited by the drawer.
    await refunds.refund(
      owner,
      saleId: saleId,
      lines: [RefundLineInput(saleItemId: mug.item.id, quantity: 1)],
      method: 'card',
      reason: 'Other',
    );
    expect(await stock(mugId), 5);
  });

  test('void restores stock and cash and is excluded afterwards', () async {
    final saleId = await sale(tendered: 1000);
    expect(await stock(teaId), 16);
    final result = await refunds.voidSale(
      owner,
      saleId: saleId,
      reason: 'Entered by mistake',
    );
    expect(result.number, endsWith('-V'));
    expect(await stock(teaId), 20);
    expect(await stock(mugId), 5);
    final state = await refunds.load(owner, saleId);
    expect(state.sale.saleStatus, SaleStatus.voided);
    expect(state.canVoid, isFalse);
    expect(state.canRefund, isFalse);
    final cash = await (fixture.database.select(
      fixture.database.cashTransactions,
    )..where((t) => t.type.equals('cash_refund'))).getSingle();
    expect(cash.amount, 630, reason: 'net cash: 1000 tendered − 370 change');
    await expectLater(
      refunds.voidSale(owner, saleId: saleId, reason: 'again'),
      throwsA(isA<RefundException>()),
    );
  });

  test('older sales and refunded sales cannot be voided', () async {
    final saleId = await sale();
    await fixture.database.customStatement(
      'UPDATE sales SET created_at = created_at - 172800 WHERE id = ?',
      [saleId],
    );
    await expectLater(
      refunds.voidSale(owner, saleId: saleId, reason: 'late'),
      throwsA(isA<RefundException>()),
    );
    expect((await refunds.load(owner, saleId)).canRefund, isTrue);
  });

  test('permissions and invoice lookup', () async {
    final saleId = await sale();
    final invoice = (await refunds.load(owner, saleId)).sale.invoiceNumber;
    expect(await refunds.findByInvoice(owner, invoice.toLowerCase()), saleId);
    expect(await refunds.findByInvoice(owner, 'NOPE'), isNull);

    final cashier = AppSession(
      user: owner.user,
      role: owner.role,
      store: owner.store,
      permissions: Permissions.cashier,
    );
    final line = (await refunds.load(owner, saleId)).lines.first;
    await expectLater(
      refunds.refund(
        cashier,
        saleId: saleId,
        lines: [RefundLineInput(saleItemId: line.item.id, quantity: 1)],
        method: 'cash',
        reason: 'x',
      ),
      throwsA(isA<PermissionDeniedException>()),
    );
    await expectLater(
      refunds.voidSale(cashier, saleId: saleId, reason: 'x'),
      throwsA(isA<PermissionDeniedException>()),
    );
  });
}
