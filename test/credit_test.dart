import 'package:drift/drift.dart' show Variable;
import 'package:flutter_test/flutter_test.dart';
import 'package:storeflow_pos/core/money/money.dart';
import 'package:storeflow_pos/features/auth/domain/app_session.dart';
import 'package:storeflow_pos/features/auth/domain/permission_guard.dart';
import 'package:storeflow_pos/features/auth/domain/permissions.dart';
import 'package:storeflow_pos/features/cashbook/data/cashbook_service.dart';
import 'package:storeflow_pos/features/credit/data/credit_service.dart';
import 'package:storeflow_pos/features/credit/domain/credit.dart';
import 'package:storeflow_pos/features/customers/data/customer_repository.dart';
import 'package:storeflow_pos/features/pos/data/checkout_service.dart';
import 'package:storeflow_pos/features/pos/domain/pos_cart.dart';
import 'package:storeflow_pos/features/products/data/product_repository.dart';
import 'package:storeflow_pos/features/reports/data/reports_service.dart';
import 'package:storeflow_pos/features/returns/data/refund_service.dart';
import 'package:flutter/material.dart' show DateTimeRange;

import 'support/storeflow_fixture.dart';

void main() {
  late StoreFlowFixture fixture;
  late AppSession owner;
  late CreditService credit;
  late CustomerRepository customers;
  late String teaId;
  late String customerId;

  setUp(() async {
    fixture = StoreFlowFixture();
    owner = await fixture.initialize();
    credit = CreditService(fixture.database);
    customers = CustomerRepository(fixture.database);
    teaId = await ProductRepository(fixture.database).save(
      session: owner,
      input: const ProductInput(
        sku: 'TEA',
        name: 'Tea',
        salePrice: 100,
        costPrice: 60,
        stockQty: 50,
      ),
    );
    customerId = await customers.save(
      session: owner,
      name: 'Bilal',
      phone: '0300',
      creditLimit: 2000,
    );
  });
  tearDown(() => fixture.close());

  AppSession withPermissions(Set<String> permissions) => AppSession(
    user: owner.user,
    role: owner.role,
    store: owner.store,
    permissions: permissions,
  );

  Future<PosCart> cart(int quantity, {String? customer}) async {
    final tea = (await ProductRepository(fixture.database)
        .byId(storeId: owner.store.id, productId: teaId))!;
    return PosCart(
      lines: [CartLine(catalogProduct: tea, quantityMilli: quantity * 1000)],
      customerId: customer,
    );
  }

  /// Tea is 100 + 0% tax, so the total is quantity × 100.
  Future<CheckoutResult> sell(
    int quantity, {
    double paid = 0,
    String method = 'cash',
    String? customer,
    AppSession? session,
    DateTime? dueDate,
    bool override = false,
    Future<void> Function()? probe,
  }) async =>
      CheckoutService(fixture.database, transactionProbe: probe).checkout(
        session: session ?? owner,
        cart: await cart(quantity, customer: customer ?? customerId),
        payments: [
          if (paid > 0)
            PaymentInput(method: method, amount: Money.fromMajor(paid)),
        ],
        dueDate: dueDate,
        overrideCreditLimit: override,
      );

  Future<double> stock() async => (await (fixture.database.select(
    fixture.database.productStores,
  )..where((r) => r.productId.equals(teaId))).getSingle()).stockQty;

  Future<int> count(String table) async =>
      (await fixture.database
              .customSelect('SELECT COUNT(*) AS n FROM $table')
              .getSingle())
          .read<int>('n');

  test('zero-payment credit sale puts the whole invoice on account', () async {
    final result = await sell(5, dueDate: DateTime.now());
    expect(result.outstanding, Money.fromMajor(500));
    expect(result.isCredit, isTrue);
    final sale = await (fixture.database.select(
      fixture.database.sales,
    )..where((s) => s.id.equals(result.saleId))).getSingle();
    expect(sale.paymentStatus, PaymentStatus.credit);
    expect(sale.creditAmount, 500);
    // Money safety: invoice total = paid now + outstanding.
    expect(
      Money.fromMajor(sale.grandTotal),
      Money.fromMajor(sale.paidAmount - sale.changeAmount) +
          Money.fromMajor(sale.creditAmount),
    );
    expect(await stock(), 45);
    expect(await count('payments'), 0);
    final balance = await credit.balance(owner, customerId);
    expect(balance.outstanding, Money.fromMajor(500));
    expect(balance.availableCredit, Money.fromMajor(1500));
    expect(balance.openInvoices, 1);
    final ledger = await credit.ledger(owner, customerId);
    expect(ledger.rows.map((r) => r.entry.type), [LedgerType.sale]);
    expect(ledger.closing, Money.fromMajor(500));
    final audit = await fixture.database
        .customSelect(
          "SELECT COUNT(*) AS n FROM audit_logs WHERE action = 'credit.sale'",
        )
        .getSingle();
    expect(audit.read<int>('n'), 1);
  });

  test(
    'partial payment leaves the rest outstanding and cash in drawer',
    () async {
      final cashbook = CashbookService(fixture.database);
      await cashbook.openSession(owner, Money.zero);
      final result = await sell(5, paid: 200);
      expect(result.outstanding, Money.fromMajor(300));
      final sale = await (fixture.database.select(
        fixture.database.sales,
      )..where((s) => s.id.equals(result.saleId))).getSingle();
      expect(sale.paymentStatus, PaymentStatus.partial);
      expect(sale.changeAmount, 0);
      final ledger = await credit.ledger(owner, customerId);
      expect(ledger.rows.map((r) => r.entry.type), [
        LedgerType.sale,
        LedgerType.salePayment,
      ]);
      expect(ledger.rows.last.balance, Money.fromMajor(300));
      final current = await cashbook.watchCurrent(owner).first;
      expect(current!.cashSales, Money.fromMajor(200));
    },
  );

  test(
    'a fully paid sale is unchanged and nets to zero on the account',
    () async {
      final result = await sell(3, paid: 500);
      expect(result.change, Money.fromMajor(200));
      expect(result.outstanding, Money.zero);
      final sale = await (fixture.database.select(
        fixture.database.sales,
      )..where((s) => s.id.equals(result.saleId))).getSingle();
      expect(sale.paymentStatus, PaymentStatus.paid);
      expect(sale.creditAmount, 0);
      expect(sale.dueDate, isNull);
      final balance = await credit.balance(owner, customerId);
      expect(balance.outstanding, Money.zero);
      expect(balance.totalPurchases, Money.fromMajor(300));
      expect(balance.totalPaid, Money.fromMajor(300));
    },
  );

  test('credit needs a customer and the credit permission', () async {
    final tea = await cart(2);
    await expectLater(
      CheckoutService(fixture.database)
          .checkout(session: owner, cart: tea, payments: const []),
      throwsA(
        isA<CheckoutException>().having(
          (e) => e.message,
          'message',
          contains('Select a customer'),
        ),
      ),
    );
    final cashier = withPermissions(const {
      Permissions.posView,
      Permissions.posCreateSale,
    });
    await expectLater(
      sell(2, paid: 50, session: cashier),
      throwsA(isA<CheckoutException>()),
    );
    expect(await count('sales'), 0);
    expect(await stock(), 50);
  });

  test(
    'credit limit blocks, override needs permission and is audited',
    () async {
      await sell(15); // 1500 of 2000 used
      await expectLater(
        sell(6),
        throwsA(
          isA<CreditLimitException>()
              .having((e) => e.projected, 'projected', Money.fromMajor(2100))
              .having((e) => e.limit, 'limit', Money.fromMajor(2000)),
        ),
      );
      final noOverride = withPermissions(const {
        Permissions.posView,
        Permissions.posCreateSale,
        Permissions.creditCreate,
      });
      await expectLater(
        sell(6, session: noOverride, override: true),
        throwsA(isA<PermissionDeniedException>()),
      );
      final result = await sell(6, override: true);
      expect(result.outstanding, Money.fromMajor(600));
      final audit = await fixture.database
          .customSelect(
            "SELECT COUNT(*) AS n FROM audit_logs WHERE action = 'credit.limit_override'",
          )
          .getSingle();
      expect(audit.read<int>('n'), 1);
      expect(
        (await credit.balance(owner, customerId)).outstanding,
        Money.fromMajor(2100),
      );
    },
  );

  test(
    'payments are applied oldest first and cannot exceed the balance',
    () async {
      await customers.save(
        session: owner,
        id: customerId,
        name: 'Bilal',
        phone: '0300',
        creditLimit: 2000,
        openingBalance: 100,
      );
      final first = await sell(2); // 200
      final second = await sell(3, paid: 100); // 200 outstanding
      expect(
        (await credit.balance(owner, customerId)).outstanding,
        Money.fromMajor(500),
      );
      await expectLater(
        credit.receivePayment(
          owner,
          customerId: customerId,
          amount: Money.fromMajor(501),
          method: 'cash',
        ),
        throwsA(isA<CreditException>()),
      );

      final payment = await credit.receivePayment(
        owner,
        customerId: customerId,
        amount: Money.fromMajor(250),
        method: 'bank',
        reference: 'TRX-1',
      );
      expect(payment.balance, Money.fromMajor(250));
      final records = await credit.payments(owner, customerId: customerId);
      expect(records.single.allocations, [
        ('Opening balance', Money.fromMajor(100)),
        (first.invoiceNumber, Money.fromMajor(150)),
      ]);
      final items = await credit.openItems(owner, customerId);
      expect(items.map((i) => (i.saleId, i.outstanding)), [
        (first.saleId, Money.fromMajor(50)),
        (second.saleId, Money.fromMajor(200)),
      ]);
      final firstSale = await (fixture.database.select(
        fixture.database.sales,
      )..where((s) => s.id.equals(first.saleId))).getSingle();
      expect(firstSale.paymentStatus, PaymentStatus.partial);

      // Settle everything; the account balance equals the open items.
      await credit.receivePayment(
        owner,
        customerId: customerId,
        amount: Money.fromMajor(250),
        method: 'card',
      );
      expect(await credit.openItems(owner, customerId), isEmpty);
      expect((await credit.balance(owner, customerId)).outstanding, Money.zero);
      final secondSale = await (fixture.database.select(
        fixture.database.sales,
      )..where((s) => s.id.equals(second.saleId))).getSingle();
      expect(secondSale.paymentStatus, PaymentStatus.paid);
      await expectLater(
        credit.receivePayment(
          owner,
          customerId: customerId,
          amount: Money.fromMajor(1),
          method: 'cash',
        ),
        throwsA(isA<CreditException>()),
      );
    },
  );

  test('manual allocation, reversal and cash drawer', () async {
    final cashbook = CashbookService(fixture.database);
    await cashbook.openSession(owner, Money.fromMajor(50));
    final first = await sell(2);
    final second = await sell(3);
    await expectLater(
      credit.receivePayment(
        owner,
        customerId: customerId,
        amount: Money.fromMajor(100),
        method: 'cash',
        manualAllocations: {second.saleId: Money.fromMajor(50)},
      ),
      throwsA(isA<CreditException>()),
    );
    final payment = await credit.receivePayment(
      owner,
      customerId: customerId,
      amount: Money.fromMajor(100),
      method: 'cash',
      manualAllocations: {second.saleId: Money.fromMajor(100)},
    );
    final items = await credit.openItems(owner, customerId);
    expect(items.map((i) => (i.saleId, i.outstanding)), [
      (first.saleId, Money.fromMajor(200)),
      (second.saleId, Money.fromMajor(200)),
    ]);
    var drawer = await cashbook.watchCurrent(owner).first;
    expect(drawer!.expected, Money.fromMajor(150));

    final noPermission = withPermissions(const {Permissions.creditView});
    await expectLater(
      credit.reversePayment(
        noPermission,
        paymentId: payment.paymentId,
        reason: 'x',
      ),
      throwsA(isA<PermissionDeniedException>()),
    );
    await credit.reversePayment(
      owner,
      paymentId: payment.paymentId,
      reason: 'Wrong customer',
    );
    expect(
      (await credit.balance(owner, customerId)).outstanding,
      Money.fromMajor(500),
    );
    drawer = await cashbook.watchCurrent(owner).first;
    expect(drawer!.expected, Money.fromMajor(50));
    final ledger = await credit.ledger(
      owner,
      customerId,
      filter: LedgerFilter.payments,
    );
    expect(ledger.rows.map((r) => r.entry.type), [
      LedgerType.payment,
      LedgerType.paymentReversal,
    ]);
    await expectLater(
      credit.reversePayment(
        owner,
        paymentId: payment.paymentId,
        reason: 'again',
      ),
      throwsA(isA<CreditException>()),
    );
  });

  test('due status and overdue receivables', () async {
    final now = DateTime(2026, 5, 10, 15);
    expect(DueStatus.of(null, now: now), DueStatus.current);
    expect(DueStatus.of(DateTime(2026, 5, 9), now: now), DueStatus.overdue);
    expect(DueStatus.of(DateTime(2026, 5, 10), now: now), DueStatus.dueSoon);
    expect(DueStatus.of(DateTime(2026, 5, 13), now: now), DueStatus.dueSoon);
    expect(DueStatus.of(DateTime(2026, 5, 14), now: now), DueStatus.current);

    final late = await sell(
      2,
      dueDate: DateTime.now().add(const Duration(days: 5)),
    );
    await sell(1, dueDate: DateTime.now().add(const Duration(days: 20)));
    var summary = await credit.receivables(owner);
    expect(summary.total, Money.fromMajor(300));
    expect(summary.overdue, Money.zero);
    expect(summary.dueThisWeek, Money.fromMajor(200));

    final viewer = withPermissions(const {Permissions.creditView});
    await expectLater(
      credit.setDueDate(viewer, saleId: late.saleId, dueDate: DateTime(2020)),
      throwsA(isA<PermissionDeniedException>()),
    );
    await credit.setDueDate(
      owner,
      saleId: late.saleId,
      dueDate: DateTime.now().subtract(const Duration(days: 3)),
    );
    summary = await credit.receivables(owner);
    expect(summary.overdue, Money.fromMajor(200));
    expect(summary.customers, 1);
    expect(summary.topDebtors.single.overdue, Money.fromMajor(200));
    final balance = await credit.balance(owner, customerId);
    expect(balance.overdue, Money.fromMajor(200));
    expect(balance.dueStatus, DueStatus.overdue);
    expect(await credit.debtorList(owner, overdueOnly: true), hasLength(1));
  });

  test('credit checkout rolls back every write on failure', () async {
    await expectLater(
      sell(4, paid: 100, probe: () async => throw StateError('disk full')),
      throwsStateError,
    );
    expect(await count('sales'), 0);
    expect(await count('customer_ledger_entries'), 0);
    expect(await count('payments'), 0);
    expect(await stock(), 50);
    expect((await credit.balance(owner, customerId)).outstanding, Money.zero);
  });

  test('customer payment rolls back every write on failure', () async {
    await sell(4);
    final failing = CreditService(
      fixture.database,
      transactionProbe: () async => throw StateError('power cut'),
    );
    await expectLater(
      failing.receivePayment(
        owner,
        customerId: customerId,
        amount: Money.fromMajor(100),
        method: 'cash',
      ),
      throwsStateError,
    );
    expect(await count('customer_payments'), 0);
    expect(await count('payment_allocations'), 0);
    expect(await count('customer_ledger_entries'), 1);
    expect(await count('cash_transactions'), 0);
    expect(
      (await credit.balance(owner, customerId)).outstanding,
      Money.fromMajor(400),
    );
  });

  test('returns reduce the unpaid balance before paying money back', () async {
    final cashbook = CashbookService(fixture.database);
    await cashbook.openSession(owner, Money.fromMajor(500));
    final refunds = RefundService(fixture.database);
    // 10 × 100 = 1000, 300 paid now, 700 on account.
    final result = await sell(10, paid: 300);
    var state = await refunds.load(owner, result.saleId);
    expect(state.outstanding, Money.fromMajor(700));

    // Returning 4 units (400) only reduces the balance.
    final first = await refunds.refund(
      owner,
      saleId: result.saleId,
      lines: [
        RefundLineInput(saleItemId: state.lines.single.item.id, quantity: 4),
      ],
      method: 'cash',
      reason: 'Damaged / defective',
    );
    expect(first.creditApplied, Money.fromMajor(400));
    expect(first.paidOut, Money.zero);
    final firstRow = await (fixture.database.select(
      fixture.database.saleRefunds,
    )..where((r) => r.id.equals(first.refundId))).getSingle();
    expect(firstRow.method, 'credit');
    expect(
      (await credit.balance(owner, customerId)).outstanding,
      Money.fromMajor(300),
    );

    // Returning 5 more (500): 300 clears the balance, 200 is paid back.
    state = await refunds.load(owner, result.saleId);
    final second = await refunds.refund(
      owner,
      saleId: result.saleId,
      lines: [
        RefundLineInput(saleItemId: state.lines.single.item.id, quantity: 5),
      ],
      method: 'cash',
      reason: 'Damaged / defective',
    );
    expect(second.creditApplied, Money.fromMajor(300));
    expect(second.paidOut, Money.fromMajor(200));
    expect((await credit.balance(owner, customerId)).outstanding, Money.zero);
    final drawer = await cashbook.watchCurrent(owner).first;
    // 500 float + 300 cash sale - 200 cash refund.
    expect(drawer!.expected, Money.fromMajor(600));
    expect(await stock(), 49);
  });

  test(
    'voiding a credit sale clears it; paid invoices cannot be voided',
    () async {
      final refunds = RefundService(fixture.database);
      final unpaid = await sell(3);
      await refunds.voidSale(owner, saleId: unpaid.saleId, reason: 'Mistake');
      expect((await credit.balance(owner, customerId)).outstanding, Money.zero);
      final voidRow = await fixture.database
          .customSelect(
            'SELECT credit_applied FROM sale_refunds WHERE sale_id = ?',
            variables: [Variable.withString(unpaid.saleId)],
          )
          .getSingle();
      expect(voidRow.read<double>('credit_applied'), 300);

      final paidLater = await sell(2);
      await credit.receivePayment(
        owner,
        customerId: customerId,
        amount: Money.fromMajor(50),
        method: 'card',
      );
      final state = await refunds.load(owner, paidLater.saleId);
      expect(state.canVoid, isFalse);
      await expectLater(
        refunds.voidSale(owner, saleId: paidLater.saleId, reason: 'x'),
        throwsA(isA<RefundException>()),
      );
    },
  );

  test('opening balance edits are written to the ledger', () async {
    await customers.save(
      session: owner,
      id: customerId,
      name: 'Bilal',
      creditLimit: 2000,
      openingBalance: 250,
    );
    await customers.save(
      session: owner,
      id: customerId,
      name: 'Bilal',
      creditLimit: 2000,
      openingBalance: 100,
    );
    final ledger = await credit.ledger(owner, customerId);
    expect(ledger.rows.map((r) => r.entry.type), [
      LedgerType.opening,
      LedgerType.adjustment,
    ]);
    expect(ledger.closing, Money.fromMajor(100));
    expect(
      (await credit.openItems(owner, customerId)).single.outstanding,
      Money.fromMajor(100),
    );
  });

  test(
    'credit reports: balances, credit sales, payments, aging, statement',
    () async {
      final reports = ReportsService(fixture.database);
      final range = DateTimeRange(
        start: DateTime.now().subtract(const Duration(days: 1)),
        end: DateTime.now(),
      );
      final overdue = await sell(3, paid: 100, dueDate: DateTime.now());
      await credit.setDueDate(
        owner,
        saleId: overdue.saleId,
        dueDate: DateTime.now().subtract(const Duration(days: 40)),
      );
      await sell(1);
      await credit.receivePayment(
        owner,
        customerId: customerId,
        amount: Money.fromMajor(50),
        method: 'bank',
      );

      final balances = await reports.run(
        owner,
        ReportKind.customerBalances,
        range,
      );
      expect(balances.rows.single[3], 250.0);
      expect(balances.kpis.first.value, 250.0);

      final sales = await reports.run(owner, ReportKind.creditSales, range);
      expect(sales.rows, hasLength(2));
      expect(sales.kpis[2].value, 300.0, reason: 'put on account');
      expect(sales.kpis[3].value, 250.0, reason: 'still outstanding');

      final payments = await reports.run(
        owner,
        ReportKind.paymentsReceived,
        range,
        filters: const ReportFilters(method: 'cash'),
      );
      expect(payments.rows, isEmpty);
      final allPayments = await reports.run(
        owner,
        ReportKind.paymentsReceived,
        range,
      );
      expect(allPayments.kpis.first.value, 50.0);

      final aging = await reports.run(owner, ReportKind.overdue, range);
      expect(aging.rows.single[5], 150.0);
      expect(aging.chart.firstWhere((c) => c.$1 == '31–60 days').$2, 150.0);

      final statement = await reports.run(
        owner,
        ReportKind.statement,
        range,
        filters: ReportFilters(customerId: customerId),
      );
      expect(statement.kpis.last.value, 250.0);
      expect(statement.rows.map((r) => r[1]), [
        'Sale',
        'Paid at sale',
        'Sale',
        'Payment received',
      ]);

      final cashierOnly = withPermissions(const {Permissions.reportsView});
      await expectLater(
        reports.run(cashierOnly, ReportKind.creditSales, range),
        throwsA(isA<PermissionDeniedException>()),
      );
    },
  );

  test('allocateOldestFirst', () {
    final items = [
      OpenItem(
        saleId: 'b',
        label: 'B',
        date: DateTime(2026, 2),
        outstanding: Money.fromMajor(30),
      ),
      OpenItem(
        saleId: 'a',
        label: 'A',
        date: DateTime(2026, 1),
        outstanding: Money.fromMajor(20),
      ),
      OpenItem(
        saleId: null,
        label: 'Opening',
        date: DateTime(2026, 3),
        outstanding: Money.fromMajor(10),
      ),
    ];
    final plan = allocateOldestFirst(Money.fromMajor(45), items);
    expect(plan.map((p) => (p.saleId, p.amount)), [
      (null, Money.fromMajor(10)),
      ('a', Money.fromMajor(20)),
      ('b', Money.fromMajor(15)),
    ]);
    expect(
      () => allocateOldestFirst(Money.fromMajor(61), items),
      throwsArgumentError,
    );
  });
}
