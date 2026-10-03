import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/database_provider.dart';
import '../../auth/domain/app_session.dart';
import '../../auth/domain/permission_guard.dart';
import '../../auth/domain/permissions.dart';
import '../../credit/data/credit_ledger.dart';

final customerRepositoryProvider = Provider<CustomerRepository>(
  (ref) => CustomerRepository(ref.watch(databaseProvider)),
);

/// Live account balance per customer id (customers who have ledger rows).
final customerBalancesProvider = StreamProvider<Map<String, double>>((ref) {
  final database = ref.watch(databaseProvider);
  return database
      .customSelect(
        'SELECT customer_id, SUM(debit - credit) AS balance '
        'FROM customer_ledger_entries GROUP BY customer_id',
        readsFrom: {database.customerLedgerEntries},
      )
      .watch()
      .map(
        (rows) => {
          for (final row in rows)
            row.read<String>('customer_id'): row.read<double>('balance'),
        },
      );
});

class CustomerStats {
  const CustomerStats(this.orders, this.total, this.lastPurchase);
  final int orders;
  final double total;
  final DateTime? lastPurchase;
}

/// Orders, spend (non-voided sales) and last purchase per customer.
final customerStatsProvider = StreamProvider<Map<String, CustomerStats>>((ref) {
  final database = ref.watch(databaseProvider);
  return database
      .customSelect(
        '''
        SELECT customer_id, COUNT(*) AS orders, SUM(grand_total) AS total,
               MAX(created_at) AS last_purchase
        FROM sales
        WHERE customer_id IS NOT NULL AND sale_status <> 'voided'
        GROUP BY customer_id
        ''',
        readsFrom: {database.sales},
      )
      .watch()
      .map(
        (rows) => {
          for (final row in rows)
            row.read<String>('customer_id'): CustomerStats(
              row.read<int>('orders'),
              row.read<double>('total'),
              row.readNullable<DateTime>('last_purchase'),
            ),
        },
      );
});

class CustomerSummary {
  const CustomerSummary({
    required this.customer,
    required this.totalSpend,
    this.lastPurchase,
  });
  final Customer customer;
  final double totalSpend;
  final DateTime? lastPurchase;
}

class CustomerRepository {
  CustomerRepository(this._database, {Uuid? uuid})
    : _uuid = uuid ?? const Uuid();
  final AppDatabase _database;
  final Uuid _uuid;

  Future<List<Customer>> search(String term, {int limit = 40}) {
    final pattern = '%${term.trim()}%';
    final query = _database.select(_database.customers)
      ..where(
        (row) =>
            row.isActive.equals(true) &
            (row.name.like(pattern) | row.phone.like(pattern)),
      )
      ..orderBy([(row) => OrderingTerm.asc(row.name)])
      ..limit(limit);
    return query.get();
  }

  Future<Customer?> byId(String id) => (_database.select(
    _database.customers,
  )..where((row) => row.id.equals(id))).getSingleOrNull();

  Stream<List<Customer>> watchAll({String search = ''}) {
    final pattern = '%${search.trim()}%';
    return (_database.select(_database.customers)
          ..where(
            (row) => search.trim().isEmpty
                ? const Constant(true)
                : row.name.like(pattern) | row.phone.like(pattern),
          )
          ..orderBy([(row) => OrderingTerm.asc(row.name)]))
        .watch();
  }

  Future<String> save({
    required AppSession session,
    String? id,
    required String name,
    String? phone,
    String? email,
    String address = '',
    String notes = '',
    int loyaltyPoints = 0,
    double creditLimit = 0,
    double openingBalance = 0,
    bool isActive = true,
  }) async {
    PermissionGuard.require(
      session,
      id == null ? Permissions.customersCreate : Permissions.customersEdit,
    );
    if (name.trim().isEmpty) throw ArgumentError('Customer name is required.');
    if (creditLimit < 0) {
      throw ArgumentError('The credit limit cannot be negative.');
    }
    final customerId = id ?? _uuid.v4();
    final now = DateTime.now();
    await _database.transaction(() async {
      final current = id == null
          ? null
          : await (_database.select(
              _database.customers,
            )..where((row) => row.id.equals(id))).getSingleOrNull();
      await _database
          .into(_database.customers)
          .insertOnConflictUpdate(
            CustomersCompanion.insert(
              id: customerId,
              name: name.trim(),
              phone: Value(
                phone?.trim().isEmpty == true ? null : phone?.trim(),
              ),
              email: Value(
                email?.trim().isEmpty == true ? null : email?.trim(),
              ),
              address: Value(address.trim()),
              notes: Value(notes.trim()),
              loyaltyPoints: Value(loyaltyPoints),
              creditLimit: Value(creditLimit),
              openingBalance: Value(openingBalance),
              isActive: Value(isActive),
              createdAt: current?.createdAt ?? now,
              updatedAt: now,
            ),
          );
      await CreditLedger(_database, uuid: _uuid).syncOpeningBalance(
        customerId: customerId,
        previous: current?.openingBalance ?? 0,
        next: openingBalance,
        storeId: session.store.id,
        userId: session.user.id,
        at: now,
      );
    });
    return customerId;
  }

  Future<CustomerSummary> summary(String customerId) async {
    final customer = await (_database.select(
      _database.customers,
    )..where((row) => row.id.equals(customerId))).getSingle();
    final row = await _database
        .customSelect(
          '''SELECT COALESCE(SUM(grand_total), 0.0) AS total_spend,
         MAX(created_at) AS last_purchase FROM sales
         WHERE customer_id = ? AND sale_status <> 'voided' ''',
          variables: [Variable.withString(customerId)],
        )
        .getSingle();
    final rawLast = row.data['last_purchase'];
    final lastPurchase = switch (rawLast) {
      int seconds => DateTime.fromMillisecondsSinceEpoch(seconds * 1000),
      String value => DateTime.tryParse(value),
      _ => null,
    };
    return CustomerSummary(
      customer: customer,
      totalSpend: row.read<double>('total_spend'),
      lastPurchase: lastPurchase,
    );
  }
}
