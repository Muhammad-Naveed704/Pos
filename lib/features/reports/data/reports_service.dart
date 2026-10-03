import 'package:drift/drift.dart';
import 'package:flutter/material.dart' show DateTimeRange, IconData, Icons;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/database_provider.dart';
import '../../auth/domain/app_session.dart';
import '../../auth/domain/permission_guard.dart';
import '../../auth/domain/permissions.dart';
import '../../credit/data/credit_ledger.dart';
import '../../credit/data/credit_service.dart';
import '../../credit/domain/credit.dart';

final reportsServiceProvider = Provider<ReportsService>(
  (ref) => ReportsService(ref.watch(databaseProvider)),
);

enum ReportKind {
  summary('Sales summary', Icons.insights_rounded, Permissions.reportsSales),
  daily('Daily sales', Icons.calendar_month_rounded, Permissions.reportsSales),
  products('Products', Icons.inventory_2_outlined, Permissions.reportsSales),
  categories('Categories', Icons.category_outlined, Permissions.reportsSales),
  cashiers('Cashiers', Icons.badge_outlined, Permissions.reportsSales),
  payments('Payment methods', Icons.payments_outlined, Permissions.reportsCash),
  purchases(
    'Purchases',
    Icons.local_shipping_outlined,
    Permissions.purchasesView,
  ),
  stock('Stock valuation', Icons.warehouse_outlined, Permissions.inventoryView),
  customerBalances(
    'Customer balances',
    Icons.account_balance_wallet_outlined,
    Permissions.creditView,
  ),
  creditSales(
    'Credit sales',
    Icons.request_quote_outlined,
    Permissions.creditView,
  ),
  paymentsReceived(
    'Payments received',
    Icons.price_check_rounded,
    Permissions.creditView,
  ),
  outstanding(
    'Outstanding receivables',
    Icons.pending_actions_rounded,
    Permissions.creditView,
  ),
  overdue(
    'Overdue receivables',
    Icons.error_outline_rounded,
    Permissions.creditView,
  ),
  statement(
    'Customer statement',
    Icons.description_outlined,
    Permissions.customerStatement,
  );

  const ReportKind(this.label, this.icon, this.permission);
  final String label;
  final IconData icon;
  final String permission;

  /// Whether the report depends on the selected date range.
  bool get usesDates => !const {
    ReportKind.stock,
    ReportKind.customerBalances,
    ReportKind.outstanding,
    ReportKind.overdue,
  }.contains(this);

  /// Customer-account reports (shown in their own group, with filters).
  bool get isCredit => index >= ReportKind.customerBalances.index;

  bool get needsCustomer => this == ReportKind.statement;
  bool get usesCashier => this == creditSales || this == paymentsReceived;
  bool get usesMethod => this == paymentsReceived;
  bool get usesStore => isCredit && this != statement;
}

/// Optional filters used by the customer-account reports.
class ReportFilters {
  const ReportFilters({
    this.customerId,
    this.cashierId,
    this.method,
    this.allStores = false,
  });
  final String? customerId;
  final String? cashierId;
  final String? method;

  /// Customer accounts are business-wide; reports default to the active
  /// store and can include every store on request.
  final bool allStores;

  ReportFilters copyWith({
    String? Function()? customerId,
    String? Function()? cashierId,
    String? Function()? method,
    bool? allStores,
  }) => ReportFilters(
    customerId: customerId == null ? this.customerId : customerId(),
    cashierId: cashierId == null ? this.cashierId : cashierId(),
    method: method == null ? this.method : method(),
    allStores: allStores ?? this.allStores,
  );
}

enum ColumnKind { text, integer, quantity, money, percent }

class ReportColumn {
  const ReportColumn(this.label, this.kind, {this.flex = 1});
  final String label;
  final ColumnKind kind;
  final int flex;

  bool get numeric => kind != ColumnKind.text;
}

class ReportKpi {
  const ReportKpi(this.label, this.value, this.kind, {this.note});
  final String label;
  final double value;
  final ColumnKind kind;
  final String? note;
}

class ReportResult {
  const ReportResult({
    required this.kind,
    required this.columns,
    required this.rows,
    this.kpis = const [],
    this.chart = const [],
    this.chartLabel,
    this.footnote,
  });
  final ReportKind kind;
  final List<ReportColumn> columns;

  /// Cells are String, int or double, matching [columns].
  final List<List<Object>> rows;
  final List<ReportKpi> kpis;

  /// Single-series bar chart data (label, value).
  final List<(String, double)> chart;
  final String? chartLabel;
  final String? footnote;
}

class ReportsService {
  ReportsService(this._database);
  final AppDatabase _database;

  static const _profitFootnote =
      'Profit uses the cost price recorded at the time of sale. Sales made '
      'before this version use the product cost at upgrade time. Line profit '
      'excludes sale-level discounts; totals include them.';

  Future<ReportResult> run(
    AppSession session,
    ReportKind kind,
    DateTimeRange range, {
    ReportFilters filters = const ReportFilters(),
  }) async {
    PermissionGuard.require(session, Permissions.reportsView);
    PermissionGuard.require(session, kind.permission);
    final from = DateTime(range.start.year, range.start.month, range.start.day);
    final to = DateTime(range.end.year, range.end.month, range.end.day + 1);
    final profit = session.can(Permissions.reportsProfit);
    return switch (kind) {
      ReportKind.summary => _summary(session, from, to, profit),
      ReportKind.daily => _daily(session, from, to, profit),
      ReportKind.products => _products(session, from, to, profit),
      ReportKind.categories => _categories(session, from, to, profit),
      ReportKind.cashiers => _cashiers(session, from, to),
      ReportKind.payments => _payments(session, from, to),
      ReportKind.purchases => _purchases(session, from, to),
      ReportKind.stock => _stock(session),
      ReportKind.customerBalances => _customerBalances(session, filters),
      ReportKind.creditSales => _creditSales(session, from, to, filters),
      ReportKind.paymentsReceived => _paymentsReceived(
        session,
        from,
        to,
        filters,
      ),
      ReportKind.outstanding => _openInvoices(session, filters, false),
      ReportKind.overdue => _openInvoices(session, filters, true),
      ReportKind.statement => _statement(session, from, to, filters),
    };
  }

