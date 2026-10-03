import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/database_provider.dart';
import '../../../core/money/money.dart';
import '../../auth/domain/app_session.dart';
import '../../auth/domain/permission_guard.dart';
import '../../auth/domain/permissions.dart';
import '../domain/credit.dart';
import 'credit_ledger.dart';

final creditServiceProvider = Provider<CreditService>(
  (ref) => CreditService(ref.watch(databaseProvider)),
);

class CreditException implements Exception {
  const CreditException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Raised by checkout when a credit sale would take the customer over their
/// limit. The UI may retry with an override if the user is allowed to.
class CreditLimitException extends CreditException {
  const CreditLimitException({
    required this.customerName,
    required this.limit,
    required this.outstanding,
    required this.requested,
  }) : super('This sale exceeds the customer credit limit.');
  final String customerName;
  final Money limit;
  final Money outstanding;
  final Money requested;

  Money get projected => outstanding + requested;
}

class CustomerBalance {
  const CustomerBalance({
    required this.customer,
    required this.totalPurchases,
    required this.totalPaid,
    required this.outstanding,
    required this.overdue,
    required this.openInvoices,
    this.lastPurchase,
    this.oldestDue,
  });
  final Customer customer;

  /// Non-voided sales minus returns.
  final Money totalPurchases;

  /// Paid at the till plus payments received.
  final Money totalPaid;
  final Money outstanding;
  final Money overdue;
  final int openInvoices;
  final DateTime? lastPurchase;
  final DateTime? oldestDue;

  Money get creditLimit => Money.fromMajor(customer.creditLimit);
  Money get availableCredit => (creditLimit - outstanding).max(Money.zero);
  bool get hasBalance => outstanding.minorUnits > 0;
  DueStatus get dueStatus =>
      overdue.minorUnits > 0 ? DueStatus.overdue : DueStatus.of(oldestDue);
}

class CustomerInvoice {
  const CustomerInvoice({
    required this.sale,
    required this.storeName,
    required this.paid,
    required this.refunded,
    required this.outstanding,
  });
  final Sale sale;
  final String storeName;
  final Money paid;
  final Money refunded;
  final Money outstanding;

  Money get total => Money.fromMajor(sale.grandTotal);
  DueStatus? get dueStatus =>
      outstanding.minorUnits > 0 ? DueStatus.of(sale.dueDate) : null;
}

class LedgerRow {
  const LedgerRow({
    required this.entry,
    required this.balance,
    this.userName,
    this.storeName,
  });
  final CustomerLedgerEntry entry;

  /// Account balance after this entry.
  final Money balance;
  final String? userName;
  final String? storeName;

  Money get debit => Money.fromMajor(entry.debit);
  Money get credit => Money.fromMajor(entry.credit);
}

enum LedgerFilter {
  all('All'),
  invoices('Invoices'),
  payments('Payments');

  const LedgerFilter(this.label);
  final String label;

  Set<String> get types => switch (this) {
    LedgerFilter.all => const {},
    LedgerFilter.invoices => const {
      LedgerType.sale,
      LedgerType.salePayment,
      LedgerType.refund,
      LedgerType.refundPaid,
      LedgerType.voidSale,
      LedgerType.voidPaid,
    },
    LedgerFilter.payments => const {
      LedgerType.payment,
      LedgerType.paymentReversal,
    },
  };
}

class LedgerPage {
  const LedgerPage({
    required this.opening,
    required this.rows,
    required this.closing,
  });

  /// Balance before the first row of the period.
  final Money opening;
  final List<LedgerRow> rows;

  /// Balance at the end of the period.
  final Money closing;

  Money get debit => rows.fold(Money.zero, (sum, row) => sum + row.debit);
  Money get credit => rows.fold(Money.zero, (sum, row) => sum + row.credit);
}

class PaymentRecord {
  const PaymentRecord({
    required this.payment,
    required this.userName,
    required this.storeName,
    required this.allocations,
  });
  final CustomerPayment payment;
  final String userName;
  final String storeName;

  /// (invoice number or "Opening balance", amount).
  final List<(String, Money)> allocations;

