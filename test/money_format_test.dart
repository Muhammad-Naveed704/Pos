import 'package:flutter_test/flutter_test.dart';
import 'package:storeflow_pos/core/money/currency.dart';
import 'package:storeflow_pos/core/money/money.dart';
import 'package:storeflow_pos/core/money/money_format.dart';

void main() {
  group('parseAmount', () {
    test('accepts plain and grouped values in either convention', () {
      expect(parseAmount('1234.5'), 1234.5);
      expect(parseAmount('1,234.50'), 1234.5);
      expect(parseAmount('1.234,50'), 1234.5);
      expect(parseAmount('12,34,567.89'), 1234567.89);
      expect(parseAmount('Rs 1 234.5'), 1234.5);
      expect(parseAmount('12,5'), 12.5);
    });

    test('uses the configured decimal separator for ambiguous input', () {
      // A kilogram quantity of 1.250 must not become 1250 in an en_US store.
      expect(parseAmount('1.250', decimalSeparator: '.'), 1.25);
      expect(parseAmount('1,250', decimalSeparator: '.'), 1250);
      expect(parseAmount('1,250', decimalSeparator: ','), 1.25);
      expect(parseAmount('1.250', decimalSeparator: ','), 1250);
    });

    test('rejects empty or non-numeric input', () {
      expect(parseAmount(''), isNull);
      expect(parseAmount('abc'), isNull);
      expect(parseAmount('-'), isNull);
      expect(parseAmount('-5'), -5);
    });
  });

  group('MoneyFormatter', () {
    test('formats with currency symbol, grouping and position', () {
      final pkr = MoneyFormatter(currency: Currencies.byCode('PKR'));
      expect(pkr.format(Money.fromMajor(1234.5)), 'Rs 1,234.50');
      expect(pkr.format(Money.fromMajor(-2)), '−Rs 2.00');

      final lakh = MoneyFormatter(
        currency: Currencies.byCode('INR'),
        style: NumberStyle.southAsian,
      );
      expect(lakh.major(1234567.89), '₹ 12,34,567.89');

      final euro = MoneyFormatter(
        currency: Currencies.byCode('EUR'),
        style: NumberStyle.european,
        symbolPosition: SymbolPosition.after,
      );
      expect(euro.major(1234.5), '1.234,50 €');
    });

    test('editable text round-trips through parse', () {
      final euro = MoneyFormatter(
        currency: Currencies.byCode('EUR'),
        style: NumberStyle.european,
      );
      final value = Money.fromMajor(1234.56);
      expect(euro.editable(value), '1234,56');
      expect(Money.fromMajor(euro.parse(euro.editable(value))!), value);
    });

    test('unknown currency codes fall back safely', () {
      expect(Currencies.byCode('XXX').code, 'PKR');
      expect(Currencies.byCode(null).code, 'PKR');
    });
  });
}
