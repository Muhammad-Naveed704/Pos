import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/database_provider.dart';
import '../../auth/application/session_controller.dart';

/// Dashboard period: the KPI window and the one it is compared with.
enum DashPeriod {
  today('Today', 1, 'vs yesterday'),
  week('7 days', 7, 'vs previous 7 days'),
  month('30 days', 30, 'vs previous 30 days');

  const DashPeriod(this.label, this.days, this.comparison);
  final String label;
  final int days;
  final String comparison;
}

class DayFigures {
  const DayFigures(
    this.day, {
    this.sales = 0,
    this.invoices = 0,
    this.discounts = 0,
    this.cash = 0,
  });
  final DateTime day;

  /// Net of refunds made that day; voided sales excluded.
  final double sales;
  final int invoices;
  final double discounts;

  /// Cash kept: tendered − change − cash refunds + account payments.
  final double cash;
}

class Kpi {
  const Kpi(this.value, this.previous, this.series);
  final double value;
  final double previous;

  /// One point per day for the sparkline (oldest first).
  final List<double> series;

  /// Percentage change, or null when there is nothing to compare with.
  double? get change =>
      previous == 0 ? null : (value - previous) / previous.abs() * 100;
}

class RankedProduct {
  const RankedProduct({
    required this.name,
    required this.sku,
    required this.quantity,
    required this.revenue,
    this.imagePath,
  });
  final String name;
  final String sku;
  final double quantity;
  final double revenue;
  final String? imagePath;
}

class RecentSale {
  const RecentSale({
    required this.invoice,
    required this.time,
    required this.customer,
    required this.items,
    required this.total,
    required this.methods,
    required this.paymentStatus,
    required this.saleStatus,
  });
  final String invoice;
  final DateTime time;
  final String? customer;
  final double items;
  final double total;
  final List<String> methods;
  final String paymentStatus;
  final String saleStatus;
}

class InventoryHealth {
  const InventoryHealth({
    required this.tracked,
    required this.active,
    required this.inStock,
    required this.low,
    required this.out,
  });
  final int tracked;
  final int active;
  final int inStock;
  final int low;
  final int out;
}

class DashboardInsights {
  const DashboardInsights({
    required this.period,
    required this.sales,
    required this.invoices,
    required this.cash,
    required this.discounts,
    required this.days,
    required this.hours,
    required this.topProducts,
    required this.paymentMix,
    required this.recentSales,
    required this.inventory,
    required this.customers,
  });
  final DashPeriod period;
  final Kpi sales;
  final Kpi invoices;
  final Kpi cash;
  final Kpi discounts;

  /// Daily figures for the chart (7 days, or the period when longer).
  final List<DayFigures> days;

  /// Today by hour: (sales, invoices).
  final List<(double, int)> hours;
  final List<RankedProduct> topProducts;

  /// Amount by method for the period (cash net of change).
  final Map<String, double> paymentMix;
  final List<RecentSale> recentSales;
  final InventoryHealth inventory;
  final int customers;

  double get averageSale =>
      invoices.value == 0 ? 0 : sales.value / invoices.value;
}

String _key(DateTime day) =>
    '${day.year.toString().padLeft(4, '0')}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';

// Dates are unix seconds: SQL date functions need 'unixepoch'.
const _day = "date(created_at, 'unixepoch', 'localtime')";