  Money get amount => Money.fromMajor(payment.amount);
  bool get reversed => payment.status == 'reversed';
}

class PaymentResult {
  const PaymentResult(this.paymentId, this.number, this.amount, this.balance);
  final String paymentId;
  final String number;
  final Money amount;

  /// Customer balance after the payment.
  final Money balance;
}

class Debtor {
  const Debtor({
    required this.customerId,
    required this.name,
    required this.phone,
    required this.outstanding,
    required this.overdue,
    this.oldestDue,
  });
  final String customerId;
  final String name;
  final String? phone;
  final Money outstanding;
  final Money overdue;
  final DateTime? oldestDue;
}

class ReceivablesSummary {
  const ReceivablesSummary({
    required this.total,
    required this.overdue,
    required this.dueThisWeek,
    required this.customers,
    required this.topDebtors,
  });
  final Money total;
  final Money overdue;
  final Money dueThisWeek;
  final int customers;
  final List<Debtor> topDebtors;
}

/// Customer accounts: balances, ledger, payments and due dates.
///
/// Customer accounts are business-wide: a customer can buy on credit in one
/// branch and pay in another, so balances and receivables are not limited to
/// the active store. Every write is recorded against the active store.
class CreditService {
  CreditService(this._database, {Uuid? uuid, this._transactionProbe})
    : _uuid = uuid ?? const Uuid(),
      _ledger = CreditLedger(_database, uuid: uuid);

  final AppDatabase _database;
  final Uuid _uuid;
  final CreditLedger _ledger;
  final Future<void> Function()? _transactionProbe;

  static const methods = {'cash', 'card', 'bank', 'other'};

  static DateTime _startOfToday() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  Future<Customer> _customer(String id) async {
    final customer = await (_database.select(
      _database.customers,
    )..where((c) => c.id.equals(id))).getSingleOrNull();
    if (customer == null) throw const CreditException('Customer not found.');
    return customer;
  }

  Future<CustomerBalance> balance(AppSession session, String customerId) async {
    PermissionGuard.require(session, Permissions.customersView);
    final customer = await _customer(customerId);
    final today = Variable.withDateTime(_startOfToday());
    final row = await _database
        .customSelect(
          '''
          SELECT
            COALESCE((SELECT SUM(grand_total) FROM sales
              WHERE customer_id = ?1 AND sale_status <> 'voided'), 0.0)
            - COALESCE((SELECT SUM(r.amount) FROM sale_refunds r JOIN sales s ON s.id = r.sale_id
              WHERE s.customer_id = ?1 AND r.kind = 'refund'), 0.0) AS purchases,
            COALESCE((SELECT SUM(grand_total - credit_amount) FROM sales
              WHERE customer_id = ?1 AND sale_status <> 'voided'), 0.0)
            + COALESCE((SELECT SUM(amount) FROM customer_payments
              WHERE customer_id = ?1 AND status = 'posted'), 0.0) AS paid,
            (SELECT MAX(created_at) FROM sales
              WHERE customer_id = ?1 AND sale_status <> 'voided') AS last_purchase,
            COALESCE((SELECT SUM($saleOutstandingSql) FROM sales s
              WHERE s.customer_id = ?1 AND s.credit_amount > 0
                AND s.due_date IS NOT NULL AND s.due_date < ?2), 0.0) AS overdue,
            (SELECT COUNT(*) FROM sales s WHERE s.customer_id = ?1
              AND s.credit_amount > 0 AND $saleOutstandingSql > 0.004) AS open_invoices,
            (SELECT MIN(s.due_date) FROM sales s WHERE s.customer_id = ?1
              AND s.credit_amount > 0 AND $saleOutstandingSql > 0.004) AS oldest_due
          ''',
          variables: [Variable.withString(customerId), today],
        )
        .getSingle();
    return CustomerBalance(
      customer: customer,
      totalPurchases: Money.fromMajor(row.read<double>('purchases')),
      totalPaid: Money.fromMajor(row.read<double>('paid')),
      outstanding: await _ledger.balance(customerId),
      overdue: Money.fromMajor(row.read<double>('overdue')).max(Money.zero),
      openInvoices: row.read<int>('open_invoices'),
      lastPurchase: row.readNullable<DateTime>('last_purchase'),
      oldestDue: row.readNullable<DateTime>('oldest_due'),
    );
  }

