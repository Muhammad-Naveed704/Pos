import 'package:drift/drift.dart';
import 'package:flutter/material.dart' show DateTimeRange, IconData, Icons;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/database_provider.dart';
import '../../auth/domain/app_session.dart';
import '../../auth/domain/permission_guard.dart';
import '../../auth/domain/permissions.dart';

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
  stock('Stock valuation', Icons.warehouse_outlined, Permissions.inventoryView);

  const ReportKind(this.label, this.icon, this.permission);
  final String label;
  final IconData icon;
  final String permission;

  /// Whether the report depends on the selected date range.
  bool get usesDates => this != stock;
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
    DateTimeRange range,
  ) async {
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
    };
  }

  List<Variable> _vars(AppSession session, DateTime from, DateTime to) => [
    Variable.withString(session.store.id),
    Variable.withDateTime(from),
    Variable.withDateTime(to),
  ];

  static const _completed =
      "s.store_id = ?1 AND s.sale_status = 'completed' AND s.created_at >= ?2 AND s.created_at < ?3";

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
    final net = row.read<double>('net');
    final tax = row.read<double>('tax');
    final cost = row.read<double>('cost');
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
        ReportKpi('Discounts', row.read<double>('discounts'), ColumnKind.money),
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
        ['Tax', tax],
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

  /// (label, invoices, net, tax, discount, cost)
  Future<List<(String, int, double, double, double, double)>> _dailyRows(
    AppSession session,
    DateTime from,
    DateTime to,
  ) async {
    final rows = await _database.customSelect('''
      SELECT date(s.created_at, 'unixepoch', 'localtime') AS day,
             COUNT(*) AS invoices,
             SUM(s.grand_total) AS net,
             SUM(s.tax_amount) AS tax,
             SUM(s.discount_amount) AS discount,
             COALESCE((SELECT SUM(i.qty * i.unit_cost) FROM sale_items i JOIN sales x ON x.id = i.sale_id
               WHERE x.store_id = ?1 AND x.sale_status = 'completed'
                 AND date(x.created_at, 'unixepoch', 'localtime') = date(s.created_at, 'unixepoch', 'localtime')), 0.0) AS cost
      FROM sales s WHERE $_completed
      GROUP BY day ORDER BY day
      ''', variables: _vars(session, from, to)).get();
    return [
      for (final row in rows)
        (
          row.read<String>('day'),
          row.read<int>('invoices'),
          row.read<double>('net'),
          row.read<double>('tax'),
          row.read<double>('discount'),
          row.read<double>('cost'),
        ),
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
        const ReportColumn('Tax', ColumnKind.money),
        const ReportColumn('Net sales', ColumnKind.money),
        if (profit) const ReportColumn('Gross profit', ColumnKind.money),
      ],
      rows: [
        for (final d in days)
          [d.$1, d.$2, d.$5, d.$4, d.$3, if (profit) d.$3 - d.$4 - d.$6],
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
      SELECT i.product_name_snapshot AS name, i.sku_snapshot AS sku,
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
    final data = [
      for (final row in rows)
        (
          name: row.read<String>('name'),
          sku: row.read<String>('sku'),
          qty: row.read<double>('qty'),
          total: row.read<double>('total'),
          tax: row.read<double>('tax'),
          discount: row.read<double>('discount'),
          cost: row.read<double>('cost'),
        ),
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
        const ReportColumn('Qty', ColumnKind.quantity),
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
    return ReportResult(
      kind: ReportKind.categories,
      columns: [
        const ReportColumn('Category', ColumnKind.text, flex: 3),
        const ReportColumn('Qty', ColumnKind.quantity),
        const ReportColumn('Sales', ColumnKind.money),
        if (profit) const ReportColumn('Profit', ColumnKind.money),
      ],
      rows: [
        for (final row in rows)
          [
            row.read<String>('name'),
            row.read<double>('qty'),
            row.read<double>('total'),
            if (profit)
              row.read<double>('total') -
                  row.read<double>('tax') -
                  row.read<double>('cost'),
          ],
      ],
      chart: [
        for (final row in rows.take(12))
          (row.read<String>('name'), row.read<double>('total')),
      ],
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
    final cash = rows
        .where((row) => row.read<String>('method') == 'cash')
        .fold(0.0, (sum, row) => sum + row.read<double>('amount'));
    return ReportResult(
      kind: ReportKind.payments,
      kpis: [
        ReportKpi(
          'Net cash from sales',
          cash - change.read<double>('change'),
          ColumnKind.money,
          note: 'Cash tendered minus change',
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
            row.read<double>('amount'),
          ],
      ],
      chart: [
        for (final row in rows)
          (
            row.read<String>('method').toUpperCase(),
            row.read<double>('amount'),
          ),
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
