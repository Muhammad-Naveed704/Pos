import '../../../core/money/money.dart';

/// `sales.payment_status` values. A sale starts as one of these at checkout
/// and moves towards [paid] as its balance is settled.
abstract final class PaymentStatus {
  static const paid = 'paid';
  static const partial = 'partial';
  static const credit = 'credit';

  static String label(String status) => switch (status) {
    paid => 'Paid',
    partial => 'Partly paid',
    credit => 'On credit',
    _ => status,
  };

  /// Status for an invoice of [total] with [outstanding] still unpaid.
  static String of(Money total, Money outstanding) {
    if (outstanding.minorUnits <= 0) return paid;
    if (outstanding.compareTo(total) >= 0) return credit;
    return partial;
  }
}

/// Customer ledger entry types. Balance = sum(debit) - sum(credit); a
/// positive balance is money the customer owes.
abstract final class LedgerType {
  static const opening = 'opening';
  static const adjustment = 'adjustment';
  static const sale = 'sale';
  static const salePayment = 'sale_payment';
  static const payment = 'payment';
  static const paymentReversal = 'payment_reversal';
  static const refund = 'refund';
  static const refundPaid = 'refund_paid';
  static const voidSale = 'void';
  static const voidPaid = 'void_paid';

  static String label(String type) => switch (type) {
    opening => 'Opening balance',
    adjustment => 'Balance adjustment',
    sale => 'Sale',
    salePayment => 'Paid at sale',
    payment => 'Payment received',
    paymentReversal => 'Payment reversed',
    refund => 'Return',
    refundPaid => 'Refund paid out',
    voidSale => 'Sale voided',
    voidPaid => 'Void paid out',
    _ => type,
  };
}

/// Due-date standing of an unpaid invoice.
enum DueStatus {
  current('Current'),
  dueSoon('Due soon'),
  overdue('Overdue');

  const DueStatus(this.label);
  final String label;

  /// Days before the due date that count as "due soon".
  static const soonDays = 3;

  static DueStatus of(DateTime? dueDate, {DateTime? now}) {
    if (dueDate == null) return DueStatus.current;
    final today = _day(now ?? DateTime.now());
    final due = _day(dueDate.toLocal());
    if (due.isBefore(today)) return DueStatus.overdue;
    if (!due.isAfter(today.add(const Duration(days: soonDays)))) {
      return DueStatus.dueSoon;
    }
    return DueStatus.current;
  }

  static DateTime _day(DateTime value) =>
      DateTime(value.year, value.month, value.day);
}

/// Something a customer still owes: an invoice or their opening balance
/// (`saleId == null`).
class OpenItem {
  const OpenItem({
    required this.saleId,
    required this.label,
    required this.date,
    required this.outstanding,
    this.dueDate,
  });
  final String? saleId;
  final String label;
  final DateTime date;
  final Money outstanding;
  final DateTime? dueDate;

  DueStatus get dueStatus => DueStatus.of(dueDate);
}

class AllocationPlan {
  const AllocationPlan(this.saleId, this.amount);
  final String? saleId;
  final Money amount;
}

/// Applies [amount] to [items] oldest first (opening balance before
/// invoices, then by date). Throws if the amount exceeds what is owed.
List<AllocationPlan> allocateOldestFirst(Money amount, List<OpenItem> items) {
  final ordered = [...items]
    ..sort((a, b) {
      if (a.saleId == null) return -1;
      if (b.saleId == null) return 1;
      return a.date.compareTo(b.date);
    });
  var left = amount;
  final plan = <AllocationPlan>[];
  for (final item in ordered) {
    if (left.minorUnits <= 0) break;
    if (item.outstanding.minorUnits <= 0) continue;
    final share = left.compareTo(item.outstanding) > 0
        ? item.outstanding
        : left;
    plan.add(AllocationPlan(item.saleId, share));
    left -= share;
  }
  if (left.minorUnits > 0) {
    throw ArgumentError('The payment is more than the customer owes.');
  }
  return plan;
}