final dashboardInsightsProvider = FutureProvider.autoDispose
    .family<DashboardInsights, DashPeriod>((ref, period) async {
      final database = ref.watch(databaseProvider);
      final session = ref.watch(activeSessionProvider);
      if (session == null) throw StateError('Authentication required.');
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      // Current + previous window, and at least 7 days for the chart.
      final span = period.days * 2 > 7 ? period.days * 2 : 7;
      final from = today.subtract(Duration(days: span - 1));
      final periodStart = today.subtract(Duration(days: period.days - 1));
      final vars = [
        Variable.withString(session.store.id),
        Variable.withDateTime(from),
      ];

      final sales = await database.customSelect('''
        SELECT $_day AS d, SUM(grand_total) AS total, COUNT(*) AS n,
               SUM(discount_amount) AS disc, SUM(change_amount) AS chg
        FROM sales WHERE store_id = ?1 AND sale_status <> 'voided' AND created_at >= ?2
        GROUP BY d
        ''', variables: vars).get();
      final cashIn = await database.customSelect('''
        SELECT date(p.created_at, 'unixepoch', 'localtime') AS d, SUM(p.amount) AS amount
        FROM payments p JOIN sales s ON s.id = p.sale_id
        WHERE s.store_id = ?1 AND s.sale_status <> 'voided' AND p.method = 'cash'
          AND p.created_at >= ?2
        GROUP BY d
        ''', variables: vars).get();
      final refunds = await database.customSelect('''
        SELECT $_day AS d, SUM(amount) AS amount,
               SUM(CASE WHEN method = 'cash' THEN amount - credit_applied ELSE 0 END) AS cash
        FROM sale_refunds WHERE store_id = ?1 AND kind = 'refund' AND created_at >= ?2
        GROUP BY d
        ''', variables: vars).get();
      final account = await database.customSelect('''
        SELECT $_day AS d,
               SUM(CASE WHEN type = 'customer_payment' THEN amount ELSE -amount END) AS amount
        FROM cash_transactions
        WHERE store_id = ?1 AND type IN ('customer_payment', 'customer_refund') AND created_at >= ?2
        GROUP BY d
        ''', variables: vars).get();

      Map<String, QueryRow> byDay(List<QueryRow> rows) => {
        for (final row in rows) row.read<String>('d'): row,
      };
      final s = byDay(sales), c = byDay(cashIn), r = byDay(refunds);
      final a = byDay(account);
      final all = <DayFigures>[
        for (var offset = span - 1; offset >= 0; offset--)
          () {
            final day = today.subtract(Duration(days: offset));
            final k = _key(day);
            final sale = s[k];
            final refund = r[k];
            return DayFigures(
              day,
              sales:
                  (sale?.read<double>('total') ?? 0) -
                  (refund?.read<double>('amount') ?? 0),
              invoices: sale?.read<int>('n') ?? 0,
              discounts: sale?.read<double>('disc') ?? 0,
              cash:
                  (c[k]?.read<double>('amount') ?? 0) -
                  (sale?.read<double>('chg') ?? 0) -
                  (refund?.read<double>('cash') ?? 0) +
                  (a[k]?.read<double>('amount') ?? 0),
            );
          }(),
      ];
      final current = all.sublist(all.length - period.days);
      final previous = all.sublist(
        all.length - period.days * 2 < 0 ? 0 : all.length - period.days * 2,
        all.length - period.days,
      );
      Kpi kpi(double Function(DayFigures) pick) {
        // Sparkline: the period, but at least the last 7 days.
        final series = all.sublist(
          all.length - (period.days < 7 ? 7 : period.days),
        );
        return Kpi(
          current.fold(0.0, (sum, d) => sum + pick(d)),
          previous.fold(0.0, (sum, d) => sum + pick(d)),
          [for (final d in series) pick(d)],
        );
      }

      final hourRows = await database
          .customSelect(
            '''
        SELECT CAST(strftime('%H', created_at, 'unixepoch', 'localtime') AS INTEGER) AS h,
               SUM(grand_total) AS total, COUNT(*) AS n
        FROM sales WHERE store_id = ?1 AND sale_status <> 'voided' AND created_at >= ?2
        GROUP BY h
        ''',
            variables: [vars.first, Variable.withDateTime(today)],
          )
          .get();
      final hours = List<(double, int)>.filled(24, (0.0, 0));
      for (final row in hourRows) {
        hours[row.read<int>('h')] = (
          row.read<double>('total'),
          row.read<int>('n'),
        );
      }

      final periodVars = [vars.first, Variable.withDateTime(periodStart)];
      final top = await database.customSelect('''
        SELECT si.product_name_snapshot AS name, si.sku_snapshot AS sku,
               p.image_path AS image, SUM(si.qty) AS qty, SUM(si.line_total) AS revenue
        FROM sale_items si
        JOIN sales s ON s.id = si.sale_id
        LEFT JOIN products p ON p.id = si.product_id
        WHERE s.store_id = ?1 AND s.sale_status <> 'voided' AND s.created_at >= ?2
        GROUP BY si.product_id
        ORDER BY revenue DESC
        LIMIT 5
        ''', variables: periodVars).get();

      final mix = await database.customSelect('''
        SELECT p.method AS method, SUM(p.amount) AS total
        FROM payments p JOIN sales s ON s.id = p.sale_id
        WHERE s.store_id = ?1 AND s.sale_status <> 'voided' AND p.created_at >= ?2
        GROUP BY p.method
        ''', variables: periodVars).get();
      final change = current.fold(
        0.0,
        (sum, d) => sum + (s[_key(d.day)]?.read<double>('chg') ?? 0),
      );

      final recent = await database
          .customSelect(
            '''
        SELECT s.invoice_number, s.created_at, s.grand_total, s.payment_status,
               s.sale_status, c.name AS customer,
               (SELECT SUM(qty) FROM sale_items i WHERE i.sale_id = s.id) AS items,
               (SELECT GROUP_CONCAT(DISTINCT method) FROM payments p WHERE p.sale_id = s.id) AS methods
        FROM sales s LEFT JOIN customers c ON c.id = s.customer_id
        WHERE s.store_id = ?1
        ORDER BY s.created_at DESC, s.rowid DESC
        LIMIT 6
        ''',
            variables: [vars.first],
          )
          .get();

      final stock = await database
          .customSelect(
            '''
        SELECT COUNT(*) AS tracked,
               SUM(CASE WHEN ps.is_available = 1 AND p.is_active = 1 THEN 1 ELSE 0 END) AS active,
               SUM(CASE WHEN ps.stock_qty > ps.reorder_level THEN 1 ELSE 0 END) AS in_stock,
               SUM(CASE WHEN ps.stock_qty > 0 AND ps.stock_qty <= ps.reorder_level THEN 1 ELSE 0 END) AS low,
               SUM(CASE WHEN ps.stock_qty <= 0 THEN 1 ELSE 0 END) AS out_of_stock
        FROM product_stores ps JOIN products p ON p.id = ps.product_id
        WHERE ps.store_id = ?1 AND p.track_inventory = 1 AND p.is_active = 1
          AND ps.is_available = 1
        ''',
            variables: [vars.first],
          )
          .getSingle();
      final customers = await database
          .customSelect(
            'SELECT COUNT(*) AS n FROM customers WHERE is_active = 1',
          )
          .getSingle();

      return DashboardInsights(
        period: period,
        sales: kpi((d) => d.sales),
        invoices: kpi((d) => d.invoices.toDouble()),
        cash: kpi((d) => d.cash),
        discounts: kpi((d) => d.discounts),
        days: all.sublist(all.length - (period.days < 7 ? 7 : period.days)),
        hours: hours,
        topProducts: [
          for (final row in top)
            RankedProduct(
              name: row.read<String>('name'),
              sku: row.read<String>('sku'),
              imagePath: row.readNullable<String>('image'),
              quantity: row.read<double>('qty'),
              revenue: row.read<double>('revenue'),
            ),
        ],
        paymentMix: {
          for (final row in mix)
            row.read<String>('method'): row.read<String>('method') == 'cash'
                ? row.read<double>('total') - change
                : row.read<double>('total'),
        },
        recentSales: [
          for (final row in recent)
            RecentSale(
              invoice: row.read<String>('invoice_number'),
              time: row.read<DateTime>('created_at'),
              customer: row.readNullable<String>('customer'),
              items: row.readNullable<double>('items') ?? 0,
              total: row.read<double>('grand_total'),
              methods: (row.readNullable<String>('methods') ?? '')
                  .split(',')
                  .where((m) => m.isNotEmpty)
                  .toList(),
              paymentStatus: row.read<String>('payment_status'),
              saleStatus: row.read<String>('sale_status'),
            ),
        ],
        inventory: InventoryHealth(
          tracked: stock.read<int>('tracked'),
          active: stock.readNullable<int>('active') ?? 0,
          inStock: stock.readNullable<int>('in_stock') ?? 0,
          low: stock.readNullable<int>('low') ?? 0,
          out: stock.readNullable<int>('out_of_stock') ?? 0,
        ),
        customers: customers.read<int>('n'),
      );
    });