  /// Unpaid items (opening balance and invoices), oldest first.
  Future<List<OpenItem>> openItems(AppSession session, String customerId) {
    PermissionGuard.require(session, Permissions.creditView);
    return _ledger.openItems(customerId);
  }

  /// All of a customer's invoices, newest first.
  Future<List<CustomerInvoice>> invoices(
    AppSession session,
    String customerId, {
    bool openOnly = false,
    int limit = 200,
  }) async {
    PermissionGuard.require(session, Permissions.customersView);
    final rows = await _database
        .customSelect(
          '''
          SELECT s.*, st.name AS store_name,
                 $saleOutstandingSql AS outstanding,
                 COALESCE((SELECT SUM(r.amount) FROM sale_refunds r
                   WHERE r.sale_id = s.id AND r.kind = 'refund'), 0.0) AS refunded,
                 COALESCE((SELECT SUM(a.amount) FROM payment_allocations a
                   JOIN customer_payments cp ON cp.id = a.payment_id
                   WHERE a.sale_id = s.id AND cp.status = 'posted'), 0.0) AS allocated
          FROM sales s JOIN stores st ON st.id = s.store_id
          WHERE s.customer_id = ?1
            ${openOnly ? "AND s.credit_amount > 0 AND $saleOutstandingSql > 0.004" : ''}
          ORDER BY s.created_at DESC, s.rowid DESC
          LIMIT ?2
          ''',
          variables: [Variable.withString(customerId), Variable.withInt(limit)],
        )
        .get();
    return [
      for (final row in rows)
        () {
          final sale = _database.sales.map(row.data);
          return CustomerInvoice(
            sale: sale,
            storeName: row.read<String>('store_name'),
            paid: Money.fromMajor(
              sale.grandTotal -
                  sale.creditAmount +
                  row.read<double>('allocated'),
            ),
            refunded: Money.fromMajor(row.read<double>('refunded')),
            outstanding: Money.fromMajor(row.read<double>('outstanding'))
                .max(Money.zero),
          );
        }(),
    ];
  }

  /// Ledger entries in [from, to) with the running account balance.
  /// Filters only hide rows; balances always reflect the whole account.
  Future<LedgerPage> ledger(
    AppSession session,
    String customerId, {
    DateTime? from,
    DateTime? to,
    String? storeId,
    LedgerFilter filter = LedgerFilter.all,
    String search = '',
  }) async {
    PermissionGuard.require(session, Permissions.creditView);
    var opening = Money.zero;
    if (from != null) {
      final row = await _database
          .customSelect(
            'SELECT COALESCE(SUM(debit - credit), 0.0) AS b FROM customer_ledger_entries '
            'WHERE customer_id = ? AND created_at < ?',
            variables: [
              Variable.withString(customerId),
              Variable.withDateTime(from),
            ],
          )
          .getSingle();
      opening = Money.fromMajor(row.read<double>('b'));
    }
    final rows = await _database
        .customSelect(
          '''
          SELECT e.*, u.display_name AS user_name, st.name AS store_name
          FROM customer_ledger_entries e
          LEFT JOIN users u ON u.id = e.user_id
          LEFT JOIN stores st ON st.id = e.store_id
          WHERE e.customer_id = ?1
            AND (?2 IS NULL OR e.created_at >= ?2)
            AND (?3 IS NULL OR e.created_at < ?3)
          ORDER BY e.created_at, e.rowid
          ''',
          variables: [
            Variable.withString(customerId),
            Variable<DateTime>(from),
            Variable<DateTime>(to),
          ],
        )
        .get();
    var running = opening;
    final term = search.trim().toLowerCase();
    final visible = <LedgerRow>[];
    for (final row in rows) {
      final entry = _database.customerLedgerEntries.map(row.data);
      running += Money.fromMajor(entry.debit) - Money.fromMajor(entry.credit);
      if (storeId != null && entry.storeId != storeId) continue;
      if (filter.types.isNotEmpty && !filter.types.contains(entry.type)) {
        continue;
      }
      if (term.isNotEmpty &&
          !entry.referenceNumber.toLowerCase().contains(term) &&
          !entry.note.toLowerCase().contains(term) &&
          !LedgerType.label(entry.type).toLowerCase().contains(term)) {
        continue;
      }
      visible.add(
        LedgerRow(
          entry: entry,
          balance: running,
          userName: row.readNullable<String>('user_name'),
          storeName: row.readNullable<String>('store_name'),
        ),
      );
    }
    return LedgerPage(opening: opening, rows: visible, closing: running);
  }

