import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/database_provider.dart';
import '../../auth/application/session_controller.dart';

import 'package:drift/drift.dart';

class DashboardMetrics {
  const DashboardMetrics({
    required this.sales,
    required this.invoices,
    required this.customers,
    required this.discounts,
    required this.cashCollected,
    required this.lowStock,
    required this.outOfStock,
  });

  final double sales;
  final int invoices;
  final int customers;
  final double discounts;
  final double cashCollected;
  final int lowStock;
  final int outOfStock;
}

final dashboardMetricsProvider = FutureProvider<DashboardMetrics>((ref) async {
  final database = ref.watch(databaseProvider);
  final session = ref.watch(activeSessionProvider);
  if (session == null) throw StateError('Authentication required.');
  final row = await database.customSelect(
    '''
    SELECT
      COALESCE((SELECT SUM(grand_total) FROM sales
        WHERE store_id = ? AND sale_status = 'completed' AND date(created_at, 'localtime') = date('now', 'localtime')), 0.0) AS sales,
      (SELECT COUNT(*) FROM sales
        WHERE store_id = ? AND sale_status = 'completed' AND date(created_at, 'localtime') = date('now', 'localtime')) AS invoices,
      (SELECT COUNT(*) FROM customers WHERE is_active = 1) AS customers,
      COALESCE((SELECT SUM(discount_amount) FROM sales
        WHERE store_id = ? AND sale_status = 'completed' AND date(created_at, 'localtime') = date('now', 'localtime')), 0.0) AS discounts,
      COALESCE((SELECT SUM(amount) FROM payments
        JOIN sales ps ON ps.id = payments.sale_id
        WHERE ps.store_id = ? AND method = 'cash' AND date(payments.created_at, 'localtime') = date('now', 'localtime')), 0.0) AS cash_collected,
      (SELECT COUNT(*) FROM product_stores
        WHERE store_id = ? AND is_available = 1 AND stock_qty > 0 AND stock_qty <= reorder_level) AS low_stock,
      (SELECT COUNT(*) FROM product_stores
        WHERE store_id = ? AND is_available = 1 AND stock_qty <= 0) AS out_of_stock
  ''',
    variables: List.generate(6, (_) => Variable.withString(session.store.id)),
  ).getSingle();
  return DashboardMetrics(
    sales: row.read<double>('sales'),
    invoices: row.read<int>('invoices'),
    customers: row.read<int>('customers'),
    discounts: row.read<double>('discounts'),
    cashCollected: row.read<double>('cash_collected'),
    lowStock: row.read<int>('low_stock'),
    outOfStock: row.read<int>('out_of_stock'),
  );
});
