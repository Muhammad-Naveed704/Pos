import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../../../core/money/money.dart';
import '../domain/credit.dart';

/// SQL for one sale's unpaid balance (alias `s`): what was left on account at
/// checkout, minus posted payment allocations, minus returns that reduced it.
const saleOutstandingSql = '''(s.credit_amount
  - COALESCE((SELECT SUM(a.amount) FROM payment_allocations a
      JOIN customer_payments cp ON cp.id = a.payment_id
      WHERE a.sale_id = s.id AND cp.status = 'posted'), 0.0)
  - COALESCE((SELECT SUM(r.credit_applied) FROM sale_refunds r
      WHERE r.sale_id = s.id), 0.0))''';

/// Low-level customer account writes and reads shared by checkout, refunds
/// and customer payments. Callers own the transaction and permission checks.
class CreditLedger {
  CreditLedger(this._database, {Uuid? uuid}) : _uuid = uuid ?? const Uuid();
  final AppDatabase _database;
  final Uuid _uuid;

  /// Account balance: positive means the customer owes money.
  Future<Money> balance(String customerId) async {
    final row = await _database
        .customSelect(
          'SELECT COALESCE(SUM(debit - credit), 0.0) AS balance '
          'FROM customer_ledger_entries WHERE customer_id = ?',
          variables: [Variable.withString(customerId)],
        )
        .getSingle();
    return Money.fromMajor(row.read<double>('balance'));
  }

  Future<Money> saleOutstanding(String saleId) async {
    final row = await _database
        .customSelect(
          'SELECT $saleOutstandingSql AS outstanding FROM sales s WHERE s.id = ?',
          variables: [Variable.withString(saleId)],
        )
        .getSingleOrNull();
    if (row == null) return Money.zero;
    return Money.fromMajor(row.read<double>('outstanding')).max(Money.zero);
  }

  /// Opening balance (and adjustments) not yet covered by payments.
  Future<Money> openingOutstanding(String customerId) async {
    final row = await _database
        .customSelect(
          '''
          SELECT COALESCE((SELECT SUM(debit - credit) FROM customer_ledger_entries
                 WHERE customer_id = ?1 AND type IN ('opening', 'adjustment')), 0.0)
               - COALESCE((SELECT SUM(a.amount) FROM payment_allocations a
                 JOIN customer_payments cp ON cp.id = a.payment_id
                 WHERE cp.customer_id = ?1 AND cp.status = 'posted'
                   AND a.sale_id IS NULL), 0.0) AS outstanding
          ''',
          variables: [Variable.withString(customerId)],
        )
        .getSingle();
    return Money.fromMajor(row.read<double>('outstanding'));
  }

  /// Everything the customer still owes, oldest first.
  Future<List<OpenItem>> openItems(String customerId) async {
    final opening = await openingOutstanding(customerId);
    final rows = await _database
        .customSelect(
          '''
          SELECT s.id, s.invoice_number, s.created_at, s.due_date,
                 $saleOutstandingSql AS outstanding
          FROM sales s
          WHERE s.customer_id = ? AND s.credit_amount > 0
            AND $saleOutstandingSql > 0.004
          ORDER BY s.created_at, s.rowid
          ''',
          variables: [Variable.withString(customerId)],
        )
        .get();
    final customer = await (_database.select(
      _database.customers,
    )..where((c) => c.id.equals(customerId))).getSingleOrNull();
    return [
      if (opening.minorUnits > 0)
        OpenItem(
          saleId: null,
          label: 'Opening balance',
          date: customer?.createdAt ?? DateTime(2000),
          outstanding: opening,
        ),
      for (final row in rows)
        OpenItem(
          saleId: row.read<String>('id'),
          label: row.read<String>('invoice_number'),
          date: row.read<DateTime>('created_at'),
          dueDate: row.readNullable<DateTime>('due_date'),
          outstanding: Money.fromMajor(row.read<double>('outstanding')),
        ),
    ];
  }

  Future<void> entry({
    required String customerId,
    required String type,
    String? storeId,
    String? userId,
    String referenceType = '',
    String? referenceId,
    String referenceNumber = '',
    Money debit = Money.zero,
    Money credit = Money.zero,
    String note = '',
    required DateTime at,
  }) async {
    if (debit.minorUnits < 0 || credit.minorUnits < 0) {
      throw ArgumentError('Ledger amounts must not be negative.');
    }
    if (debit.minorUnits == 0 && credit.minorUnits == 0) return;
    await _database
        .into(_database.customerLedgerEntries)
        .insert(
          CustomerLedgerEntriesCompanion.insert(
            id: _uuid.v4(),
            customerId: customerId,
            storeId: Value(storeId),
            userId: Value(userId),
            type: type,
            referenceType: Value(referenceType),
            referenceId: Value(referenceId),
            referenceNumber: Value(referenceNumber),
            debit: Value(debit.majorUnits),
            credit: Value(credit.majorUnits),
            note: Value(note),
            createdAt: at,
          ),
        );
  }

  /// Records a change of a customer's opening balance as a ledger entry so
  /// the account balance follows the edited figure.
  Future<void> syncOpeningBalance({
    required String customerId,
    required double previous,
    required double next,
    String? storeId,
    String? userId,
    required DateTime at,
  }) async {
    final delta = Money.fromMajor(next) - Money.fromMajor(previous);
    if (delta.minorUnits == 0) return;
    final hasOpening =
        await (_database.select(_database.customerLedgerEntries)
              ..where(
                (e) =>
                    e.customerId.equals(customerId) &
                    e.type.isIn([LedgerType.opening, LedgerType.adjustment]),
              )
              ..limit(1))
            .getSingleOrNull();
    await entry(
      customerId: customerId,
      type: hasOpening == null ? LedgerType.opening : LedgerType.adjustment,
      storeId: storeId,
      userId: userId,
      referenceType: 'customer',
      referenceId: customerId,
      debit: delta.max(Money.zero),
      credit: (-delta).max(Money.zero),
      note: hasOpening == null
          ? 'Opening balance'
          : 'Opening balance changed from ${Money.fromMajor(previous)} to ${Money.fromMajor(next)}',
      at: at,
    );
  }

  /// Re-derives `sales.payment_status` from the current balance.
  Future<void> refreshSaleStatus(String saleId, DateTime now) async {
    final sale = await (_database.select(
      _database.sales,
    )..where((s) => s.id.equals(saleId))).getSingleOrNull();
    if (sale == null || sale.creditAmount <= 0) return;
    final status = PaymentStatus.of(
      Money.fromMajor(sale.grandTotal),
      await saleOutstanding(saleId),
    );
    if (status == sale.paymentStatus) return;
    await (_database.update(_database.sales)..where((s) => s.id.equals(saleId)))
        .write(SalesCompanion(paymentStatus: Value(status)));
  }
}
