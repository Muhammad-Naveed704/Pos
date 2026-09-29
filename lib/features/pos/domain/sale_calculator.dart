import 'dart:math' as math;

enum DiscountKind { fixed, percentage }

class SaleLineInput {
  const SaleLineInput({
    required this.quantity,
    required this.unitPrice,
    this.taxRate = 0,
    this.discount = 0,
    this.discountKind = DiscountKind.fixed,
  });

  final double quantity;
  final double unitPrice;
  final double taxRate;
  final double discount;
  final DiscountKind discountKind;
}

class SaleLineTotal {
  const SaleLineTotal({
    required this.gross,
    required this.discount,
    required this.tax,
    required this.total,
  });

  final double gross;
  final double discount;
  final double tax;
  final double total;
}

class SaleTotals {
  const SaleTotals({
    required this.subtotal,
    required this.lineDiscount,
    required this.invoiceDiscount,
    required this.tax,
    required this.grandTotal,
    required this.paid,
    required this.change,
    required this.balanceDue,
  });

  final double subtotal;
  final double lineDiscount;
  final double invoiceDiscount;
  final double tax;
  final double grandTotal;
  final double paid;
  final double change;
  final double balanceDue;
}

abstract final class SaleCalculator {
  static SaleLineTotal line(SaleLineInput input) {
    if (input.quantity <= 0 || input.unitPrice < 0) {
      throw ArgumentError(
        'Quantity must be positive and price cannot be negative.',
      );
    }
    final gross = _money(input.quantity * input.unitPrice);
    final requested = input.discountKind == DiscountKind.percentage
        ? gross * input.discount.clamp(0, 100) / 100
        : input.discount;
    final discount = _money(requested.clamp(0, gross));
    final taxable = gross - discount;
    final tax = _money(taxable * input.taxRate.clamp(0, 100) / 100);
    return SaleLineTotal(
      gross: gross,
      discount: discount,
      tax: tax,
      total: _money(taxable + tax),
    );
  }

  static SaleTotals sale({
    required Iterable<SaleLineInput> lines,
    double invoiceDiscount = 0,
    DiscountKind invoiceDiscountKind = DiscountKind.fixed,
    Iterable<double> payments = const [],
  }) {
    final calculated = lines.map(line).toList(growable: false);
    final subtotal = _money(
      calculated.fold(0, (sum, item) => sum + item.gross),
    );
    final lineDiscount = _money(
      calculated.fold(0, (sum, item) => sum + item.discount),
    );
    final beforeInvoiceDiscount = subtotal - lineDiscount;
    final requested = invoiceDiscountKind == DiscountKind.percentage
        ? beforeInvoiceDiscount * invoiceDiscount.clamp(0, 100) / 100
        : invoiceDiscount;
    final appliedInvoiceDiscount = _money(
      requested.clamp(0, beforeInvoiceDiscount),
    );
    final taxBeforeProration = calculated.fold(
      0.0,
      (sum, item) => sum + item.tax,
    );
    final ratio = beforeInvoiceDiscount == 0
        ? 0
        : (beforeInvoiceDiscount - appliedInvoiceDiscount) /
              beforeInvoiceDiscount;
    final tax = _money(taxBeforeProration * ratio);
    final grandTotal = _money(
      beforeInvoiceDiscount - appliedInvoiceDiscount + tax,
    );
    final paid = _money(
      payments.fold(0, (sum, value) => sum + math.max(0, value)),
    );
    return SaleTotals(
      subtotal: subtotal,
      lineDiscount: lineDiscount,
      invoiceDiscount: appliedInvoiceDiscount,
      tax: tax,
      grandTotal: grandTotal,
      paid: paid,
      change: _money(math.max(0, paid - grandTotal)),
      balanceDue: _money(math.max(0, grandTotal - paid)),
    );
  }

  static double _money(num value) => (value * 100).round() / 100;
}
