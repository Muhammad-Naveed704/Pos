import 'package:flutter/material.dart' show DateTimeRange;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:storeflow_pos/core/database/database_provider.dart';
import 'package:storeflow_pos/core/money/money.dart';
import 'package:storeflow_pos/core/theme/theme_controller.dart';
import 'package:storeflow_pos/features/auth/application/session_controller.dart';
import 'package:storeflow_pos/features/auth/domain/app_session.dart';
import 'package:storeflow_pos/features/auth/domain/permission_guard.dart';
import 'package:storeflow_pos/features/auth/domain/permissions.dart';
import 'package:storeflow_pos/features/dashboard/data/dashboard_metrics.dart';
import 'package:storeflow_pos/features/pos/data/checkout_service.dart';
import 'package:storeflow_pos/features/pos/domain/pos_cart.dart';
import 'package:storeflow_pos/features/products/data/product_repository.dart';
import 'package:storeflow_pos/features/reports/data/reports_service.dart';
import 'package:storeflow_pos/features/returns/data/refund_service.dart';

import 'support/storeflow_fixture.dart';

void main() {
  late StoreFlowFixture fixture;
  late AppSession owner;

  setUp(() async {
    fixture = StoreFlowFixture();
    owner = await fixture.initialize();
  });
  tearDown(() => fixture.close());

  /// Sells 2 × item at 500 (cost 300) for 1000 cash.
  Future<void> sell() async {
    final products = ProductRepository(fixture.database);
    final existing = await products.exactLookup(
      storeId: owner.store.id,
      code: 'LAMP',
    );
    final id =
        existing?.product.id ??
        await products.save(
          session: owner,
          input: const ProductInput(
            sku: 'LAMP',
            name: 'Lamp',
            salePrice: 500,
            costPrice: 300,
            stockQty: 10,
          ),
        );
    final product = (await products.byId(
      storeId: owner.store.id,
      productId: id,
    ))!;
    await CheckoutService(fixture.database).checkout(
      session: owner,
      cart: PosCart(
        lines: [CartLine(catalogProduct: product, quantityMilli: 2000)],
      ),
      payments: const [
        PaymentInput(method: 'cash', amount: Money.fromMinor(100000)),
      ],
    );
  }

  DateTimeRange today() {
    final now = DateTime.now();
    final day = DateTime(now.year, now.month, now.day);
    return DateTimeRange(start: day, end: day);
  }

  test('dashboard counts today’s sales (unix timestamp dates)', () async {
    await sell();
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(fixture.database),
        sharedPreferencesProvider.overrideWithValue(preferences),
      ],
    );
    addTearDown(container.dispose);
    await container
        .read(sessionControllerProvider.notifier)
        .login('owner', 'test-password');
    final metrics = await container.read(dashboardMetricsProvider.future);
    expect(metrics.sales, 1000);
    expect(metrics.invoices, 1);
    expect(metrics.cashCollected, 1000);
    expect(metrics.hourly.reduce((a, b) => a + b), 1000);
    expect(metrics.week.last.$2, 1000);
    expect(metrics.topProducts.single.name, 'Lamp');
    expect(metrics.paymentMix['cash'], 1000);
  });

  test('sales, product profit and payment reports', () async {
    await sell();
    final reports = ReportsService(fixture.database);

    final summary = await reports.run(owner, ReportKind.summary, today());
    double kpi(String label) =>
        summary.kpis.firstWhere((k) => k.label == label).value;
    expect(kpi('Net sales'), 1000);
    expect(kpi('Gross profit'), 400);
    expect(kpi('Margin'), 40);

    final daily = await reports.run(owner, ReportKind.daily, today());
    expect(daily.rows, hasLength(1));
    expect(daily.rows.single[5], 1000);

    final products = await reports.run(owner, ReportKind.products, today());
    final lamp = products.rows.single;
    expect(lamp[0], 'Lamp');
    expect(lamp[2], 2);
    expect(lamp[6], 600, reason: 'cost uses the snapshot at sale time');
    expect(lamp[7], 400);

    // Changing the product cost later does not rewrite past profit.
    await fixture.database.customStatement(
      "UPDATE products SET cost_price = 450 WHERE sku = 'LAMP'",
    );
    final again = await reports.run(owner, ReportKind.products, today());
    expect(again.rows.single[7], 400);

    final payments = await reports.run(owner, ReportKind.payments, today());
    expect(payments.rows.single[0], 'CASH');
    expect(payments.rows.single[2], 1000);

    final stock = await reports.run(owner, ReportKind.stock, today());
    expect(stock.rows.single[3], 8);

    final yesterday = DateTime.now().subtract(const Duration(days: 1));
    final empty = await reports.run(
      owner,
      ReportKind.summary,
      DateTimeRange(start: yesterday, end: yesterday),
    );
    expect(empty.kpis.first.value, 0);
  });

  test('reports require the matching permission', () async {
    final cashier = AppSession(
      user: owner.user,
      role: owner.role,
      store: owner.store,
      permissions: const {Permissions.reportsView, Permissions.reportsSales},
    );
    final reports = ReportsService(fixture.database);
    await reports.run(cashier, ReportKind.summary, today());
    await expectLater(
      reports.run(cashier, ReportKind.payments, today()),
      throwsA(isA<PermissionDeniedException>()),
    );
    final summary = await reports.run(cashier, ReportKind.summary, today());
    expect(
      summary.kpis.any((k) => k.label == 'Gross profit'),
      isFalse,
      reason: 'profit is hidden without reports.profit',
    );
  });

  test('refunds reduce sales, profit and cash; voids drop out', () async {
    await sell();
    final refunds = RefundService(fixture.database);
    final sale = await fixture.database
        .select(fixture.database.sales)
        .getSingle();
    final state = await refunds.load(owner, sale.id);
    // Return 1 of 2 lamps (500, cost 300) to stock, in cash.
    await refunds.refund(
      owner,
      saleId: sale.id,
      lines: [
        RefundLineInput(saleItemId: state.lines.single.item.id, quantity: 1),
      ],
      method: 'cash',
      reason: 'Other',
    );
    final reports = ReportsService(fixture.database);
    final summary = await reports.run(owner, ReportKind.summary, today());
    double kpi(String label) =>
        summary.kpis.firstWhere((k) => k.label == label).value;
    expect(kpi('Net sales'), 500);
    expect(kpi('Refunds'), 500);
    expect(kpi('Gross profit'), 200);

    final daily = await reports.run(owner, ReportKind.daily, today());
    expect(daily.rows.single[3], 500, reason: 'refunds column');
    expect(daily.rows.single[5], 500, reason: 'net after refunds');

    final products = await reports.run(owner, ReportKind.products, today());
    final lamp = products.rows.single;
    expect(lamp[2], 1, reason: 'net quantity');
    expect(lamp[3], 1, reason: 'returned quantity');
    expect(lamp[5], 500);
    expect(lamp[7], 200);

    final payments = await reports.run(owner, ReportKind.payments, today());
    expect(payments.kpis.first.value, 500, reason: 'net cash after refund');
    expect(payments.rows.last[2], -500);

    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(fixture.database),
        sharedPreferencesProvider.overrideWithValue(
          await SharedPreferences.getInstance(),
        ),
      ],
    );
    addTearDown(container.dispose);
    await container
        .read(sessionControllerProvider.notifier)
        .login('owner', 'test-password');
    final metrics = await container.read(dashboardMetricsProvider.future);
    expect(metrics.sales, 500);
    expect(metrics.cashCollected, 500);

    // A second sale that is voided disappears from the reports.
    await sell();
    final second = (await fixture.database.select(fixture.database.sales).get())
        .firstWhere((s) => s.id != sale.id);
    await refunds.voidSale(
      owner,
      saleId: second.id,
      reason: 'Entered by mistake',
    );
    final after = await reports.run(owner, ReportKind.summary, today());
    expect(after.kpis.first.value, 500);
  });
}
