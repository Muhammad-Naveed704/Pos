import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';

import 'currency.dart';
import 'money.dart';

/// Formats and parses amounts according to the business regional settings.
@immutable
class MoneyFormatter {
  MoneyFormatter({
    required this.currency,
    this.style = NumberStyle.international,
    this.symbolPosition = SymbolPosition.before,
  }) : _number = NumberFormat.decimalPatternDigits(
         locale: style.locale,
         decimalDigits: 2,
       ),
       _compact = NumberFormat.compact(locale: 'en_US');

  final CurrencyInfo currency;
  final NumberStyle style;
  final SymbolPosition symbolPosition;
  final NumberFormat _number;
  final NumberFormat _compact;

  String get symbol => currency.symbol;

  /// Plain grouped number without a currency symbol, e.g. `1,234.50`.
  String number(num value) => _number.format(value);

  String _withSymbol(String digits, bool negative) {
    final sign = negative ? '−' : '';
    return symbolPosition == SymbolPosition.before
        ? '$sign$symbol $digits'
        : '$sign$digits $symbol';
  }

  String format(Money value) => _withSymbol(
    _number.format(value.minorUnits.abs() / 100),
    value.minorUnits < 0,
  );

  String major(num value) =>
      _withSymbol(_number.format(value.abs()), value < 0);

  /// Short form for dashboards, e.g. `Rs 12.4K`.
  String compact(num value) =>
      _withSymbol(_compact.format(value.abs()), value < 0);

  /// Editable text for an amount field. Uses the locale decimal separator but
  /// no grouping so the value can be edited and parsed back safely.
  String editable(Money value) {
    final text = value.toString();
    return _number.symbols.DECIMAL_SEP == ','
        ? text.replaceAll('.', ',')
        : text;
  }

  String get decimalSeparator => _number.symbols.DECIMAL_SEP;

  /// Parses user input leniently. See [parseAmount].
  double? parse(String input) =>
      parseAmount(input, decimalSeparator: decimalSeparator);
}

/// Parses a typed amount, accepting either `.` or `,` as the decimal mark and
/// ignoring grouping characters and currency symbols.
///
/// When both marks appear, the last one is the decimal mark (`1,234.50`,
/// `1.234,50`). A mark repeated more than once is grouping (`1,234,567`). A
/// single mark is the decimal mark unless it is followed by exactly three
/// digits and differs from [decimalSeparator] (`1,234` in an en_US store).
double? parseAmount(String input, {String? decimalSeparator}) {
  var text = input.trim().replaceAll(RegExp(r'[^0-9,.\-]'), '');
  if (text.isEmpty || text == '-') return null;
  final negative = text.startsWith('-');
  text = text.replaceAll('-', '');
  final lastDot = text.lastIndexOf('.');
  final lastComma = text.lastIndexOf(',');
  final decimalIndex = lastDot > lastComma ? lastDot : lastComma;
  String normalized;
  if (decimalIndex == -1) {
    normalized = text;
  } else {
    final separator = text[decimalIndex];
    final occurrences = separator.allMatches(text).length;
    final fraction = text.substring(decimalIndex + 1);
    final mixed = lastDot != -1 && lastComma != -1;
    final looksLikeGrouping =
        !mixed &&
        (occurrences > 1 ||
            (fraction.length == 3 && separator != decimalSeparator));
    if (looksLikeGrouping) {
      normalized = text.replaceAll(separator, '');
    } else {
      normalized =
          '${text.substring(0, decimalIndex).replaceAll(RegExp('[,.]'), '')}'
          '.$fraction';
    }
  }
  final value = double.tryParse(normalized);
  if (value == null) return null;
  return negative ? -value : value;
}
