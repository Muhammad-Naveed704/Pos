import '../../../core/money/money.dart';
import '../../products/data/product_repository.dart';

enum TaxMode { disabled, exclusive, inclusive }

class CartLine {
  const CartLine({
    required this.catalogProduct,
    this.quantityMilli = 1000,
    this.overrideUnitPrice,
    this.manualDiscount = Money.zero,
    this.manualDiscountPercent = 0,
  });

  final CatalogProduct catalogProduct;
  final int quantityMilli;
  final Money? overrideUnitPrice;
  final Money manualDiscount;
  final double manualDiscountPercent;

  String get productId => catalogProduct.product.id;
  Money get unitPrice =>
      overrideUnitPrice ?? Money.fromMajor(catalogProduct.effectivePrice);

  CartLine copyWith({
    int? quantityMilli,
    Money? overrideUnitPrice,
    bool clearPriceOverride = false,
    Money? manualDiscount,
    double? manualDiscountPercent,
  }) => CartLine(
    catalogProduct: catalogProduct,
    quantityMilli: quantityMilli ?? this.quantityMilli,
    overrideUnitPrice: clearPriceOverride
        ? null
        : overrideUnitPrice ?? this.overrideUnitPrice,
    manualDiscount: manualDiscount ?? this.manualDiscount,
    manualDiscountPercent: manualDiscountPercent ?? this.manualDiscountPercent,
  );
}

class CartLineTotals {
  const CartLineTotals({
    required this.gross,
    required this.discount,
    required this.tax,
    required this.total,
  });
  final Money gross;
  final Money discount;
  final Money tax;
  final Money total;
}

class CartTotals {
  const CartTotals({
    required this.subtotal,
    required this.lineDiscount,
    required this.saleDiscount,
    required this.tax,
    required this.grandTotal,
  });
  final Money subtotal;
  final Money lineDiscount;
  final Money saleDiscount;
  final Money tax;
  final Money grandTotal;
}

class PosCart {
  const PosCart({
    this.lines = const [],
    this.customerId,
    this.notes = '',
    this.saleDiscount = Money.zero,
    this.saleDiscountPercent = 0,
  });

  final List<CartLine> lines;
  final String? customerId;
  final String notes;
  final Money saleDiscount;
  final double saleDiscountPercent;

  PosCart copyWith({
    List<CartLine>? lines,
    String? customerId,
    bool clearCustomer = false,
    String? notes,
    Money? saleDiscount,
    double? saleDiscountPercent,
  }) => PosCart(
    lines: lines ?? this.lines,
    customerId: clearCustomer ? null : customerId ?? this.customerId,
    notes: notes ?? this.notes,
    saleDiscount: saleDiscount ?? this.saleDiscount,
    saleDiscountPercent: saleDiscountPercent ?? this.saleDiscountPercent,
  );

  CartLineTotals lineTotals(CartLine line, TaxMode taxMode) {
    final gross = line.unitPrice.multiply(line.quantityMilli / 1000);
    final defaultDiscount = gross.multiply(
      line.catalogProduct.effectiveDiscount.clamp(0, 100) / 100,
    );
    final manualPercent = gross.multiply(
      line.manualDiscountPercent.clamp(0, 100) / 100,
    );
    final requested = defaultDiscount + manualPercent + line.manualDiscount;
    final discount = requested.clamp(Money.zero, gross);
    final afterDiscount = gross - discount;
    final rate = line.catalogProduct.product.taxRate.clamp(0, 100);
    final tax = switch (taxMode) {
      TaxMode.disabled => Money.zero,
      TaxMode.exclusive => afterDiscount.multiply(rate / 100),
      TaxMode.inclusive =>
        rate == 0 ? Money.zero : afterDiscount.multiply(rate / (100 + rate)),
    };
    final total = switch (taxMode) {
      TaxMode.exclusive => afterDiscount + tax,
      TaxMode.disabled || TaxMode.inclusive => afterDiscount,
    };
    return CartLineTotals(
      gross: gross,
      discount: discount,
      tax: tax,
      total: total,
    );
  }

  CartTotals totals(TaxMode taxMode) {
    final calculated = lines.map((line) => lineTotals(line, taxMode));
    var subtotal = Money.zero;
    var lineDiscount = Money.zero;
    var tax = Money.zero;
    var afterLines = Money.zero;
    for (final line in calculated) {
      subtotal += line.gross;
      lineDiscount += line.discount;
      tax += line.tax;
      afterLines += line.total;
    }
    final discountable = (subtotal - lineDiscount).max(Money.zero);
    final requested =
        saleDiscount +
        discountable.multiply(saleDiscountPercent.clamp(0, 100) / 100);
    final appliedSaleDiscount = requested.clamp(Money.zero, discountable);
    final totalBeforeSaleDiscount = afterLines;
    final grandTotal = (totalBeforeSaleDiscount - appliedSaleDiscount).max(
      Money.zero,
    );
    return CartTotals(
      subtotal: subtotal,
      lineDiscount: lineDiscount,
      saleDiscount: appliedSaleDiscount,
      tax: tax,
      grandTotal: grandTotal,
    );
  }
}

class PaymentInput {
  const PaymentInput({
    required this.method,
    required this.amount,
    this.reference,
  });
  final String method;
  final Money amount;
  final String? reference;
}
