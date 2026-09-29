import 'package:flutter/foundation.dart';

/// A currency supported by StoreFlow.
///
/// [Money] stores two minor-unit digits, so only currencies with two decimal
/// places are listed. Zero- and three-decimal currencies (JPY, KWD, OMR, BHD)
/// need a `Money` precision migration before they can be offered safely.
@immutable
class CurrencyInfo {
  const CurrencyInfo(this.code, this.symbol, this.name, this.region);

  final String code;
  final String symbol;
  final String name;
  final String region;

  @override
  bool operator ==(Object other) => other is CurrencyInfo && other.code == code;

  @override
  int get hashCode => code.hashCode;
}

abstract final class Currencies {
  static const all = <CurrencyInfo>[
    CurrencyInfo('PKR', 'Rs', 'Pakistani Rupee', 'Pakistan'),
    CurrencyInfo('INR', '₹', 'Indian Rupee', 'India'),
    CurrencyInfo('BDT', '৳', 'Bangladeshi Taka', 'Bangladesh'),
    CurrencyInfo('LKR', 'Rs', 'Sri Lankan Rupee', 'Sri Lanka'),
    CurrencyInfo('NPR', 'Rs', 'Nepalese Rupee', 'Nepal'),
    CurrencyInfo('AFN', '؋', 'Afghan Afghani', 'Afghanistan'),
    CurrencyInfo('AED', 'AED', 'UAE Dirham', 'United Arab Emirates'),
    CurrencyInfo('SAR', 'SAR', 'Saudi Riyal', 'Saudi Arabia'),
    CurrencyInfo('QAR', 'QAR', 'Qatari Riyal', 'Qatar'),
    CurrencyInfo('USD', r'$', 'US Dollar', 'United States'),
    CurrencyInfo('CAD', r'CA$', 'Canadian Dollar', 'Canada'),
    CurrencyInfo('EUR', '€', 'Euro', 'Eurozone'),
    CurrencyInfo('GBP', '£', 'British Pound', 'United Kingdom'),
    CurrencyInfo('CHF', 'CHF', 'Swiss Franc', 'Switzerland'),
    CurrencyInfo('TRY', '₺', 'Turkish Lira', 'Türkiye'),
    CurrencyInfo('EGP', 'E£', 'Egyptian Pound', 'Egypt'),
    CurrencyInfo('NGN', '₦', 'Nigerian Naira', 'Nigeria'),
    CurrencyInfo('KES', 'KSh', 'Kenyan Shilling', 'Kenya'),
    CurrencyInfo('ZAR', 'R', 'South African Rand', 'South Africa'),
    CurrencyInfo('MYR', 'RM', 'Malaysian Ringgit', 'Malaysia'),
    CurrencyInfo('SGD', r'S$', 'Singapore Dollar', 'Singapore'),
    CurrencyInfo('CNY', '¥', 'Chinese Yuan', 'China'),
    CurrencyInfo('AUD', r'A$', 'Australian Dollar', 'Australia'),
  ];

  static CurrencyInfo byCode(String? code) => all.firstWhere(
    (currency) => currency.code == code,
    orElse: () => all.first,
  );
}

/// Number presentation styles. The locale controls grouping and the decimal
/// separator only; digits always stay Latin for scanner/keyboard parity.
enum NumberStyle {
  international('en_US', 'International', '1,234,567.89'),
  southAsian('en_IN', 'South Asian (lakh/crore)', '12,34,567.89'),
  european('de_DE', 'European', '1.234.567,89'),
  spaced('fr_FR', 'Spaced', '1 234 567,89');

  const NumberStyle(this.locale, this.label, this.example);
  final String locale;
  final String label;
  final String example;

  static NumberStyle byName(String? name) => values.firstWhere(
    (style) => style.name == name,
    orElse: () => international,
  );
}

enum SymbolPosition { before, after }
