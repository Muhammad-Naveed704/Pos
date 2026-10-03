import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/database_provider.dart';
import '../../auth/application/session_controller.dart';

class TopProduct {
  const TopProduct(this.name, this.quantity, this.revenue);
  final String name;
  final double quantity;
  final double revenue;
}

class DashboardMetrics {
  const DashboardMetrics({
    required this.sales,
    required this.invoices,
    required this.customers,
    required this.discounts,
    required this.cashCollected,
    required this.lowStock,
    required this.outOfStock,
    this.yesterdaySales = 0,
    this.hourly = const [],
    this.week = const [],
    this.topProducts = const [],
    this.paymentMix = const {},
  });

  final double sales;
  final int invoices;
  final int customers;
  final double discounts;
  final double cashCollected;
  final int lowStock;
  final int outOfStock;
  final double yesterdaySales;

  /// 24 buckets of today's completed sales totals, by local hour.
  final List<double> hourly;

  /// Last seven days oldest → newest, as (day, total).
  final List<(DateTime, double)> week;
  final List<TopProduct> topProducts;

  /// Today's tender totals by payment method.
  final Map<String, double> paymentMix;

  double get averageSale => invoices == 0 ? 0 : sales / invoices;
}

// Drift stores DateTime as unix seconds, so SQL date functions need the
// 'unixepoch' modifier before 'localtime'.
final dashboardMetricsProvider = FutureProvider.autoDispose<DashboardMetrics>((
  ref,
) async {
  final database = ref.watch(databaseProvider);
  final session = ref.watch(activeSessionProvider);
  if (session == null) throw StateError('Authentication required.');
  final store = Variable.withString(session.store.id);
  const today =
      "date(created_at, 'unixepoch', 'localtime') = date('now', 'localtime')";
  final row = await database
      .customSelect(
        '''
    SELECT
      COALESCE((SELECT SUM(grand_total) FROM sales
        WHERE store_id = ?1 AND sale_status <> 'voided' AND $today), 0.0) AS sales,
      COALESCE((SELECT SUM(grand_total) FROM sales
        WHERE store_id = ?1 AND sale_status <> 'voided'
          AND date(created_at, 'unixepoch', 'localtime') = date('now', 'localtime', '-1 day')), 0.0) AS yesterday,
      (SELECT COUNT(*) FROM sales
        WHERE store_id = ?1 AND sale_status <> 'voided' AND $today) AS invoices,
      (SELECT COUNT(*) FROM customers WHERE is_active = 1) AS customers,
      COALESCE((SELECT SUM(discount_amount) FROM sales
        WHERE store_id = ?1 AND sale_status <> 'voided' AND $today), 0.0) AS discounts,
      -- Net cash in the drawer: cash tendered minus change handed back.
      COALESCE((SELECT SUM(payments.amount) FROM payments
        JOIN sales ps ON ps.id = payments.sale_id
        WHERE ps.store_id = ?1 AND ps.sale_status <> 'voided' AND payments.method = 'cash'
          AND date(payments.created_at, 'unixepoch', 'localtime') = date('now', 'localtime')), 0.0)
      - COALESCE((SELECT SUM(change_amount) FROM sales
        WHERE store_id = ?1 AND sale_status <> 'voided' AND $today), 0.0) AS cash_collected,
      COALESCE((SELECT SUM(change_amount) FROM sales
        WHERE store_id = ?1 AND sale_status <> 'voided' AND $today), 0.0) AS change_today,
      COALESCE((SELECT SUM(amount) FROM sale_refunds
        WHERE store_id = ?1 AND kind = 'refund' AND date(created_at, 'unixepoch', 'localtime') = date('now', 'localtime')), 0.0) AS refunds,
      COALESCE((SELECT SUM(amount - credit_applied) FROM sale_refunds
        WHERE store_id = ?1 AND kind = 'refund' AND method = 'cash' AND date(created_at, 'unixepoch', 'localtime') = date('now', 'localtime')), 0.0) AS cash_refunds,
      -- Cash received today against customer accounts, net of reversals.
      COALESCE((SELECT SUM(CASE WHEN type = 'customer_payment' THEN amount ELSE -amount END)
        FROM cash_transactions
        WHERE store_id = ?1 AND type IN ('customer_payment', 'customer_refund') AND $today), 0.0) AS account_cash,
      (SELECT COUNT(*) FROM product_stores
        WHERE store_id = ?1 AND is_available = 1 AND stock_qty > 0 AND stock_qty <= reorder_level) AS low_stock,
      (SELECT COUNT(*) FROM product_stores
        WHERE store_id = ?1 AND is_available = 1 AND stock_qty <= 0) AS out_of_stock
  ''',
        variables: [store],
      )
      .getSingle();

  final hourlyRows = await database
      .customSelect(
        '''
    SELECT CAST(strftime('%H', created_at, 'unixepoch', 'localtime') AS INTEGER) AS hour,
           SUM(grand_total) AS total
    FROM sales
    WHERE store_id = ?1 AND sale_status <> 'voided' AND $today
    GROUP BY hour
  ''',
        variables: [store],
      )
      .get();
  final hourly = List<double>.filled(24, 0);
  for (final item in hourlyRows) {
    hourly[item.read<int>('hour')] = item.read<double>('total');
  }

  final weekRows = await database
      .customSelect(
        '''
    SELECT date(created_at, 'unixepoch', 'localtime') AS day, SUM(grand_total) AS total
    FROM sales
    WHERE store_id = ?1 AND sale_status <> 'voided'
      AND date(created_at, 'unixepoch', 'localtime') >= date('now', 'localtime', '-6 day')
    GROUP BY day
  ''',
        variables: [store],
      )
      .get();
  final byDay = {
    for (final item in weekRows)
      item.read<String>('day'): item.read<double>('total'),
  };
  final now = DateTime.now();
  final week = [
    for (var offset = 6; offset >= 0; offset--)
      () {
        final day = DateTime(now.year, now.month, now.day - offset);
        final key =
            '${day.year.toString().padLeft(4, '0')}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';
        return (day, byDay[key] ?? 0.0);
      }(),
  ];

  final topRows = await database
      .customSelect(
        '''
    SELECT si.product_name_snapshot AS name,
           SUM(si.qty) AS qty,
           SUM(si.line_total) AS revenue
    FROM sale_items si
    JOIN sales s ON s.id = si.sale_id
    WHERE s.store_id = ?1 AND s.sale_status <> 'voided'
      AND date(s.created_at, 'unixepoch', 'localtime') >= date('now', 'localtime', '-6 day')
    GROUP BY si.product_id, si.product_name_snapshot
    ORDER BY revenue DESC
    LIMIT 5
  ''',
        variables: [store],
      )
      .get();

  final mixRows = await database
      .customSelect(
        '''
    SELECT p.method AS method, SUM(p.amount) AS total
    FROM payments p
    JOIN sales s ON s.id = p.sale_id
    WHERE s.store_id = ?1 AND s.sale_status <> 'voided'
      AND date(p.created_at, 'unixepoch', 'localtime') = date('now', 'localtime')
    GROUP BY p.method
  ''',
        variables: [store],
      )
      .get();

  return DashboardMetrics(
    sales: row.read<double>('sales') - row.read<double>('refunds'),
    yesterdaySales: row.read<double>('yesterday'),
    invoices: row.read<int>('invoices'),
    customers: row.read<int>('customers'),
    discounts: row.read<double>('discounts'),
    cashCollected:
        row.read<double>('cash_collected') -
        row.read<double>('cash_refunds') +
        row.read<double>('account_cash'),
    lowStock: row.read<int>('low_stock'),
    outOfStock: row.read<int>('out_of_stock'),
    hourly: hourly,
    week: week,
    topProducts: [
      for (final item in topRows)
        TopProduct(
          item.read<String>('name'),
          item.read<double>('qty'),
          item.read<double>('revenue'),
        ),
    ],
    // Payments store the amount tendered; change is handed back in cash.
    paymentMix: {
      for (final item in mixRows)
        item.read<String>('method'): item.read<String>('method') == 'cash'
            ? item.read<double>('total') - row.read<double>('change_today')
            : item.read<double>('total'),
    },
  );
});