  Future<List<PaymentRecord>> payments(
    AppSession session, {
    String? customerId,
    int limit = 200,
  }) async {
    PermissionGuard.require(session, Permissions.creditView);
    final rows = await _database
        .customSelect(
          '''
          SELECT cp.*, u.display_name AS user_name, st.name AS store_name
          FROM customer_payments cp
          JOIN users u ON u.id = cp.user_id
          JOIN stores st ON st.id = cp.store_id
          WHERE (?1 IS NULL OR cp.customer_id = ?1)
          ORDER BY cp.created_at DESC, cp.rowid DESC
          LIMIT ?2
          ''',
          variables: [Variable<String>(customerId), Variable.withInt(limit)],
        )
        .get();
    final result = <PaymentRecord>[];
    for (final row in rows) {
      final payment = _database.customerPayments.map(row.data);
      final allocations = await _database
          .customSelect(
            '''
            SELECT COALESCE(s.invoice_number, 'Opening balance') AS label, a.amount
            FROM payment_allocations a LEFT JOIN sales s ON s.id = a.sale_id
            WHERE a.payment_id = ? ORDER BY a.rowid
            ''',
            variables: [Variable.withString(payment.id)],
          )
          .get();
      result.add(
        PaymentRecord(
          payment: payment,
          userName: row.read<String>('user_name'),
          storeName: row.read<String>('store_name'),
          allocations: [
            for (final a in allocations)
              (
                a.read<String>('label'),
                Money.fromMajor(a.read<double>('amount')),
              ),
          ],
        ),
      );
    }
    return result;
  }

