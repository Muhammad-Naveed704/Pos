import 'package:flutter/foundation.dart';

enum ReceiptPaper {
  roll58('58 mm thermal', 58),
  roll80('80 mm thermal', 80),
  a4('A4 invoice', 210),
  a5('A5 invoice', 148);

  const ReceiptPaper(this.label, this.widthMm);
  final String label;
  final double widthMm;

  bool get isRoll => this == roll58 || this == roll80;

  static ReceiptPaper byName(String? name) =>
      values.firstWhere((value) => value.name == name, orElse: () => roll80);
}

enum ReceiptFontSize {
  small('Small', 0.9),
  normal('Normal', 1),
  large('Large', 1.15);

  const ReceiptFontSize(this.label, this.factor);
  final String label;
  final double factor;

  static ReceiptFontSize byName(String? name) =>
      values.firstWhere((value) => value.name == name, orElse: () => normal);
}

/// What the printed receipt / invoice contains and how it is laid out.
@immutable
class ReceiptLayout {
  const ReceiptLayout({
    this.paper = ReceiptPaper.roll80,
    this.fontSize = ReceiptFontSize.normal,
    this.title = '',
    this.logoPath = '',
    this.address = '',
    this.phone = '',
    this.email = '',
    this.website = '',
    this.policy = '',
    this.showLogo = true,
    this.showStoreName = true,
    this.showCashier = true,
    this.showCustomer = true,
    this.showSku = false,
    this.showTaxBreakdown = true,
    this.showBarcode = true,
    this.showPoweredBy = true,
  });

  static const _prefix = 'receipt.';
  static const keys = [
    'receipt.paper',
    'receipt.fontSize',
    'receipt.title',
    'receipt.logoPath',
    'receipt.address',
    'receipt.phone',
    'receipt.email',
    'receipt.website',
    'receipt.policy',
    'receipt.showLogo',
    'receipt.showStoreName',
    'receipt.showCashier',
    'receipt.showCustomer',
    'receipt.showSku',
    'receipt.showTaxBreakdown',
    'receipt.showBarcode',
    'receipt.showPoweredBy',
  ];

  final ReceiptPaper paper;
  final ReceiptFontSize fontSize;

  /// Document title; empty means automatic ("Tax invoice" when a tax number
  /// is configured, otherwise "Sales receipt").
  final String title;
  final String logoPath;

  /// Overrides for the store address/phone; empty uses the store's values.
  final String address;
  final String phone;
  final String email;
  final String website;

  /// Return/exchange policy printed above the footer.
  final String policy;
  final bool showLogo;
  final bool showStoreName;
  final bool showCashier;
  final bool showCustomer;
  final bool showSku;
  final bool showTaxBreakdown;
  final bool showBarcode;
  final bool showPoweredBy;

  factory ReceiptLayout.fromMap(Map<String, String> map) {
    const d = ReceiptLayout();
    String text(String key, String fallback) => map['$_prefix$key'] ?? fallback;
    bool flag(String key, bool fallback) {
      final value = map['$_prefix$key'];
      return value == null ? fallback : value == 'true';
    }

    return ReceiptLayout(
      paper: ReceiptPaper.byName(map['${_prefix}paper']),
      fontSize: ReceiptFontSize.byName(map['${_prefix}fontSize']),
      title: text('title', d.title),
      logoPath: text('logoPath', d.logoPath),
      address: text('address', d.address),
      phone: text('phone', d.phone),
      email: text('email', d.email),
      website: text('website', d.website),
      policy: text('policy', d.policy),
      showLogo: flag('showLogo', d.showLogo),
      showStoreName: flag('showStoreName', d.showStoreName),
      showCashier: flag('showCashier', d.showCashier),
      showCustomer: flag('showCustomer', d.showCustomer),
      showSku: flag('showSku', d.showSku),
      showTaxBreakdown: flag('showTaxBreakdown', d.showTaxBreakdown),
      showBarcode: flag('showBarcode', d.showBarcode),
      showPoweredBy: flag('showPoweredBy', d.showPoweredBy),
    );
  }

  Map<String, String> toMap() => {
    '${_prefix}paper': paper.name,
    '${_prefix}fontSize': fontSize.name,
    '${_prefix}title': title.trim(),
    '${_prefix}logoPath': logoPath.trim(),
    '${_prefix}address': address.trim(),
    '${_prefix}phone': phone.trim(),
    '${_prefix}email': email.trim(),
    '${_prefix}website': website.trim(),
    '${_prefix}policy': policy.trim(),
    '${_prefix}showLogo': '$showLogo',
    '${_prefix}showStoreName': '$showStoreName',
    '${_prefix}showCashier': '$showCashier',
    '${_prefix}showCustomer': '$showCustomer',
    '${_prefix}showSku': '$showSku',
    '${_prefix}showTaxBreakdown': '$showTaxBreakdown',
    '${_prefix}showBarcode': '$showBarcode',
    '${_prefix}showPoweredBy': '$showPoweredBy',
  };

  ReceiptLayout copyWith({
    ReceiptPaper? paper,
    ReceiptFontSize? fontSize,
    String? title,
    String? logoPath,
    String? address,
    String? phone,
    String? email,
    String? website,
    String? policy,
    bool? showLogo,
    bool? showStoreName,
    bool? showCashier,
    bool? showCustomer,
    bool? showSku,
    bool? showTaxBreakdown,
    bool? showBarcode,
    bool? showPoweredBy,
  }) => ReceiptLayout(
    paper: paper ?? this.paper,
    fontSize: fontSize ?? this.fontSize,
    title: title ?? this.title,
    logoPath: logoPath ?? this.logoPath,
    address: address ?? this.address,
    phone: phone ?? this.phone,
    email: email ?? this.email,
    website: website ?? this.website,
    policy: policy ?? this.policy,
    showLogo: showLogo ?? this.showLogo,
    showStoreName: showStoreName ?? this.showStoreName,
    showCashier: showCashier ?? this.showCashier,
    showCustomer: showCustomer ?? this.showCustomer,
    showSku: showSku ?? this.showSku,
    showTaxBreakdown: showTaxBreakdown ?? this.showTaxBreakdown,
    showBarcode: showBarcode ?? this.showBarcode,
    showPoweredBy: showPoweredBy ?? this.showPoweredBy,
  );
}
