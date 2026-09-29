import 'package:flutter/foundation.dart';

import '../../../core/money/currency.dart';
import '../../../core/money/money_format.dart';
import '../../pos/domain/pos_cart.dart';

/// Business-wide configuration persisted in `app_settings` (global scope).
@immutable
class BusinessSettings {
  const BusinessSettings({
    this.businessName = '',
    this.currencyCode = 'PKR',
    this.numberStyle = NumberStyle.international,
    this.symbolPosition = SymbolPosition.before,
    this.timezone = 'Asia/Karachi',
    this.taxMode = TaxMode.exclusive,
    this.taxLabel = 'Tax',
    this.taxNumber = '',
    this.receiptHeader = '',
    this.receiptFooter = 'Thank you for your business.',
    this.allowNegativeStock = false,
    this.maxDiscountPercent = 100,
    this.allowPriceOverride = true,
    this.quickCashDenominations = const [100, 500, 1000, 5000],
  });

  static const keyBusinessName = 'business.name';
  static const keyCurrency = 'currency.code';
  static const keyNumberStyle = 'currency.numberStyle';
  static const keySymbolPosition = 'currency.symbolPosition';
  static const keyTimezone = 'timezone';
  static const keyTaxMode = 'tax.mode';
  static const keyTaxLabel = 'tax.label';
  static const keyTaxNumber = 'tax.registrationNumber';
  static const keyReceiptHeader = 'receipt.header';
  static const keyReceiptFooter = 'receipt.footer';
  static const keyAllowNegative = 'inventory.allowNegative';
  static const keyMaxDiscount = 'sales.maxDiscountPercent';
  static const keyAllowOverride = 'sales.allowPriceOverride';
  static const keyQuickCash = 'pos.quickCashDenominations';

  final String businessName;
  final String currencyCode;
  final NumberStyle numberStyle;
  final SymbolPosition symbolPosition;
  final String timezone;
  final TaxMode taxMode;
  final String taxLabel;
  final String taxNumber;
  final String receiptHeader;
  final String receiptFooter;
  final bool allowNegativeStock;
  final double maxDiscountPercent;
  final bool allowPriceOverride;
  final List<int> quickCashDenominations;

  CurrencyInfo get currency => Currencies.byCode(currencyCode);

  MoneyFormatter get formatter => MoneyFormatter(
    currency: currency,
    style: numberStyle,
    symbolPosition: symbolPosition,
  );

  factory BusinessSettings.fromMap(Map<String, String> map) {
    const defaults = BusinessSettings();
    final denominations = (map[keyQuickCash] ?? '')
        .split(',')
        .map((value) => int.tryParse(value.trim()))
        .whereType<int>()
        .where((value) => value > 0)
        .toList();
    return BusinessSettings(
      businessName: map[keyBusinessName] ?? defaults.businessName,
      currencyCode: map[keyCurrency] ?? defaults.currencyCode,
      numberStyle: NumberStyle.byName(map[keyNumberStyle]),
      symbolPosition: map[keySymbolPosition] == SymbolPosition.after.name
          ? SymbolPosition.after
          : SymbolPosition.before,
      timezone: map[keyTimezone] ?? defaults.timezone,
      taxMode:
          TaxMode.values
              .where((mode) => mode.name == map[keyTaxMode])
              .firstOrNull ??
          defaults.taxMode,
      taxLabel: (map[keyTaxLabel] ?? '').trim().isEmpty
          ? defaults.taxLabel
          : map[keyTaxLabel]!.trim(),
      taxNumber: map[keyTaxNumber] ?? defaults.taxNumber,
      receiptHeader: map[keyReceiptHeader] ?? defaults.receiptHeader,
      receiptFooter: map[keyReceiptFooter] ?? defaults.receiptFooter,
      allowNegativeStock: map[keyAllowNegative] == 'true',
      maxDiscountPercent:
          (double.tryParse(map[keyMaxDiscount] ?? '') ??
                  defaults.maxDiscountPercent)
              .clamp(0, 100)
              .toDouble(),
      allowPriceOverride: map.containsKey(keyAllowOverride)
          ? map[keyAllowOverride] == 'true'
          : defaults.allowPriceOverride,
      quickCashDenominations: denominations.isEmpty
          ? defaults.quickCashDenominations
          : denominations,
    );
  }

  Map<String, String> toMap() => {
    keyBusinessName: businessName.trim(),
    keyCurrency: currencyCode,
    keyNumberStyle: numberStyle.name,
    keySymbolPosition: symbolPosition.name,
    keyTimezone: timezone,
    keyTaxMode: taxMode.name,
    keyTaxLabel: taxLabel.trim(),
    keyTaxNumber: taxNumber.trim(),
    keyReceiptHeader: receiptHeader.trim(),
    keyReceiptFooter: receiptFooter.trim(),
    keyAllowNegative: '$allowNegativeStock',
    keyMaxDiscount: maxDiscountPercent.toStringAsFixed(2),
    keyAllowOverride: '$allowPriceOverride',
    keyQuickCash: quickCashDenominations.join(','),
  };

  BusinessSettings copyWith({
    String? businessName,
    String? currencyCode,
    NumberStyle? numberStyle,
    SymbolPosition? symbolPosition,
    String? timezone,
    TaxMode? taxMode,
    String? taxLabel,
    String? taxNumber,
    String? receiptHeader,
    String? receiptFooter,
    bool? allowNegativeStock,
    double? maxDiscountPercent,
    bool? allowPriceOverride,
    List<int>? quickCashDenominations,
  }) => BusinessSettings(
    businessName: businessName ?? this.businessName,
    currencyCode: currencyCode ?? this.currencyCode,
    numberStyle: numberStyle ?? this.numberStyle,
    symbolPosition: symbolPosition ?? this.symbolPosition,
    timezone: timezone ?? this.timezone,
    taxMode: taxMode ?? this.taxMode,
    taxLabel: taxLabel ?? this.taxLabel,
    taxNumber: taxNumber ?? this.taxNumber,
    receiptHeader: receiptHeader ?? this.receiptHeader,
    receiptFooter: receiptFooter ?? this.receiptFooter,
    allowNegativeStock: allowNegativeStock ?? this.allowNegativeStock,
    maxDiscountPercent: maxDiscountPercent ?? this.maxDiscountPercent,
    allowPriceOverride: allowPriceOverride ?? this.allowPriceOverride,
    quickCashDenominations:
        quickCashDenominations ?? this.quickCashDenominations,
  );
}

/// Time zones offered in setup and settings.
const commonTimezones = [
  'Asia/Karachi',
  'Asia/Kolkata',
  'Asia/Dhaka',
  'Asia/Colombo',
  'Asia/Kathmandu',
  'Asia/Kabul',
  'Asia/Dubai',
  'Asia/Riyadh',
  'Asia/Qatar',
  'Asia/Kuala_Lumpur',
  'Asia/Singapore',
  'Asia/Shanghai',
  'Africa/Cairo',
  'Africa/Lagos',
  'Africa/Nairobi',
  'Africa/Johannesburg',
  'Europe/London',
  'Europe/Berlin',
  'Europe/Istanbul',
  'America/New_York',
  'America/Chicago',
  'America/Los_Angeles',
  'America/Toronto',
  'Australia/Sydney',
  'UTC',
];
