import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/database_provider.dart';
import '../../auth/domain/app_session.dart';
import '../../auth/domain/permission_guard.dart';
import '../../auth/domain/permissions.dart';

final salesRepositoryProvider = Provider<SalesRepository>(
  (ref) => SalesRepository(ref.watch(databaseProvider)),
);

class SaleSummary {
  const SaleSummary({
    required this.sale,
    required this.cashierName,
    this.customerName,
    this.paymentMethods = '',
  });
  final Sale sale;
  final String cashierName;
  final String? customerName;
  final String paymentMethods;
}

class SaleDetails {
  const SaleDetails({
    required this.summary,
    required this.store,
    required this.items,
    required this.payments,
  });
  final SaleSummary summary;
  final Store store;
  final List<SaleItem> items;
  final List<Payment> payments;
}

class SalesFilterChoice {
  const SalesFilterChoice(this.id, this.label);
  final String id;
  final String label;
}

class SalesFilterOptions {
  const SalesFilterOptions({required this.customers, required this.cashiers});
  final List<SalesFilterChoice> customers;
  final List<SalesFilterChoice> cashiers;
}

class SalesRepository {
  SalesRepository(this._database);
  final AppDatabase _database;

  Future<SalesFilterOptions> filterOptions(AppSession session) async {
    PermissionGuard.require(session, Permissions.posView);
    final customerRows = await _database
        .customSelect(
          '''SELECT DISTINCT c.id, c.name AS label
          FROM sales s JOIN customers c ON c.id = s.customer_id
          WHERE s.store_id = ? ORDER BY c.name''',
          variables: [Variable.withString(session.store.id)],
          readsFrom: {_database.sales, _database.customers},
        )
        .get();
    final cashierRows = await _database
        .customSelect(
          '''SELECT DISTINCT u.id, u.display_name AS label
          FROM sales s JOIN users u ON u.id = s.user_id
          WHERE s.store_id = ? ORDER BY u.display_name''',
          variables: [Variable.withString(session.store.id)],
          readsFrom: {_database.sales, _database.users},
        )
        .get();
    List<SalesFilterChoice> map(List<QueryRow> rows) => rows
        .map(
          (row) => SalesFilterChoice(
            row.read<String>('id'),
            row.read<String>('label'),
          ),
        )
        .toList();
    return SalesFilterOptions(
      customers: map(customerRows),
      cashiers: map(cashierRows),
    );
  }

  Future<List<SaleSummary>> search({
    required AppSession session,
    String invoice = '',
    String? customerId,
    String? cashierId,
    String? paymentMethod,
    String? status,
    String? saleId,
    DateTime? from,
    DateTime? to,
    int limit = 100,
    int offset = 0,
  }) async {
    PermissionGuard.require(session, Permissions.posView);
    final variables = <Variable<Object>>[Variable.withString(session.store.id)];
    final filters = <String>['s.store_id = ?'];
    if (invoice.trim().isNotEmpty) {
      filters.add('s.invoice_number LIKE ?');
      variables.add(Variable.withString('%${invoice.trim()}%'));
    }
    if (customerId != null) {
      filters.add('s.customer_id = ?');
      variables.add(Variable.withString(customerId));
    }
    if (cashierId != null) {
      filters.add('s.user_id = ?');
      variables.add(Variable.withString(cashierId));
    }
    if (saleId != null) {
      filters.add('s.id = ?');
      variables.add(Variable.withString(saleId));
    }
    if (status != null) {
      filters.add('s.sale_status = ?');
      variables.add(Variable.withString(status));
    }
    if (paymentMethod != null) {
      filters.add(
        'EXISTS (SELECT 1 FROM payments p2 WHERE p2.sale_id = s.id AND p2.method = ?)',
      );
      variables.add(Variable.withString(paymentMethod));
    }
    if (from != null) {
      filters.add('s.created_at >= ?');
      variables.add(Variable.withDateTime(from));
    }
    if (to != null) {
      filters.add('s.created_at < ?');
      variables.add(Variable.withDateTime(to));
    }
    variables
      ..add(Variable.withInt(limit))
      ..add(Variable.withInt(offset));
    final rows = await _database
        .customSelect(
          '''SELECT s.*, u.display_name AS cashier_name, c.name AS customer_name,
         GROUP_CONCAT(DISTINCT p.method) AS payment_methods
         FROM sales s
         JOIN users u ON u.id = s.user_id
         LEFT JOIN customers c ON c.id = s.customer_id
         LEFT JOIN payments p ON p.sale_id = s.id
         WHERE ${filters.join(' AND ')}
         GROUP BY s.id
         ORDER BY s.created_at DESC, s.rowid DESC
         LIMIT ? OFFSET ?''',
          variables: variables,
          readsFrom: {
            _database.sales,
            _database.users,
            _database.customers,
            _database.payments,
          },
        )
        .get();
    return rows
        .map(
          (row) => SaleSummary(
            sale: _database.sales.map(row.data),
            cashierName: row.read<String>('cashier_name'),
            customerName: row.readNullable<String>('customer_name'),
            paymentMethods: row.readNullable<String>('payment_methods') ?? '',
          ),
        )
        .toList();
  }

  Future<SaleDetails> details(AppSession session, String saleId) async {
    final matches = await search(session: session, saleId: saleId, limit: 1);
    if (matches.isEmpty) {
      throw StateError('Sale not found in the active store.');
    }
    final summary = matches.single;
    final store = await (_database.select(
      _database.stores,
    )..where((row) => row.id.equals(summary.sale.storeId))).getSingle();
    final items = await (_database.select(
      _database.saleItems,
    )..where((row) => row.saleId.equals(saleId))).get();
    final payments = await (_database.select(
      _database.payments,
    )..where((row) => row.saleId.equals(saleId))).get();
    return SaleDetails(
      summary: summary,
      store: store,
      items: items,
      payments: payments,
    );
  }
}