  static DateTime _today() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  String _storeClause(
    AppSession session,
    ReportFilters f,
    String column,
    List<Variable> vars,
  ) {
    if (f.allStores) return '1 = 1';
    vars.add(Variable.withString(session.store.id));
    return '$column = ?${vars.length}';
  }

  Future<ReportResult> _customerBalances(
    AppSession session,
    ReportFilters f,
  ) async {
    final vars = <Variable>[Variable.withDateTime(_today())];
    final customer = f.customerId == null
        ? ''
        : 'AND c.id = ?${(vars..add(Variable.withString(f.customerId!))).length}';
    final rows = await _database.customSelect('''
      SELECT c.name, COALESCE(c.phone, '') AS phone, c.credit_limit, b.balance,
        COALESCE((SELECT SUM($saleOutstandingSql) FROM sales s
          WHERE s.customer_id = c.id AND s.credit_amount > 0
            AND s.due_date IS NOT NULL AND s.due_date < ?1), 0.0) AS overdue,
        (SELECT MIN(s.due_date) FROM sales s WHERE s.customer_id = c.id
          AND s.credit_amount > 0 AND $saleOutstandingSql > 0.004) AS oldest_due,
        c.is_active
      FROM (SELECT customer_id, SUM(debit - credit) AS balance
            FROM customer_ledger_entries GROUP BY customer_id) b
      JOIN customers c ON c.id = b.customer_id
      WHERE b.balance > 0.004 $customer
      ORDER BY b.balance DESC
      ''', variables: vars).get();
    final total = rows.fold(0.0, (s, r) => s + r.read<double>('balance'));
    final overdue = rows.fold(0.0, (s, r) => s + r.read<double>('overdue'));
    return ReportResult(
      kind: ReportKind.customerBalances,
      kpis: [
        ReportKpi('Total receivable', total, ColumnKind.money),
        ReportKpi('Overdue', overdue, ColumnKind.money),
        ReportKpi('Customers', rows.length.toDouble(), ColumnKind.integer),
      ],
      columns: const [
        ReportColumn('Customer', ColumnKind.text, flex: 3),
        ReportColumn('Phone', ColumnKind.text, flex: 2),
        ReportColumn('Credit limit', ColumnKind.money),
        ReportColumn('Outstanding', ColumnKind.money),
        ReportColumn('Overdue', ColumnKind.money),
        ReportColumn('Oldest due', ColumnKind.text),
      ],
      rows: [
        for (final row in rows)
          [
            row.read<String>('name') +
                (row.read<bool>('is_active') ? '' : ' (inactive)'),
            row.read<String>('phone'),
            row.read<double>('credit_limit'),
            row.read<double>('balance'),
            row.read<double>('overdue'),
            _dueText(row.readNullable<DateTime>('oldest_due')),
          ],
      ],
      chart: [
        for (final row in rows.take(10))
          (row.read<String>('name'), row.read<double>('balance')),
      ],
      chartLabel: 'Largest balances',
      footnote: 'Customer accounts are shared by all stores. Balances come from the customer ledger.',
    );
  }