  /// Records money received from a customer. Applies it oldest-first unless
  /// [manualAllocations] (sale id, or null for the opening balance) is given.
  Future<PaymentResult> receivePayment(
    AppSession session, {
    required String customerId,
    required Money amount,
    required String method,
    String? reference,
    String note = '',
    DateTime? receivedAt,
    Map<String?, Money>? manualAllocations,
  }) async {
    PermissionGuard.require(session, Permissions.creditReceivePayment);
    if (amount.minorUnits <= 0) {
      throw const CreditException('Enter an amount greater than zero.');
    }
    if (!methods.contains(method)) {
      throw const CreditException('Choose a valid payment method.');
    }
    final at = receivedAt ?? DateTime.now();
    if (at.isAfter(DateTime.now().add(const Duration(minutes: 5)))) {
      throw const CreditException('The payment date cannot be in the future.');
    }
    return _database.transaction(() async {
      final customer = await _customer(customerId);
      final items = await _ledger.openItems(customerId);
      final owed = items.fold(Money.zero, (sum, i) => sum + i.outstanding);
      if (owed.minorUnits <= 0) {
        throw CreditException('${customer.name} has no outstanding balance.');
      }
      if (amount.compareTo(owed) > 0) {
        throw CreditException(
          'The payment is more than the outstanding balance ($owed).',
        );
      }
      final List<AllocationPlan> plan;
      if (manualAllocations == null) {
        plan = allocateOldestFirst(amount, items);
      } else {
        final byId = {for (final item in items) item.saleId: item};
        var total = Money.zero;
        plan = [];
        for (final MapEntry(:key, :value) in manualAllocations.entries) {
          if (value.minorUnits == 0) continue;
          final item = byId[key];
          if (item == null || value.minorUnits < 0) {
            throw const CreditException('Allocation is not an open invoice.');
          }
          if (value.compareTo(item.outstanding) > 0) {
            throw CreditException(
              'Allocation to ${item.label} exceeds its balance (${item.outstanding}).',
            );
          }
          plan.add(AllocationPlan(key, value));
          total += value;
        }
        if (total != amount) {
          throw const CreditException(
            'Allocated amounts must add up to the payment amount.',
          );
        }
      }

      final openSession = method == 'cash'
          ? await _openCashSession(session)
          : null;
      final paymentId = _uuid.v4();
      final number = await _nextNumber(session, at);
      await _database
          .into(_database.customerPayments)
          .insert(
            CustomerPaymentsCompanion.insert(
              id: paymentId,
              number: number,
              customerId: customerId,
              storeId: session.store.id,
              userId: session.user.id,
              method: method,
              amount: amount.majorUnits,
              reference: Value(
                reference?.trim().isEmpty ?? true ? null : reference!.trim(),
              ),
              note: Value(note.trim()),
              cashSessionId: Value(openSession?.id),
              createdAt: at,
            ),
          );
      for (final allocation in plan) {
        await _database
            .into(_database.paymentAllocations)
            .insert(
              PaymentAllocationsCompanion.insert(
                id: _uuid.v4(),
                paymentId: paymentId,
                saleId: Value(allocation.saleId),
                amount: allocation.amount.majorUnits,
                createdAt: at,
              ),
            );
      }
      await _ledger.entry(
        customerId: customerId,
        type: LedgerType.payment,
        storeId: session.store.id,
        userId: session.user.id,
        referenceType: 'customer_payment',
        referenceId: paymentId,
        referenceNumber: number,
        credit: amount,
        note: [
          method.toUpperCase(),
          if (reference?.trim().isNotEmpty ?? false) reference!.trim(),
          if (note.trim().isNotEmpty) note.trim(),
        ].join(' · '),
        at: at,
      );
      if (_transactionProbe != null) await _transactionProbe();
      if (method == 'cash') {
        await _database
            .into(_database.cashTransactions)
            .insert(
              CashTransactionsCompanion.insert(
                id: _uuid.v4(),
                storeId: session.store.id,
                userId: session.user.id,
                sessionId: Value(openSession?.id),
                type: 'customer_payment',
                category: 'Customer payment',
                amount: amount.majorUnits,
                description: Value('Payment $number from ${customer.name}'),
                reference: Value(paymentId),
                createdAt: at,
              ),
            );
      }
      for (final allocation in plan) {
        if (allocation.saleId != null) {
          await _ledger.refreshSaleStatus(allocation.saleId!, at);
        }
      }
      final after = await _ledger.balance(customerId);
      await _audit(
        session,
        'credit.payment_received',
        'customer_payment',
        paymentId,
        'Received $amount from ${customer.name} by $method ($number).',
        {
          'customerId': customerId,
          'amountMinor': amount.minorUnits,
          'method': method,
          'allocations': {
            for (final a in plan) a.saleId ?? 'opening': a.amount.minorUnits,
          },
          'manual': manualAllocations != null,
        },
      );
      return PaymentResult(paymentId, number, amount, after);
    });
  }

