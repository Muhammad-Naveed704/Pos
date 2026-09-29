import 'package:flutter_test/flutter_test.dart';
import 'package:storeflow_pos/features/pos/domain/sale_calculator.dart';

void main() {
  group('SaleCalculator', () {
    test('calculates line discount and tax after discount', () {
      final result = SaleCalculator.line(
        const SaleLineInput(
          quantity: 2,
          unitPrice: 100,
          discount: 10,
          discountKind: DiscountKind.percentage,
          taxRate: 15,
        ),
      );

      expect(result.gross, 200);
      expect(result.discount, 20);
      expect(result.tax, 27);
      expect(result.total, 207);
    });

    test('caps discounts and never produces a negative total', () {
      final result = SaleCalculator.sale(
        lines: const [SaleLineInput(quantity: 1, unitPrice: 50)],
        invoiceDiscount: 500,
      );

      expect(result.invoiceDiscount, 50);
      expect(result.grandTotal, 0);
    });

    test('calculates split payment balance and change', () {
      final partial = SaleCalculator.sale(
        lines: const [SaleLineInput(quantity: 1, unitPrice: 100)],
        payments: const [30, 20],
      );
      final complete = SaleCalculator.sale(
        lines: const [SaleLineInput(quantity: 1, unitPrice: 100)],
        payments: const [60, 50],
      );

      expect(partial.balanceDue, 50);
      expect(partial.change, 0);
      expect(complete.balanceDue, 0);
      expect(complete.change, 10);
    });

    test('rejects invalid quantities', () {
      expect(
        () => SaleCalculator.line(
          const SaleLineInput(quantity: 0, unitPrice: 10),
        ),
        throwsArgumentError,
      );
    });
  });
}