  static String _dueText(DateTime? due) {
    if (due == null) return 'No due date';
    final local = due.toLocal();
    return '${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')} '
        '(${DueStatus.of(due).label})';
  }

  Future<ReportResult> _creditSales(
    AppSession session,
    DateTime from,
    DateTime to,
    ReportFilters f,
  ) async {
    final vars = <Variable>[
      Variable.withDateTime(from),
      Variable.withDateTime(to),
    ];
    final where = <String>[
      's.credit_amount > 0',
      "s.sale_status <> 'voided'",
      's.created_at >= ?1',
      's.created_at < ?2',
      _storeClause(session, f, 's.store_id', vars),
    ];
    if (f.customerId != null) {
      vars.add(Variable.withString(f.customerId!));
      where.add('s.customer_id = ?${vars.length}');
    }
    if (f.cashierId != null) {
      vars.add(Variable.withString(f.cashierId!));
      where.add('s.user_id = ?${vars.length}');
    }
    final rows = await _database.customSelect('''
      SELECT s.invoice_number, s.created_at, s.grand_total, s.credit_amount,
             s.due_date, s.payment_status, COALESCE(c.name, '') AS customer,
             u.display_name AS cashier, $saleOutstandingSql AS outstanding
      FROM sales s
      LEFT JOIN customers c ON c.id = s.customer_id
      JOIN users u ON u.id = s.user_id
      WHERE ${where.join(' AND ')}
      ORDER BY s.created_at DESC, s.rowid DESC
      ''', variables: vars).get();
    double sum(String column) =>
        rows.fold(0.0, (s, r) => s + r.read<double>(column));
    return ReportResult(
      kind: ReportKind.creditSales,
      kpis: [
        ReportKpi(
          'Credit invoices',
          rows.length.toDouble(),
          ColumnKind.integer,
        ),
        ReportKpi('Invoice value', sum('grand_total'), ColumnKind.money),
        ReportKpi('Put on account', sum('credit_amount'), ColumnKind.money),
        ReportKpi(
          'Still outstanding',
          sum('outstanding'),
          ColumnKind.money,
          note: 'After payments and returns',
        ),
      ],
      columns: const [
        ReportColumn('Invoice', ColumnKind.text, flex: 2),
        ReportColumn('Date', ColumnKind.text),
        ReportColumn('Customer', ColumnKind.text, flex: 2),
        ReportColumn('Cashier', ColumnKind.text),
        ReportColumn('Total', ColumnKind.money),
        ReportColumn('On account', ColumnKind.money),
        ReportColumn('Outstanding', ColumnKind.money),
        ReportColumn('Due', ColumnKind.text, flex: 2),
      ],
      rows: [
        for (final row in rows)
          [
            row.read<String>('invoice_number'),
            _day(row.read<DateTime>('created_at')),
            row.read<String>('customer'),
            row.read<String>('cashier'),
            row.read<double>('grand_total'),
            row.read<double>('credit_amount'),
            _positive(row.read<double>('outstanding')),
            row.read<double>('outstanding') > 0.004
                ? _dueText(row.readNullable<DateTime>('due_date'))
                : 'Settled',
          ],
      ],
    );
  }

  static String _day(DateTime value) {
    final local = value.toLocal();
    return '${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')}';
  }

  static double _positive(double value) => value < 0.005 ? 0 : value;

  Future<ReportResult> _paymentsReceived(
    AppSession session,
    DateTime from,
    DateTime to,
    ReportFilters f,
  ) async {
    final vars = <Variable>[
      Variable.withDateTime(from),
      Variable.withDateTime(to),
    ];
    final where = <String>[
      'cp.created_at >= ?1',
      'cp.created_at < ?2',
      _storeClause(session, f, 'cp.store_id', vars),
    ];
    if (f.customerId != null) {
      vars.add(Variable.withString(f.customerId!));
      where.add('cp.customer_id = ?${vars.length}');
    }
    if (f.cashierId != null) {
      vars.add(Variable.withString(f.cashierId!));
      where.add('cp.user_id = ?${vars.length}');
    }
    if (f.method != null) {
      vars.add(Variable.withString(f.method!));
      where.add('cp.method = ?${vars.length}');
    }
    final rows = await _database.customSelect('''
      SELECT cp.number, cp.created_at, cp.method, cp.amount, cp.status,
             COALESCE(cp.reference, '') AS reference,
             c.name AS customer, u.display_name AS cashier
      FROM customer_payments cp
      JOIN customers c ON c.id = cp.customer_id
      JOIN users u ON u.id = cp.user_id
      WHERE ${where.join(' AND ')}
      ORDER BY cp.created_at DESC, cp.rowid DESC
      ''', variables: vars).get();
    final posted = rows.where((r) => r.read<String>('status') == 'posted');
    final byMethod = <String, double>{};
    for (final row in posted) {
      final method = row.read<String>('method').toUpperCase();
      byMethod[method] = (byMethod[method] ?? 0) + row.read<double>('amount');
    }
    return ReportResult(
      kind: ReportKind.paymentsReceived,
      kpis: [
        ReportKpi(
          'Received',
          posted.fold(0.0, (s, r) => s + r.read<double>('amount')),
          ColumnKind.money,
        ),
        ReportKpi('Payments', posted.length.toDouble(), ColumnKind.integer),
        ReportKpi(
          'Reversed',
          (rows.length - posted.length).toDouble(),
          ColumnKind.integer,
        ),
      ],
      columns: const [
        ReportColumn('Payment', ColumnKind.text, flex: 2),
        ReportColumn('Date', ColumnKind.text),
        ReportColumn('Customer', ColumnKind.text, flex: 2),
        ReportColumn('Method', ColumnKind.text),
        ReportColumn('Reference', ColumnKind.text),
        ReportColumn('Received by', ColumnKind.text),
        ReportColumn('Amount', ColumnKind.money),
      ],
      rows: [
        for (final row in rows)
          [
            row.read<String>('number') +
                (row.read<String>('status') == 'posted' ? '' : ' (reversed)'),
            _day(row.read<DateTime>('created_at')),
            row.read<String>('customer'),
            row.read<String>('method').toUpperCase(),
            row.read<String>('reference'),
            row.read<String>('cashier'),
            row.read<String>('status') == 'posted'
                ? row.read<double>('amount')
                : 0.0,
          ],
      ],
      chart: [for (final e in byMethod.entries) (e.key, e.value)],
      chartLabel: 'Received by method',
    );
  }

  Future<ReportResult> _openInvoices(
    AppSession session,
    ReportFilters f,
    bool overdueOnly,
  ) async {
    final today = _today();
    final vars = <Variable>[Variable.withDateTime(today)];
    final where = <String>[
      's.credit_amount > 0',
      '$saleOutstandingSql > 0.004',
      _storeClause(session, f, 's.store_id', vars),
      if (overdueOnly) 's.due_date IS NOT NULL AND s.due_date < ?1',
    ];
    if (f.customerId != null) {
      vars.add(Variable.withString(f.customerId!));
      where.add('s.customer_id = ?${vars.length}');
    }
    final rows = await _database.customSelect('''
      SELECT s.invoice_number, s.created_at, s.due_date, s.grand_total,
             COALESCE(c.name, '') AS customer, COALESCE(c.phone, '') AS phone,
             $saleOutstandingSql AS outstanding
      FROM sales s LEFT JOIN customers c ON c.id = s.customer_id
      WHERE ${where.join(' AND ')}
      ORDER BY COALESCE(s.due_date, s.created_at), s.rowid
      ''', variables: vars).get();
    // Aging by days past due (no due date counts as current).
    const buckets = [
      'Current',
      '1–30 days',
      '31–60 days',
      '61–90 days',
      '90+ days',
    ];
    final aging = {for (final b in buckets) b: 0.0};
    final result = <List<Object>>[];
    for (final row in rows) {
      final due = row.readNullable<DateTime>('due_date');
      final late = due == null ? 0 : today.difference(due.toLocal()).inDays;
      final bucket = late <= 0
          ? buckets[0]
          : late <= 30
          ? buckets[1]
          : late <= 60
          ? buckets[2]
          : late <= 90
          ? buckets[3]
          : buckets[4];
      final amount = row.read<double>('outstanding');
      aging[bucket] = aging[bucket]! + amount;
      result.add([
        row.read<String>('invoice_number'),
        row.read<String>('customer'),
        _day(row.read<DateTime>('created_at')),
        due == null ? 'No due date' : _day(due),
        late > 0 ? late : 0,
        amount,
        DueStatus.of(due).label,
      ]);
    }
    final total = aging.values.fold(0.0, (a, b) => a + b);
    return ReportResult(
      kind: overdueOnly ? ReportKind.overdue : ReportKind.outstanding,
      kpis: [
        ReportKpi(
          overdueOnly ? 'Overdue' : 'Outstanding',
          total,
          ColumnKind.money,
        ),
        ReportKpi('Invoices', rows.length.toDouble(), ColumnKind.integer),
        if (!overdueOnly)
          ReportKpi('Overdue', total - aging[buckets[0]]!, ColumnKind.money),
      ],
      columns: const [
        ReportColumn('Invoice', ColumnKind.text, flex: 2),
        ReportColumn('Customer', ColumnKind.text, flex: 2),
        ReportColumn('Date', ColumnKind.text),
        ReportColumn('Due', ColumnKind.text),
        ReportColumn('Days late', ColumnKind.integer),
        ReportColumn('Outstanding', ColumnKind.money),
        ReportColumn('Status', ColumnKind.text),
      ],
      rows: result,
      chart: [
        for (final b in buckets)
          if (!overdueOnly || b != buckets[0]) (b, aging[b]!),
      ],
      chartLabel: 'Aging by days past due',
      footnote:
          'Invoices only. Opening balances are included in Customer balances.',
    );
  }

  Future<ReportResult> _statement(
    AppSession session,
    DateTime from,
    DateTime to,
    ReportFilters f,
  ) async {
    final customerId = f.customerId;
    if (customerId == null) {
      return const ReportResult(
        kind: ReportKind.statement,
        columns: [ReportColumn('Choose a customer above', ColumnKind.text)],
        rows: [],
      );
    }
    final credit = CreditService(_database);
    final page = await credit.ledger(session, customerId, from: from, to: to);
    final balance = await credit.balance(session, customerId);
    return ReportResult(
      kind: ReportKind.statement,
      kpis: [
        ReportKpi('Opening balance', page.opening.majorUnits, ColumnKind.money),
        ReportKpi('Charges', page.debit.majorUnits, ColumnKind.money),
        ReportKpi(
          'Payments & credits',
          page.credit.majorUnits,
          ColumnKind.money,
        ),
        ReportKpi('Closing balance', page.closing.majorUnits, ColumnKind.money),
      ],
      columns: const [
        ReportColumn('Date', ColumnKind.text),
        ReportColumn('Type', ColumnKind.text),
        ReportColumn('Reference', ColumnKind.text, flex: 2),
        ReportColumn('Debit', ColumnKind.money),
        ReportColumn('Credit', ColumnKind.money),
        ReportColumn('Balance', ColumnKind.money),
        ReportColumn('User', ColumnKind.text),
      ],
      rows: [
        for (final row in page.rows)
          [
            _day(row.entry.createdAt),
            LedgerType.label(row.entry.type),
            row.entry.referenceNumber,
            row.debit.majorUnits,
            row.credit.majorUnits,
            row.balance.majorUnits,
            row.userName ?? '',
          ],
      ],
      footnote:
          '${balance.customer.name}: credit limit ${balance.creditLimit}, '
          'overdue now ${balance.overdue}. Positive balance = owed to the business.',
    );
  }

  List<Variable> _vars(AppSession session, DateTime from, DateTime to) => [
    Variable.withString(session.store.id),
    Variable.withDateTime(from),
    Variable.withDateTime(to),
  ];

  /// Sales that count: everything except voided ones. Refunds are subtracted
  /// separately on the date they happened.
  static const _completed =
      "s.store_id = ?1 AND s.sale_status <> 'voided' AND s.created_at >= ?2 AND s.created_at < ?3";

  static const _refundWhere =
      "r.store_id = ?1 AND r.kind = 'refund' AND r.created_at >= ?2 AND r.created_at < ?3";

  /// Refund value (incl. sale discount share), its tax share and the cost of
  /// restocked units, plus count — for refunds made in the period.
  Future<({double amount, double tax, double cost, int count})> _refundTotals(
    AppSession session,
    DateTime from,
    DateTime to,
  ) async {
    final row = await _database.customSelect('''
      SELECT COUNT(*) AS count,
             COALESCE(SUM(r.amount), 0.0) AS amount,
             COALESCE(SUM(CASE WHEN s.grand_total > 0 THEN r.amount * s.tax_amount / s.grand_total ELSE 0 END), 0.0) AS tax,
             COALESCE((SELECT SUM(ri.cost) FROM sale_refund_items ri JOIN sale_refunds r ON r.id = ri.refund_id
                       WHERE $_refundWhere AND ri.restocked = 1), 0.0) AS cost
      FROM sale_refunds r JOIN sales s ON s.id = r.sale_id
      WHERE $_refundWhere
      ''', variables: _vars(session, from, to)).getSingle();
    return (
      amount: row.read<double>('amount'),
      tax: row.read<double>('tax'),
      cost: row.read<double>('cost'),
      count: row.read<int>('count'),
    );
  }

  /// Per refunded product (line basis, like the product report):
  /// qty, value, tax share and restocked cost.
  Future<Map<String, ({double qty, double value, double tax, double cost})>>
  _refundsBy(
    AppSession session,
    DateTime from,
    DateTime to,
    String keySql, {
    String joins = '',
  }) async {
    final rows = await _database.customSelect('''
      SELECT $keySql AS k,
             SUM(ri.qty) AS qty,
             SUM(ri.qty * i.line_total / i.qty) AS value,
             SUM(ri.qty * i.tax_amount / i.qty) AS tax,
             SUM(CASE WHEN ri.restocked = 1 THEN ri.cost ELSE 0 END) AS cost
      FROM sale_refund_items ri
      JOIN sale_refunds r ON r.id = ri.refund_id
      JOIN sale_items i ON i.id = ri.sale_item_id
      $joins
      WHERE $_refundWhere AND i.qty > 0
      GROUP BY k
      ''', variables: _vars(session, from, to)).get();
    return {
      for (final row in rows)
        row.read<String>('k'): (
          qty: row.read<double>('qty'),
          value: row.read<double>('value'),
          tax: row.read<double>('tax'),
          cost: row.read<double>('cost'),
        ),
    };
  }

  Future<ReportResult> _summary(
    AppSession session,
    DateTime from,
    DateTime to,
    bool profit,
  ) async {
    final row = await _database.customSelect('''
      SELECT COUNT(*) AS invoices,
             COALESCE(SUM(s.subtotal), 0.0) AS gross,
             COALESCE(SUM(s.discount_amount), 0.0) AS discounts,
             COALESCE(SUM(s.tax_amount), 0.0) AS tax,
             COALESCE(SUM(s.grand_total), 0.0) AS net,
             COALESCE((SELECT SUM(i.qty) FROM sale_items i JOIN sales s ON s.id = i.sale_id WHERE $_completed), 0.0) AS items,
             COALESCE((SELECT SUM(i.qty * i.unit_cost) FROM sale_items i JOIN sales s ON s.id = i.sale_id WHERE $_completed), 0.0) AS cost,
             COUNT(DISTINCT s.customer_id) AS customers
      FROM sales s WHERE $_completed
      ''', variables: _vars(session, from, to)).getSingle();
    final invoices = row.read<int>('invoices');
    final refunds = await _refundTotals(session, from, to);
    final salesNet = row.read<double>('net');
    final net = salesNet - refunds.amount;
    final tax = row.read<double>('tax') - refunds.tax;
    final cost = row.read<double>('cost') - refunds.cost;
    final revenue = net - tax;
    final grossProfit = revenue - cost;
    final daily = await _dailyRows(session, from, to);
    return ReportResult(
      kind: ReportKind.summary,
      kpis: [
        ReportKpi(
          'Net sales',
          net,
          ColumnKind.money,
          note: '$invoices invoices',
        ),
        ReportKpi(
          'Average sale',
          invoices == 0 ? 0 : net / invoices,
          ColumnKind.money,
        ),
        ReportKpi(
          'Refunds',
          refunds.amount,
          ColumnKind.money,
          note: '${refunds.count} refund(s)',
        ),
        ReportKpi('Tax collected', tax, ColumnKind.money),
        if (profit) ...[
          ReportKpi('Gross profit', grossProfit, ColumnKind.money),
          ReportKpi(
            'Margin',
            revenue == 0 ? 0 : grossProfit / revenue * 100,
            ColumnKind.percent,
          ),
        ],
      ],
      columns: const [
        ReportColumn('Measure', ColumnKind.text, flex: 3),
        ReportColumn('Value', ColumnKind.money, flex: 2),
      ],
      rows: [
        ['Gross sales (before discounts)', row.read<double>('gross')],
        ['Discounts', -row.read<double>('discounts')],
        ['Sales after discounts', salesNet],
        ['Refunds', -refunds.amount],
        ['Tax (after refunds)', tax],
        ['Net sales', net],
        ['Sales excluding tax', revenue],
        if (profit) ['Cost of goods sold', -cost],
        if (profit) ['Gross profit', grossProfit],
      ],
      chart: [for (final day in daily) (day.$1, day.$3)],
      chartLabel: 'Net sales by day',
      footnote: profit ? _profitFootnote : null,
    );
  }

  /// (label, invoices, net after refunds, tax, discount, cost, refunds)
  Future<List<(String, int, double, double, double, double, double)>>
  _dailyRows(AppSession session, DateTime from, DateTime to) async {
    final rows = await _database.customSelect('''
      SELECT date(s.created_at, 'unixepoch', 'localtime') AS day,
             COUNT(*) AS invoices,
             SUM(s.grand_total) AS net,
             SUM(s.tax_amount) AS tax,
             SUM(s.discount_amount) AS discount,
             COALESCE((SELECT SUM(i.qty * i.unit_cost) FROM sale_items i JOIN sales x ON x.id = i.sale_id
               WHERE x.store_id = ?1 AND x.sale_status <> 'voided'
                 AND date(x.created_at, 'unixepoch', 'localtime') = date(s.created_at, 'unixepoch', 'localtime')), 0.0) AS cost
      FROM sales s WHERE $_completed
      GROUP BY day ORDER BY day
      ''', variables: _vars(session, from, to)).get();
    final refundRows = await _database.customSelect('''
      SELECT date(r.created_at, 'unixepoch', 'localtime') AS day,
             SUM(r.amount) AS amount,
             SUM(CASE WHEN s.grand_total > 0 THEN r.amount * s.tax_amount / s.grand_total ELSE 0 END) AS tax,
             COALESCE(SUM((SELECT SUM(ri.cost) FROM sale_refund_items ri
                           WHERE ri.refund_id = r.id AND ri.restocked = 1)), 0.0) AS cost
      FROM sale_refunds r JOIN sales s ON s.id = r.sale_id
      WHERE $_refundWhere
      GROUP BY day
      ''', variables: _vars(session, from, to)).get();
    final refunds = {
      for (final row in refundRows)
        row.read<String>('day'): (
          row.read<double>('amount'),
          row.read<double>('tax'),
          row.read<double>('cost'),
        ),
    };
    final sales = {for (final row in rows) row.read<String>('day'): row};
    final days = {...sales.keys, ...refunds.keys}.toList()..sort();
    return [
      for (final day in days)
        () {
          final row = sales[day];
          final refund = refunds[day] ?? (0.0, 0.0, 0.0);
          return (
            day,
            row?.read<int>('invoices') ?? 0,
            (row?.read<double>('net') ?? 0) - refund.$1,
            (row?.read<double>('tax') ?? 0) - refund.$2,
            row?.read<double>('discount') ?? 0,
            (row?.read<double>('cost') ?? 0) - refund.$3,
            refund.$1,
          );
        }(),
    ];
  }

  Future<ReportResult> _daily(
    AppSession session,
    DateTime from,
    DateTime to,
    bool profit,
  ) async {
    final days = await _dailyRows(session, from, to);
    return ReportResult(
      kind: ReportKind.daily,
      columns: [
        const ReportColumn('Date', ColumnKind.text, flex: 2),
        const ReportColumn('Invoices', ColumnKind.integer),
        const ReportColumn('Discounts', ColumnKind.money),
        const ReportColumn('Refunds', ColumnKind.money),
        const ReportColumn('Tax', ColumnKind.money),
        const ReportColumn('Net sales', ColumnKind.money),
        if (profit) const ReportColumn('Gross profit', ColumnKind.money),
      ],
      rows: [
        for (final d in days)
          [d.$1, d.$2, d.$5, d.$7, d.$4, d.$3, if (profit) d.$3 - d.$4 - d.$6],
      ],
      chart: [for (final d in days) (d.$1, d.$3)],
      chartLabel: 'Net sales by day',
      footnote: profit ? _profitFootnote : null,
    );
  }

  Future<ReportResult> _products(
    AppSession session,
    DateTime from,
    DateTime to,
    bool profit,
  ) async {
    final rows = await _database.customSelect('''
      SELECT i.product_id AS product_id,
             i.product_name_snapshot AS name, i.sku_snapshot AS sku,
             SUM(i.qty) AS qty,
             SUM(i.line_total) AS total,
             SUM(i.tax_amount) AS tax,
             SUM(i.discount_amount) AS discount,
             SUM(i.qty * i.unit_cost) AS cost
      FROM sale_items i JOIN sales s ON s.id = i.sale_id
      WHERE $_completed
      GROUP BY i.product_id, i.product_name_snapshot, i.sku_snapshot
      ORDER BY total DESC
      LIMIT 1000
      ''', variables: _vars(session, from, to)).get();
    final returned = await _refundsBy(session, from, to, 'i.product_id');
    final data = [
      for (final row in rows)
        () {
          final r = returned[row.read<String>('product_id')];
          return (
            name: row.read<String>('name'),
            sku: row.read<String>('sku'),
            qty: row.read<double>('qty') - (r?.qty ?? 0),
            total: row.read<double>('total') - (r?.value ?? 0),
            tax: row.read<double>('tax') - (r?.tax ?? 0),
            discount: row.read<double>('discount'),
            cost: row.read<double>('cost') - (r?.cost ?? 0),
            returnedQty: r?.qty ?? 0,
          );
        }(),
    ];
    return ReportResult(
      kind: ReportKind.products,
      kpis: [
        ReportKpi('Products sold', data.length.toDouble(), ColumnKind.integer),
        ReportKpi(
          'Units sold',
          data.fold(0.0, (sum, item) => sum + item.qty),
          ColumnKind.quantity,
        ),
      ],
      columns: [
        const ReportColumn('Product', ColumnKind.text, flex: 3),
        const ReportColumn('SKU', ColumnKind.text, flex: 2),
        const ReportColumn('Net qty', ColumnKind.quantity),
        const ReportColumn('Returned', ColumnKind.quantity),
        const ReportColumn('Discounts', ColumnKind.money),
        const ReportColumn('Sales', ColumnKind.money),
        if (profit) const ReportColumn('Cost', ColumnKind.money),
        if (profit) const ReportColumn('Profit', ColumnKind.money),
        if (profit) const ReportColumn('Margin', ColumnKind.percent),
      ],
      rows: [
        for (final p in data)
          [
            p.name,
            p.sku,
            p.qty,
            p.returnedQty,
            p.discount,
            p.total,
            if (profit) p.cost,
            if (profit) p.total - p.tax - p.cost,
            if (profit)
              p.total - p.tax == 0
                  ? 0.0
                  : (p.total - p.tax - p.cost) / (p.total - p.tax) * 100,
          ],
      ],
      chart: [for (final p in data.take(10)) (p.name, p.total)],
      chartLabel: 'Top 10 products by sales',
      footnote: profit ? _profitFootnote : null,
    );
  }

  Future<ReportResult> _categories(
    AppSession session,
    DateTime from,
    DateTime to,
    bool profit,
  ) async {
    final rows = await _database.customSelect('''
      SELECT COALESCE(c.name, 'Uncategorized') AS name,
             SUM(i.qty) AS qty, SUM(i.line_total) AS total,
             SUM(i.tax_amount) AS tax, SUM(i.qty * i.unit_cost) AS cost
      FROM sale_items i
      JOIN sales s ON s.id = i.sale_id
      LEFT JOIN products p ON p.id = i.product_id
      LEFT JOIN categories c ON c.id = p.category_id
      WHERE $_completed
      GROUP BY COALESCE(c.name, 'Uncategorized')
      ORDER BY total DESC
      ''', variables: _vars(session, from, to)).get();
    final returned = await _refundsBy(
      session,
      from,
      to,
      "COALESCE(c.name, 'Uncategorized')",
      joins:
          'LEFT JOIN products p ON p.id = i.product_id '
          'LEFT JOIN categories c ON c.id = p.category_id',
    );
    final data = [
      for (final row in rows)
        () {
          final r = returned[row.read<String>('name')];
          return (
            name: row.read<String>('name'),
            qty: row.read<double>('qty') - (r?.qty ?? 0),
            total: row.read<double>('total') - (r?.value ?? 0),
            profit:
                row.read<double>('total') -
                row.read<double>('tax') -
                row.read<double>('cost') -
                ((r?.value ?? 0) - (r?.tax ?? 0) - (r?.cost ?? 0)),
          );
        }(),
    ]..sort((a, b) => b.total.compareTo(a.total));
    return ReportResult(
      kind: ReportKind.categories,
      columns: [
        const ReportColumn('Category', ColumnKind.text, flex: 3),
        const ReportColumn('Net qty', ColumnKind.quantity),
        const ReportColumn('Sales', ColumnKind.money),
        if (profit) const ReportColumn('Profit', ColumnKind.money),
      ],
      rows: [
        for (final c in data) [c.name, c.qty, c.total, if (profit) c.profit],
      ],
      chart: [for (final c in data.take(12)) (c.name, c.total)],
      chartLabel: 'Sales by category',
      footnote: profit ? _profitFootnote : null,
    );
  }

  Future<ReportResult> _cashiers(
    AppSession session,
    DateTime from,
    DateTime to,
  ) async {
    final rows = await _database.customSelect('''
      SELECT u.display_name AS name, COUNT(*) AS invoices,
             SUM(s.grand_total) AS total, SUM(s.discount_amount) AS discount
      FROM sales s JOIN users u ON u.id = s.user_id
      WHERE $_completed
      GROUP BY s.user_id, u.display_name
      ORDER BY total DESC
      ''', variables: _vars(session, from, to)).get();
    return ReportResult(
      kind: ReportKind.cashiers,
      columns: const [
        ReportColumn('Cashier', ColumnKind.text, flex: 3),
        ReportColumn('Invoices', ColumnKind.integer),
        ReportColumn('Discounts given', ColumnKind.money),
        ReportColumn('Average sale', ColumnKind.money),
        ReportColumn('Net sales', ColumnKind.money),
      ],
      rows: [
        for (final row in rows)
          [
            row.read<String>('name'),
            row.read<int>('invoices'),
            row.read<double>('discount'),
            row.read<double>('total') / row.read<int>('invoices'),
            row.read<double>('total'),
          ],
      ],
      chart: [
        for (final row in rows)
          (row.read<String>('name'), row.read<double>('total')),
      ],
      chartLabel: 'Net sales by cashier',
    );
  }

  Future<ReportResult> _payments(
    AppSession session,
    DateTime from,
    DateTime to,
  ) async {
    final rows = await _database.customSelect('''
      SELECT p.method AS method, COUNT(*) AS count, SUM(p.amount) AS amount
      FROM payments p JOIN sales s ON s.id = p.sale_id
      WHERE $_completed
      GROUP BY p.method ORDER BY amount DESC
      ''', variables: _vars(session, from, to)).get();
    final change = await _database
        .customSelect(
          'SELECT COALESCE(SUM(s.change_amount), 0.0) AS change FROM sales s WHERE $_completed',
          variables: _vars(session, from, to),
        )
        .getSingle();
    final cashOut = await _database.customSelect('''
      SELECT COALESCE(SUM(CASE WHEN type = 'pay_in' THEN amount ELSE 0 END), 0.0) AS pay_in,
             COALESCE(SUM(CASE WHEN type = 'pay_out' THEN amount ELSE 0 END), 0.0) AS pay_out
      FROM cash_transactions
      WHERE store_id = ?1 AND created_at >= ?2 AND created_at < ?3
      ''', variables: _vars(session, from, to)).getSingle();
    // Only money actually handed back; the part of a return that reduced an
    // unpaid credit balance is not a payment.
    final refundRows = await _database.customSelect('''
      SELECT r.method AS method, COUNT(*) AS count, SUM(r.amount - r.credit_applied) AS amount
      FROM sale_refunds r WHERE $_refundWhere AND r.amount - r.credit_applied > 0.004
      GROUP BY r.method ORDER BY amount DESC
      ''', variables: _vars(session, from, to)).get();
    final accountRows = await _database.customSelect('''
      SELECT cp.method AS method, COUNT(*) AS count, SUM(cp.amount) AS amount
      FROM customer_payments cp
      WHERE cp.store_id = ?1 AND cp.status = 'posted'
        AND cp.created_at >= ?2 AND cp.created_at < ?3
      GROUP BY cp.method ORDER BY amount DESC
      ''', variables: _vars(session, from, to)).get();
    final accountCash = accountRows
        .where((row) => row.read<String>('method') == 'cash')
        .fold(0.0, (sum, row) => sum + row.read<double>('amount'));
    final cashRefunds = refundRows
        .where((row) => row.read<String>('method') == 'cash')
        .fold(0.0, (sum, row) => sum + row.read<double>('amount'));
    // Payments store the tendered amount; change always comes from cash.
    double netOf(QueryRow row) => row.read<String>('method') == 'cash'
        ? row.read<double>('amount') - change.read<double>('change')
        : row.read<double>('amount');
    final cash =
        rows
            .where((row) => row.read<String>('method') == 'cash')
            .fold(0.0, (sum, row) => sum + row.read<double>('amount')) -
        cashRefunds;
    return ReportResult(
      kind: ReportKind.payments,
      kpis: [
        ReportKpi(
          'Net cash from sales',
          cash - change.read<double>('change'),
          ColumnKind.money,
          note: 'Cash tendered minus change and cash refunds',
        ),
        ReportKpi(
          'Account payments (cash)',
          accountCash,
          ColumnKind.money,
          note: 'Cash received against customer balances',
        ),
        ReportKpi('Pay-ins', cashOut.read<double>('pay_in'), ColumnKind.money),
        ReportKpi(
          'Pay-outs',
          cashOut.read<double>('pay_out'),
          ColumnKind.money,
        ),
      ],
      columns: const [
        ReportColumn('Method', ColumnKind.text, flex: 2),
        ReportColumn('Payments', ColumnKind.integer),
        ReportColumn('Amount received', ColumnKind.money),
      ],
      rows: [
        for (final row in rows)
          [
            row.read<String>('method').toUpperCase(),
            row.read<int>('count'),
            netOf(row),
          ],
        for (final row in accountRows)
          [
            'ACCOUNT PAYMENTS · ${row.read<String>('method').toUpperCase()}',
            row.read<int>('count'),
            row.read<double>('amount'),
          ],
        for (final row in refundRows)
          [
            'REFUNDS · ${row.read<String>('method').toUpperCase()}',
            row.read<int>('count'),
            -row.read<double>('amount'),
          ],
      ],
      chart: [
        for (final row in rows)
          (row.read<String>('method').toUpperCase(), netOf(row)),
      ],
      chartLabel: 'Amount by payment method',
    );
  }

  Future<ReportResult> _purchases(
    AppSession session,
    DateTime from,
    DateTime to,
  ) async {
    final rows = await _database.customSelect('''
      SELECT COALESCE(sp.name, 'No supplier') AS supplier,
             SUM(CASE WHEN p.status = 'received' THEN 1 ELSE 0 END) AS received_count,
             COALESCE(SUM(CASE WHEN p.status = 'received' THEN p.total ELSE 0 END), 0.0) AS received,
             COALESCE(SUM(CASE WHEN p.status = 'returned' THEN p.total ELSE 0 END), 0.0) AS returned
      FROM purchases p LEFT JOIN suppliers sp ON sp.id = p.supplier_id
      WHERE p.store_id = ?1 AND p.created_at >= ?2 AND p.created_at < ?3
      GROUP BY COALESCE(sp.name, 'No supplier')
      ORDER BY received DESC
      ''', variables: _vars(session, from, to)).get();
    final received = rows.fold(0.0, (s, r) => s + r.read<double>('received'));
    final returned = rows.fold(0.0, (s, r) => s + r.read<double>('returned'));
    return ReportResult(
      kind: ReportKind.purchases,
      kpis: [
        ReportKpi('Purchases', received, ColumnKind.money),
        ReportKpi('Supplier returns', returned, ColumnKind.money),
        ReportKpi('Net purchases', received - returned, ColumnKind.money),
      ],
      columns: const [
        ReportColumn('Supplier', ColumnKind.text, flex: 3),
        ReportColumn('Deliveries', ColumnKind.integer),
        ReportColumn('Received', ColumnKind.money),
        ReportColumn('Returned', ColumnKind.money),
        ReportColumn('Net', ColumnKind.money),
      ],
      rows: [
        for (final row in rows)
          [
            row.read<String>('supplier'),
            row.read<int>('received_count'),
            row.read<double>('received'),
            row.read<double>('returned'),
            row.read<double>('received') - row.read<double>('returned'),
          ],
      ],
      chart: [
        for (final row in rows.take(10))
          (row.read<String>('supplier'), row.read<double>('received')),
      ],
      chartLabel: 'Purchases by supplier',
    );
  }

  Future<ReportResult> _stock(AppSession session) async {
    final showCost = session.can(Permissions.inventoryViewCost);
    final rows = await _database
        .customSelect(
          '''
      SELECT p.name, p.sku, COALESCE(c.name, 'Uncategorized') AS category,
             ps.stock_qty, ps.reorder_level, p.cost_price,
             COALESCE(ps.custom_sale_price, p.sale_price) AS price
      FROM product_stores ps
      JOIN products p ON p.id = ps.product_id
      LEFT JOIN categories c ON c.id = p.category_id
      WHERE ps.store_id = ?1 AND p.track_inventory = 1 AND p.is_active = 1
      ORDER BY p.name COLLATE NOCASE
      ''',
          variables: [Variable.withString(session.store.id)],
        )
        .get();
    double positive(QueryRow row) {
      final value = row.read<double>('stock_qty');
      return value > 0 ? value : 0;
    }

    final costValue = rows.fold(
      0.0,
      (s, r) => s + positive(r) * r.read<double>('cost_price'),
    );
    final retailValue = rows.fold(
      0.0,
      (s, r) => s + positive(r) * r.read<double>('price'),
    );
    final byCategory = <String, double>{};
    for (final row in rows) {
      final category = row.read<String>('category');
      byCategory[category] =
          (byCategory[category] ?? 0) +
          positive(row) *
              (showCost
                  ? row.read<double>('cost_price')
                  : row.read<double>('price'));
    }
    final chart = byCategory.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return ReportResult(
      kind: ReportKind.stock,
      kpis: [
        ReportKpi('Products', rows.length.toDouble(), ColumnKind.integer),
        if (showCost) ReportKpi('Value at cost', costValue, ColumnKind.money),
        ReportKpi('Value at retail', retailValue, ColumnKind.money),
        if (showCost)
          ReportKpi(
            'Potential margin',
            retailValue - costValue,
            ColumnKind.money,
          ),
      ],
      columns: [
        const ReportColumn('Product', ColumnKind.text, flex: 3),
        const ReportColumn('SKU', ColumnKind.text, flex: 2),
        const ReportColumn('Category', ColumnKind.text, flex: 2),
        const ReportColumn('In stock', ColumnKind.quantity),
        const ReportColumn('Reorder at', ColumnKind.quantity),
        if (showCost) const ReportColumn('Cost value', ColumnKind.money),
        const ReportColumn('Retail value', ColumnKind.money),
      ],
      rows: [
        for (final row in rows)
          [
            row.read<String>('name'),
            row.read<String>('sku'),
            row.read<String>('category'),
            row.read<double>('stock_qty'),
            row.read<double>('reorder_level'),
            if (showCost) positive(row) * row.read<double>('cost_price'),
            positive(row) * row.read<double>('price'),
          ],
      ],
      chart: [for (final entry in chart.take(12)) (entry.key, entry.value)],
      chartLabel: showCost
          ? 'Stock value at cost by category'
          : 'Stock value at retail by category',
    );
  }
}