  /// Cancels a payment recorded by mistake: its allocations stop counting,
  /// the ledger is debited back and cash leaves the drawer.
  Future<void> reversePayment(
    AppSession session, {
    required String paymentId,
    required String reason,
  }) async {
    PermissionGuard.require(session, Permissions.creditReceivePayment);
    if (reason.trim().isEmpty) {
      throw const CreditException('Enter a reason for the reversal.');
    }
    await _database.transaction(() async {
      final payment = await (_database.select(
        _database.customerPayments,
      )..where((p) => p.id.equals(paymentId))).getSingleOrNull();
      if (payment == null) throw const CreditException('Payment not found.');
      if (payment.status != 'posted') {
        throw const CreditException('This payment is already reversed.');
      }
      final amount = Money.fromMajor(payment.amount);
      final now = DateTime.now();
      final openSession = payment.method == 'cash'
          ? await _openCashSession(session)
          : null;
      if (payment.method == 'cash' && openSession != null) {
        final inDrawer = await _drawerCash(openSession);
        if (amount.compareTo(inDrawer) > 0) {
          throw CreditException(
            'Not enough cash in the drawer ($inDrawer) to pay this back.',
          );
        }
      }
      await (_database.update(_database.customerPayments)
            ..where((p) => p.id.equals(paymentId)))
          .write(const CustomerPaymentsCompanion(status: Value('reversed')));
      await _ledger.entry(
        customerId: payment.customerId,
        type: LedgerType.paymentReversal,
        storeId: session.store.id,
        userId: session.user.id,
        referenceType: 'customer_payment',
        referenceId: paymentId,
        referenceNumber: payment.number,
        debit: amount,
        note: reason.trim(),
        at: now,
      );
      if (payment.method == 'cash') {
        await _database
            .into(_database.cashTransactions)
            .insert(
              CashTransactionsCompanion.insert(
                id: _uuid.v4(),
                storeId: session.store.id,
                userId: session.user.id,
                sessionId: Value(openSession?.id),
                type: 'customer_refund',
                category: 'Customer payment reversed',
                amount: amount.majorUnits,
                description: Value('Reversed ${payment.number}'),
                reference: Value(paymentId),
                createdAt: now,
              ),
            );
      }
      final sales =
          await (_database.select(_database.paymentAllocations)..where(
                (a) => a.paymentId.equals(paymentId) & a.saleId.isNotNull(),
              ))
              .get();
      for (final allocation in sales) {
        await _ledger.refreshSaleStatus(allocation.saleId!, now);
      }
      await _audit(
        session,
        'credit.payment_reversed',
        'customer_payment',
        paymentId,
        'Reversed payment ${payment.number} of $amount (${reason.trim()}).',
        {'customerId': payment.customerId, 'amountMinor': amount.minorUnits},
      );
    });
  }

  Future<void> setDueDate(
    AppSession session, {
    required String saleId,
    required DateTime? dueDate,
  }) async {
    PermissionGuard.require(session, Permissions.creditEditDueDate);
    await _database.transaction(() async {
      final sale = await (_database.select(
        _database.sales,
      )..where((s) => s.id.equals(saleId))).getSingleOrNull();
      if (sale == null || sale.creditAmount <= 0) {
        throw const CreditException('Only credit invoices have a due date.');
      }
      final due = dueDate == null
          ? null
          : DateTime(dueDate.year, dueDate.month, dueDate.day);
      await (_database.update(
        _database.sales,
      )..where((s) => s.id.equals(saleId))).write(
        SalesCompanion(dueDate: Value(due), updatedAt: Value(DateTime.now())),
      );
      await _audit(
        session,
        'credit.due_date_changed',
        'sale',
        saleId,
        'Due date of ${sale.invoiceNumber} changed.',
        {'from': sale.dueDate?.toIso8601String(), 'to': due?.toIso8601String()},
      );
    });
  }

  /// Business-wide receivables for the dashboard and AR page.
  Future<ReceivablesSummary> receivables(
    AppSession session, {
    int top = 5,
  }) async {
    PermissionGuard.require(session, Permissions.creditView);
    final debtors = await debtorList(session);
    final today = _startOfToday();
    final row = await _database
        .customSelect(
          '''
          SELECT COALESCE(SUM($saleOutstandingSql), 0.0) AS due_week
          FROM sales s
          WHERE s.credit_amount > 0 AND s.customer_id IS NOT NULL
            AND s.due_date >= ?1 AND s.due_date < ?2
          ''',
          variables: [
            Variable.withDateTime(today),
            Variable.withDateTime(today.add(const Duration(days: 7))),
          ],
        )
        .getSingle();
    return ReceivablesSummary(
      total: debtors.fold(Money.zero, (sum, d) => sum + d.outstanding),
      overdue: debtors.fold(Money.zero, (sum, d) => sum + d.overdue),
      dueThisWeek: Money.fromMajor(row.read<double>('due_week'))
          .max(Money.zero),
      customers: debtors.length,
      topDebtors: debtors.take(top).toList(),
    );
  }

  /// Customers who owe money, largest balance first.
  Future<List<Debtor>> debtorList(
    AppSession session, {
    bool overdueOnly = false,
  }) async {
    PermissionGuard.require(session, Permissions.creditView);
    final rows = await _database
        .customSelect(
          '''
          SELECT c.id, c.name, c.phone, b.balance,
            COALESCE((SELECT SUM($saleOutstandingSql) FROM sales s
              WHERE s.customer_id = c.id AND s.credit_amount > 0
                AND s.due_date IS NOT NULL AND s.due_date < ?1), 0.0) AS overdue,
            (SELECT MIN(s.due_date) FROM sales s WHERE s.customer_id = c.id
              AND s.credit_amount > 0 AND $saleOutstandingSql > 0.004) AS oldest_due
          FROM (SELECT customer_id, SUM(debit - credit) AS balance
                FROM customer_ledger_entries GROUP BY customer_id) b
          JOIN customers c ON c.id = b.customer_id
          WHERE b.balance > 0.004
          ORDER BY b.balance DESC
          ''',
          variables: [Variable.withDateTime(_startOfToday())],
        )
        .get();
    final list = [
      for (final row in rows)
        Debtor(
          customerId: row.read<String>('id'),
          name: row.read<String>('name'),
          phone: row.readNullable<String>('phone'),
          outstanding: Money.fromMajor(row.read<double>('balance')),
          overdue: Money.fromMajor(row.read<double>('overdue')).max(Money.zero),
          oldestDue: row.readNullable<DateTime>('oldest_due'),
        ),
    ];
    return overdueOnly
        ? list.where((d) => d.overdue.minorUnits > 0).toList()
        : list;
  }

  Future<String> _nextNumber(AppSession session, DateTime at) async {
    final row = await _database
        .customSelect(
          'SELECT COUNT(*) AS n FROM customer_payments WHERE store_id = ?',
          variables: [Variable.withString(session.store.id)],
        )
        .getSingle();
    var next = row.read<int>('n') + 1;
    while (true) {
      final number =
          'PAY-${session.store.code}-${at.year}-${next.toString().padLeft(5, '0')}';
      final clash = await (_database.select(
        _database.customerPayments,
      )..where((p) => p.number.equals(number))).getSingleOrNull();
      if (clash == null) return number;
      next++;
    }
  }

  Future<CashSession?> _openCashSession(AppSession session) =>
      (_database.select(_database.cashSessions)
            ..where(
              (s) =>
                  s.storeId.equals(session.store.id) &
                  s.userId.equals(session.user.id) &
                  s.status.equals('open'),
            )
            ..limit(1))
          .getSingleOrNull();

  Future<Money> _drawerCash(CashSession open) async {
    final row = await _database
        .customSelect(
          '''
          SELECT ?2 + COALESCE(SUM(CASE WHEN type IN ('pay_out', 'cash_refund', 'customer_refund')
                 THEN -amount ELSE amount END), 0.0) AS expected
          FROM cash_transactions WHERE session_id = ?1
          ''',
          variables: [
            Variable.withString(open.id),
            Variable.withReal(open.openingBalance),
          ],
        )
        .getSingle();
    return Money.fromMajor(row.read<double>('expected'));
  }

  Future<void> _audit(
    AppSession session,
    String action,
    String entityType,
    String entityId,
    String description,
    Map<String, Object?> data,
  ) => _database
      .into(_database.auditLogs)
      .insert(
        AuditLogsCompanion.insert(
          id: _uuid.v4(),
          userId: Value(session.user.id),
          storeId: Value(session.store.id),
          action: action,
          entityType: entityType,
          entityId: Value(entityId),
          description: description,
          newValueJson: Value(jsonEncode(data)),
          createdAt: DateTime.now(),
        ),
      );
}
