import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/database/app_database.dart';
import '../../../core/money/currency.dart';
import '../../../core/money/money_format.dart';
import '../../../core/printing/windows_printing.dart';
import '../../../core/theme/theme_controller.dart';
import '../../history/data/sales_repository.dart';
import '../../settings/domain/business_settings.dart';

/// Asks the user which printer to use; returns the printer name or null to
/// cancel. Overridden at bootstrap with the in-app picker dialog.
typedef PrinterChooser = Future<String?> Function(
  List<Printer> printers,
  String? preferred,
);

final printerChooserProvider = Provider<PrinterChooser?>((ref) => null);

final receiptServiceProvider = Provider<ReceiptService>(
  (ref) => ReceiptService(
    ref.watch(sharedPreferencesProvider),
    chooser: ref.watch(printerChooserProvider),
  ),
);

/// Printer choice is per computer, so it lives in SharedPreferences rather
/// than the shared business database.
class ReceiptPrinterPrefs {
  const ReceiptPrinterPrefs({this.printerName, this.directPrint = false});
  final String? printerName;
  final bool directPrint;
}

class ReceiptService {
  ReceiptService(this._prefs, {this._chooser});
  final SharedPreferences _prefs;
  final PrinterChooser? _chooser;

  static const _printerKey = 'receipt.printerName';
  static const _directKey = 'receipt.directPrint';

  ReceiptPrinterPrefs get printerPrefs => ReceiptPrinterPrefs(
    printerName: _prefs.getString(_printerKey),
    directPrint: _prefs.getBool(_directKey) ?? false,
  );

  Future<void> savePrinterPrefs(ReceiptPrinterPrefs value) async {
    if (value.printerName == null) {
      await _prefs.remove(_printerKey);
    } else {
      await _prefs.setString(_printerKey, value.printerName!);
    }
    await _prefs.setBool(_directKey, value.directPrint);
  }

  Future<List<Printer>> printers() async {
    try {
      if (WindowsPrinting.available) {
        return [
          for (final printer in await WindowsPrinting.listPrinters())
            Printer(
              url: printer.name,
              name: printer.name,
              isDefault: printer.isDefault,
            ),
        ];
      }
      return await Printing.listPrinters();
    } catch (_) {
      return const [];
    }
  }

  Future<Uint8List> generate(SaleDetails details, BusinessSettings settings) =>
      compute(buildReceiptPdf, ReceiptData.fromSale(details, settings));

  Future<Uint8List> generateSample(BusinessSettings settings) =>
      compute(buildReceiptPdf, ReceiptData.sample(settings));

  /// Prints the receipt. Uses the saved printer without a dialog when direct
  /// printing is enabled and that printer is still installed.
  Future<void> printReceipt(
    SaleDetails details,
    BusinessSettings settings,
  ) async {
    final bytes = await generate(details, settings);
    await printBytes(
      bytes,
      name: 'Receipt ${details.summary.sale.invoiceNumber}',
      paper: settings.receipt.paper,
    );
  }

  Future<void> printBytes(
    Uint8List bytes, {
    required String name,
    required ReceiptPaper paper,
  }) async {
    final prefs = printerPrefs;
    if (WindowsPrinting.available) {
      // Spooling runs on a background isolate so a slow, busy or offline
      // printer can never freeze the window.
      var target = prefs.directPrint ? prefs.printerName : null;
      if (target == null) {
        final available = await printers();
        if (available.isEmpty) {
          throw const NativePrintException('No printer is installed.');
        }
        final chooser = _chooser;
        target = chooser == null
            ? (available.where((p) => p.isDefault).firstOrNull ??
                      available.first)
                  .name
            : await chooser(available, prefs.printerName);
        if (target == null) return;
      }
      await WindowsPrinting.printPdf(
        printer: target,
        documentName: name,
        pdf: bytes,
        rollPaper: paper.isRoll,
        paperWidthMm: paper.widthMm,
        paperSizeCode: switch (paper) {
          ReceiptPaper.a4 => 9,
          ReceiptPaper.a5 => 11,
          _ => 0,
        },
      );
      return;
    }
    final format = pageFormatFor(paper);
    if (prefs.directPrint && prefs.printerName != null) {
      final printer = (await printers())
          .where((item) => item.name == prefs.printerName)
          .firstOrNull;
      if (printer != null) {
        await Printing.directPrintPdf(
          printer: printer,
          name: name,
          format: format,
          onLayout: (_) async => bytes,
        );
        return;
      }
    }
    await Printing.layoutPdf(
      name: name,
      format: format,
      onLayout: (_) async => bytes,
    );
  }

  Future<String?> savePdf(
    SaleDetails details,
    BusinessSettings settings,
  ) async {
    final bytes = await generate(details, settings);
    return saveBytes(bytes, '${details.summary.sale.invoiceNumber}.pdf');
  }

  Future<String?> saveBytes(Uint8List bytes, String fileName) async {
    final uri = await FilePicker.saveFile(
      dialogTitle: 'Save PDF',
      fileName: fileName,
      bytes: bytes,
      type: FileType.custom,
      allowedExtensions: ['pdf'],
    );
    if (uri == null) return null;
    final path = uri.scheme == 'file' ? uri.toFilePath() : uri.toString();
    // Desktop pickers may return a path without writing the bytes.
    final file = File(path);
    if (!file.existsSync() || file.lengthSync() == 0) {
      await file.writeAsBytes(bytes, flush: true);
    }
    return path;
  }
}

/// Builds any receipt-style PDF off the UI isolate.
Future<Uint8List> buildReceiptPdfInBackground(ReceiptData data) =>
    compute(buildReceiptPdf, data);

PdfPageFormat pageFormatFor(ReceiptPaper paper) => switch (paper) {
  ReceiptPaper.roll58 => const PdfPageFormat(
    58 * PdfPageFormat.mm,
    double.infinity,
    marginAll: 2.5 * PdfPageFormat.mm,
  ),
  ReceiptPaper.roll80 => const PdfPageFormat(
    80 * PdfPageFormat.mm,
    double.infinity,
    marginAll: 4 * PdfPageFormat.mm,
  ),
  ReceiptPaper.a4 => PdfPageFormat.a4.copyWith(
    marginLeft: 16 * PdfPageFormat.mm,
    marginRight: 16 * PdfPageFormat.mm,
    marginTop: 14 * PdfPageFormat.mm,
    marginBottom: 14 * PdfPageFormat.mm,
  ),
  ReceiptPaper.a5 => PdfPageFormat.a5.copyWith(
    marginLeft: 10 * PdfPageFormat.mm,
    marginRight: 10 * PdfPageFormat.mm,
    marginTop: 10 * PdfPageFormat.mm,
    marginBottom: 10 * PdfPageFormat.mm,
  ),
};

class ReceiptItem {
  const ReceiptItem({
    required this.name,
    required this.sku,
    required this.quantity,
    required this.unitPrice,
    required this.discount,
    required this.tax,
    required this.total,
  });
  final String name;
  final String sku;
  final double quantity;
  final double unitPrice;
  final double discount;
  final double tax;
  final double total;
}

/// Plain, isolate-safe receipt content.
class ReceiptData {
  const ReceiptData({
    required this.layout,
    required this.businessName,
    required this.header,
    required this.footer,
    required this.taxLabel,
    required this.taxNumber,
    required this.currencyCode,
    required this.currencySymbol,
    required this.numberStyle,
    required this.symbolAfter,
    required this.storeName,
    required this.address,
    required this.phone,
    required this.invoice,
    required this.createdAt,
    required this.cashier,
    required this.customer,
    required this.items,
    required this.payments,
    required this.subtotal,
    required this.discount,
    required this.tax,
    required this.total,
    required this.received,
    required this.change,
    this.notes = '',
    this.status = 'completed',
    this.balanceDue = 0,
    this.dueDate,
  });

  factory ReceiptData.fromSale(SaleDetails details, BusinessSettings s) {
    final sale = details.summary.sale;
    return ReceiptData(
      layout: s.receipt,
      businessName: s.businessName,
      header: s.receiptHeader,
      footer: s.receiptFooter,
      taxLabel: s.taxLabel,
      taxNumber: s.taxNumber,
      currencyCode: s.currency.code,
      currencySymbol: s.currency.symbol,
      numberStyle: s.numberStyle.name,
      symbolAfter: s.symbolPosition == SymbolPosition.after,
      storeName: details.store.name,
      address: s.receipt.address.isNotEmpty
          ? s.receipt.address
          : details.store.address,
      phone: s.receipt.phone.isNotEmpty ? s.receipt.phone : details.store.phone,
      invoice: sale.invoiceNumber,
      createdAt: sale.createdAt,
      cashier: details.summary.cashierName,
      customer: details.summary.customerName ?? 'Walk-in customer',
      items: [
        for (final item in details.items)
          ReceiptItem(
            name: item.productNameSnapshot,
            sku: item.skuSnapshot,
            quantity: item.qty,
            unitPrice: item.unitPrice,
            discount: item.discountAmount,
            tax: item.taxAmount,
            total: item.lineTotal,
          ),
      ],
      payments: [
        for (final payment in details.payments)
          (method: payment.method, amount: payment.amount),
      ],
      subtotal: sale.subtotal,
      discount: sale.discountAmount,
      tax: sale.taxAmount,
      total: sale.grandTotal,
      received: sale.paidAmount,
      change: sale.changeAmount,
      notes: sale.notes,
      status: sale.saleStatus,
      balanceDue: sale.creditAmount,
      dueDate: sale.dueDate,
    );
  }

  /// Refund slip for one refund/void of a sale.
  factory ReceiptData.fromRefund(
    SaleDetails details,
    SaleRefund refund,
    List<(SaleRefundItem, String)> items,
    BusinessSettings s,
  ) {
    final base = ReceiptData.fromSale(details, s);
    final skus = {for (final i in details.items) i.id: i.skuSnapshot};
    final amount = refund.amount;
    return ReceiptData(
      layout: s.receipt.copyWith(
        title: refund.kind == 'void' ? 'VOID' : 'REFUND',
      ),
      businessName: base.businessName,
      header: base.header,
      footer: base.footer,
      taxLabel: base.taxLabel,
      taxNumber: base.taxNumber,
      currencyCode: base.currencyCode,
      currencySymbol: base.currencySymbol,
      numberStyle: base.numberStyle,
      symbolAfter: base.symbolAfter,
      storeName: base.storeName,
      address: base.address,
      phone: base.phone,
      invoice: refund.number,
      createdAt: refund.createdAt,
      cashier: base.cashier,
      customer: base.customer,
      items: [
        for (final (item, name) in items)
          ReceiptItem(
            name: name,
            sku: skus[item.saleItemId] ?? '',
            quantity: item.qty,
            unitPrice: item.qty == 0 ? 0 : item.amount / item.qty,
            discount: 0,
            tax: 0,
            total: item.amount,
          ),
      ],
      payments: [(method: 'refund ${refund.method}', amount: amount)],
      subtotal: amount,
      discount: 0,
      tax: 0,
      total: amount,
      received: amount,
      change: 0,
      notes:
          'Original invoice ${details.summary.sale.invoiceNumber}'
          '${refund.reason.isEmpty ? '' : ' · ${refund.reason}'}',
      status: 'refunded',
    );
  }

  /// Example content for the receipt designer preview.
  factory ReceiptData.sample(BusinessSettings s) => ReceiptData(
    layout: s.receipt,
    businessName: s.businessName.isEmpty ? 'Your Business' : s.businessName,
    header: s.receiptHeader,
    footer: s.receiptFooter,
    taxLabel: s.taxLabel,
    taxNumber: s.taxNumber,
    currencyCode: s.currency.code,
    currencySymbol: s.currency.symbol,
    numberStyle: s.numberStyle.name,
    symbolAfter: s.symbolPosition == SymbolPosition.after,
    storeName: 'Main Store',
    address: s.receipt.address.isNotEmpty
        ? s.receipt.address
        : '12 Market Road, City',
    phone: s.receipt.phone.isNotEmpty ? s.receipt.phone : '+00 000 0000000',
    invoice: 'MAIN-${DateTime.now().year}-000123',
    createdAt: DateTime.now(),
    cashier: 'Cashier',
    customer: 'Walk-in customer',
    items: const [
      ReceiptItem(
        name: 'Premium Tea 500g',
        sku: 'TEA-500',
        quantity: 2,
        unitPrice: 450,
        discount: 45,
        tax: 0,
        total: 855,
      ),
      ReceiptItem(
        name: 'Sugar 1kg',
        sku: 'SUG-1',
        quantity: 1.5,
        unitPrice: 160,
        discount: 0,
        tax: 0,
        total: 240,
      ),
      ReceiptItem(
        name: 'Biscuits family pack',
        sku: 'BIS-FAM',
        quantity: 3,
        unitPrice: 120,
        discount: 0,
        tax: 0,
        total: 360,
      ),
    ],
    payments: const [(method: 'cash', amount: 1500)],
    subtotal: 1500,
    discount: 45,
    tax: 0,
    total: 1455,
    received: 1500,
    change: 45,
  );

  final ReceiptLayout layout;
  final String businessName;
  final String header;
  final String footer;
  final String taxLabel;
  final String taxNumber;
  final String currencyCode;
  final String currencySymbol;
  final String numberStyle;
  final bool symbolAfter;
  final String storeName;
  final String address;
  final String phone;
  final String invoice;
  final DateTime createdAt;
  final String cashier;
  final String customer;
  final List<ReceiptItem> items;
  final List<({String method, double amount})> payments;
  final double subtotal;
  final double discount;
  final double tax;
  final double total;
  final double received;
  final double change;
  final String notes;
  final String status;

  /// Left on the customer account at checkout (credit sales).
  final double balanceDue;
  final DateTime? dueDate;
}

// ---------------------------------------------------------------------------
// PDF building (runs in a background isolate)
// ---------------------------------------------------------------------------

class _Fonts {
  const _Fonts(this.base, this.bold, this.fallback);
  final pw.Font? base;
  final pw.Font? bold;
  final List<pw.Font> fallback;

  bool get unicode => base != null;
}

pw.Font? _loadFont(List<String> names) {
  if (!Platform.isWindows) return null;
  final root = Platform.environment['WINDIR'] ?? r'C:\Windows';
  for (final name in names) {
    final file = File('$root\\Fonts\\$name');
    try {
      if (file.existsSync()) {
        final bytes = file.readAsBytesSync();
        return pw.Font.ttf(bytes.buffer.asByteData());
      }
    } catch (_) {
      // Try the next candidate.
    }
  }
  return null;
}

_Fonts _fonts() {
  final base = _loadFont(['segoeui.ttf', 'arial.ttf']);
  final bold = _loadFont(['segoeuib.ttf', 'arialbd.ttf']) ?? base;
  final fallback = [
    ?_loadFont(['Nirmala.ttf', 'NirmalaUI.ttf']),
    ?_loadFont(['seguisym.ttf']),
  ];
  return _Fonts(base, bold, fallback);
}

/// PDF theme using Windows system fonts when available (Unicode currency
/// symbols and scripts); falls back to the built-in Latin-1 fonts.
pw.ThemeData pdfSystemTheme() {
  final fonts = _fonts();
  return fonts.unicode
      ? pw.ThemeData.withFont(
          base: fonts.base,
          bold: fonts.bold,
          fontFallback: fonts.fallback,
        )
      : pw.ThemeData();
}

/// Built-in PDF fonts only cover Latin-1 plus the euro sign.
bool _latin1(String text) =>
    text.runes.every((rune) => rune <= 0xFF || rune == 0x20AC);

String _paidLabel(String method) => method.startsWith('refund ')
    ? 'Refunded (${method.substring(7).toUpperCase()})'
    : 'Paid (${method.toUpperCase()})';

String _quantity(double value) => value == value.roundToDouble()
    ? value.toStringAsFixed(0)
    : value.toStringAsFixed(3).replaceFirst(RegExp(r'0+$'), '');

pw.ImageProvider? _logo(ReceiptLayout layout) {
  if (!layout.showLogo || layout.logoPath.isEmpty) return null;
  try {
    final file = File(layout.logoPath);
    if (!file.existsSync() || file.lengthSync() > 3 * 1024 * 1024) return null;
    return pw.MemoryImage(file.readAsBytesSync());
  } catch (_) {
    return null;
  }
}

Future<Uint8List> buildReceiptPdf(ReceiptData data) async {
  final fonts = _fonts();
  final layout = data.layout;
  final symbol = fonts.unicode || _latin1(data.currencySymbol)
      ? data.currencySymbol
      : data.currencyCode;
  final formatter = MoneyFormatter(
    currency: CurrencyInfo(data.currencyCode, symbol, data.currencyCode, ''),
    style: NumberStyle.byName(data.numberStyle),
    symbolPosition: data.symbolAfter
        ? SymbolPosition.after
        : SymbolPosition.before,
  );
  final theme = fonts.unicode
      ? pw.ThemeData.withFont(
          base: fonts.base,
          bold: fonts.bold,
          fontFallback: fonts.fallback,
        )
      : pw.ThemeData();
  final document = pw.Document(
    theme: theme,
    title: data.invoice,
    author: data.businessName,
    creator: 'StoreFlow POS',
  );
  final ctx = _Ctx(data, formatter, _logo(layout), layout);
  final format = pageFormatFor(layout.paper);
  if (layout.paper.isRoll) {
    // Roll paper has no fixed height, so it must be a single auto-sized Page;
    // MultiPage requires a finite page height.
    document.addPage(pw.Page(pageFormat: format, build: (_) => _rollBody(ctx)));
  } else {
    document.addPage(
      pw.MultiPage(
        pageFormat: format,
        header: (context) =>
            context.pageNumber == 1 ? pw.SizedBox() : _pageHeader(ctx),
        footer: (context) => pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Text(
            'Page ${context.pageNumber} of ${context.pagesCount}',
            style: ctx.small,
          ),
        ),
        build: (_) => _invoiceBody(ctx),
      ),
    );
  }
  return document.save();
}

class _Ctx {
  _Ctx(this.data, this.money, this.logo, this.layout)
    : base =
          switch (layout.paper) {
            ReceiptPaper.roll58 => 7.5,
            ReceiptPaper.roll80 => 8.5,
            ReceiptPaper.a5 => 9.0,
            ReceiptPaper.a4 => 10.0,
          } *
          layout.fontSize.factor;

  final ReceiptData data;
  final MoneyFormatter money;
  final pw.ImageProvider? logo;
  final ReceiptLayout layout;
  final double base;

  pw.TextStyle get text => pw.TextStyle(fontSize: base);
  pw.TextStyle get small => pw.TextStyle(fontSize: base * 0.85);
  pw.TextStyle get bold =>
      pw.TextStyle(fontSize: base, fontWeight: pw.FontWeight.bold);
  pw.TextStyle get title =>
      pw.TextStyle(fontSize: base * 1.6, fontWeight: pw.FontWeight.bold);

  String get documentTitle => layout.title.isNotEmpty
      ? layout.title
      : data.status == 'refunded'
      ? 'REFUND'
      : data.taxNumber.isNotEmpty
      ? 'TAX INVOICE'
      : 'SALES RECEIPT';

  String get heading =>
      data.businessName.isNotEmpty ? data.businessName : data.storeName;

  bool get showStoreLine =>
      layout.showStoreName &&
      data.businessName.isNotEmpty &&
      data.storeName != data.businessName;

  List<String> get contactLines => [
    if (data.address.isNotEmpty) data.address,
    [
      if (data.phone.isNotEmpty) 'Tel: ${data.phone}',
      if (layout.email.isNotEmpty) layout.email,
    ].join('  ·  '),
    if (layout.website.isNotEmpty) layout.website,
    if (data.taxNumber.isNotEmpty) '${data.taxLabel} No: ${data.taxNumber}',
  ].where((line) => line.trim().isNotEmpty).toList();
}

pw.Widget _dashed() => pw.Padding(
  padding: const pw.EdgeInsets.symmetric(vertical: 4),
  child: pw.Divider(
    height: 1,
    thickness: 0.6,
    borderStyle: pw.BorderStyle.dashed,
  ),
);

pw.Widget _row(String label, String value, pw.TextStyle style) => pw.Padding(
  padding: const pw.EdgeInsets.symmetric(vertical: 0.8),
  child: pw.Row(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Expanded(child: pw.Text(label, style: style)),
      pw.SizedBox(width: 6),
      pw.Text(value, style: style),
    ],
  ),
);

pw.Widget _rollBody(_Ctx c) {
  final d = c.data;
  final layout = c.layout;
  final narrow = layout.paper == ReceiptPaper.roll58;
  final totalQty = d.items.fold(0.0, (sum, item) => sum + item.quantity);
  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.stretch,
    children: [
      if (c.logo != null)
        pw.Center(
          child: pw.Image(
            c.logo!,
            height: narrow ? 34 : 46,
            fit: pw.BoxFit.contain,
          ),
        ),
      pw.SizedBox(height: 3),
      pw.Text(c.heading, style: c.title, textAlign: pw.TextAlign.center),
      if (c.showStoreLine)
        pw.Text(d.storeName, style: c.text, textAlign: pw.TextAlign.center),
      for (final line in c.contactLines)
        pw.Text(line, style: c.small, textAlign: pw.TextAlign.center),
      if (d.header.isNotEmpty) ...[
        pw.SizedBox(height: 3),
        pw.Text(d.header, style: c.text, textAlign: pw.TextAlign.center),
      ],
      _dashed(),
      pw.Text(c.documentTitle, style: c.bold, textAlign: pw.TextAlign.center),
      pw.SizedBox(height: 2),
      _row('Invoice', d.invoice, c.bold),
      _row(
        'Date',
        DateFormat('dd MMM yyyy, hh:mm a').format(d.createdAt),
        c.text,
      ),
      if (layout.showCashier) _row('Cashier', d.cashier, c.text),
      if (layout.showCustomer) _row('Customer', d.customer, c.text),
      _dashed(),
      for (final item in d.items)
        pw.Padding(
          padding: const pw.EdgeInsets.symmetric(vertical: 1.5),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(item.name, style: c.bold),
              if (layout.showSku && item.sku.isNotEmpty)
                pw.Text(item.sku, style: c.small),
              _row(
                '${_quantity(item.quantity)} x ${c.money.number(item.unitPrice)}',
                c.money.number(item.total),
                c.text,
              ),
              if (item.discount > 0)
                _row(
                  '  Discount',
                  '-${c.money.number(item.discount)}',
                  c.small,
                ),
            ],
          ),
        ),
      _dashed(),
      _row('Items', '${d.items.length}  (qty ${_quantity(totalQty)})', c.text),
      _row('Subtotal', c.money.major(d.subtotal), c.text),
      if (d.discount > 0)
        _row('Discount', '-${c.money.major(d.discount)}', c.text),
      if (layout.showTaxBreakdown && d.tax > 0)
        _row(d.taxLabel, c.money.major(d.tax), c.text),
      pw.SizedBox(height: 2),
      pw.Container(
        padding: const pw.EdgeInsets.symmetric(vertical: 3),
        decoration: const pw.BoxDecoration(
          border: pw.Border(
            top: pw.BorderSide(width: 1),
            bottom: pw.BorderSide(width: 1),
          ),
        ),
        child: _row(
          'TOTAL',
          c.money.major(d.total),
          pw.TextStyle(fontSize: c.base * 1.3, fontWeight: pw.FontWeight.bold),
        ),
      ),
      pw.SizedBox(height: 2),
      for (final payment in d.payments)
        _row(_paidLabel(payment.method), c.money.major(payment.amount), c.text),
      if (d.change > 0) _row('Change', c.money.major(d.change), c.bold),
      if (d.balanceDue > 0)
        _row('Balance due', c.money.major(d.balanceDue), c.bold),
      if (d.balanceDue > 0 && d.dueDate != null)
        _row('Due date', DateFormat('d MMM y').format(d.dueDate!), c.text),
      if (d.notes.isNotEmpty) ...[
        _dashed(),
        pw.Text('Note: ${d.notes}', style: c.small),
      ],
      if (layout.showBarcode) ...[
        pw.SizedBox(height: 6),
        pw.Center(
          child: pw.BarcodeWidget(
            barcode: pw.Barcode.code128(),
            data: d.invoice,
            width: narrow ? 130 : 170,
            height: narrow ? 30 : 36,
            drawText: false,
          ),
        ),
      ],
      if (layout.policy.isNotEmpty) ...[
        _dashed(),
        pw.Text(layout.policy, style: c.small, textAlign: pw.TextAlign.center),
      ],
      if (d.footer.isNotEmpty) ...[
        pw.SizedBox(height: 5),
        pw.Text(d.footer, style: c.bold, textAlign: pw.TextAlign.center),
      ],
      if (layout.showPoweredBy) ...[
        pw.SizedBox(height: 4),
        pw.Text(
          'Powered by StoreFlow POS',
          style: c.small,
          textAlign: pw.TextAlign.center,
        ),
      ],
    ],
  );
}

pw.Widget _pageHeader(_Ctx c) => pw.Padding(
  padding: const pw.EdgeInsets.only(bottom: 8),
  child: pw.Row(
    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
    children: [
      pw.Text(c.heading, style: c.bold),
      pw.Text('${c.documentTitle} ${c.data.invoice}', style: c.text),
    ],
  ),
);

List<pw.Widget> _invoiceBody(_Ctx c) {
  final d = c.data;
  final layout = c.layout;
  const accent = PdfColor.fromInt(0xFF1F2937);
  const shade = PdfColor.fromInt(0xFFF1F5F9);
  final headers = [
    '#',
    'Item',
    'Qty',
    'Unit price',
    'Discount',
    if (layout.showTaxBreakdown) d.taxLabel,
    'Amount',
  ];
  return [
    pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        if (c.logo != null) ...[
          pw.Image(c.logo!, height: 56, width: 90, fit: pw.BoxFit.contain),
          pw.SizedBox(width: 12),
        ],
        pw.Expanded(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(c.heading, style: c.title),
              if (c.showStoreLine) pw.Text(d.storeName, style: c.text),
              for (final line in c.contactLines) pw.Text(line, style: c.small),
            ],
          ),
        ),
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            pw.Text(
              c.documentTitle,
              style: pw.TextStyle(
                fontSize: c.base * 1.8,
                fontWeight: pw.FontWeight.bold,
                color: accent,
              ),
            ),
            pw.SizedBox(height: 4),
            pw.Text('No. ${d.invoice}', style: c.bold),
            pw.Text(
              DateFormat('dd MMM yyyy, hh:mm a').format(d.createdAt),
              style: c.text,
            ),
            if (layout.showBarcode) ...[
              pw.SizedBox(height: 6),
              pw.BarcodeWidget(
                barcode: pw.Barcode.code128(),
                data: d.invoice,
                width: 150,
                height: 30,
                drawText: false,
              ),
            ],
          ],
        ),
      ],
    ),
    if (d.header.isNotEmpty) ...[
      pw.SizedBox(height: 10),
      pw.Text(d.header, style: c.text),
    ],
    pw.SizedBox(height: 14),
    if (layout.showCustomer || layout.showCashier)
      pw.Container(
        padding: const pw.EdgeInsets.all(8),
        color: shade,
        child: pw.Row(
          children: [
            pw.Expanded(
              child: layout.showCustomer
                  ? pw.Text('Bill to: ${d.customer}', style: c.bold)
                  : pw.SizedBox(),
            ),
            if (layout.showCashier)
              pw.Text('Served by: ${d.cashier}', style: c.text),
          ],
        ),
      ),
    pw.SizedBox(height: 10),
    pw.TableHelper.fromTextArray(
      headerStyle: pw.TextStyle(
        fontSize: c.base,
        fontWeight: pw.FontWeight.bold,
        color: PdfColors.white,
      ),
      headerDecoration: const pw.BoxDecoration(color: accent),
      cellStyle: c.text,
      cellPadding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 4),
      rowDecoration: const pw.BoxDecoration(
        border: pw.Border(
          bottom: pw.BorderSide(color: PdfColors.grey300, width: 0.5),
        ),
      ),
      columnWidths: {1: const pw.FlexColumnWidth(4)},
      cellAlignments: {
        0: pw.Alignment.centerLeft,
        1: pw.Alignment.centerLeft,
        for (var i = 2; i < headers.length; i++) i: pw.Alignment.centerRight,
      },
      headerAlignments: {
        for (var i = 2; i < headers.length; i++) i: pw.Alignment.centerRight,
      },
      headers: headers,
      data: [
        for (var i = 0; i < d.items.length; i++)
          [
            '${i + 1}',
            layout.showSku && d.items[i].sku.isNotEmpty
                ? '${d.items[i].name}\n${d.items[i].sku}'
                : d.items[i].name,
            _quantity(d.items[i].quantity),
            c.money.number(d.items[i].unitPrice),
            d.items[i].discount > 0 ? c.money.number(d.items[i].discount) : '-',
            if (layout.showTaxBreakdown)
              d.items[i].tax > 0 ? c.money.number(d.items[i].tax) : '-',
            c.money.number(d.items[i].total),
          ],
      ],
    ),
    pw.SizedBox(height: 10),
    pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Expanded(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              if (d.notes.isNotEmpty)
                pw.Text('Note: ${d.notes}', style: c.text),
              if (layout.policy.isNotEmpty) ...[
                pw.SizedBox(height: 6),
                pw.Text('Terms & policy', style: c.bold),
                pw.Text(layout.policy, style: c.small),
              ],
            ],
          ),
        ),
        pw.SizedBox(width: 20),
        pw.SizedBox(
          width: 210,
          child: pw.Column(
            children: [
              _row('Subtotal', c.money.major(d.subtotal), c.text),
              if (d.discount > 0)
                _row('Discount', '-${c.money.major(d.discount)}', c.text),
              if (layout.showTaxBreakdown && d.tax > 0)
                _row(d.taxLabel, c.money.major(d.tax), c.text),
              pw.Container(
                margin: const pw.EdgeInsets.symmetric(vertical: 4),
                padding: const pw.EdgeInsets.all(6),
                color: shade,
                child: _row(
                  'Total',
                  c.money.major(d.total),
                  pw.TextStyle(
                    fontSize: c.base * 1.25,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ),
              for (final payment in d.payments)
                _row(
                  _paidLabel(payment.method),
                  c.money.major(payment.amount),
                  c.text,
                ),
              if (d.change > 0) _row('Change', c.money.major(d.change), c.text),
              if (d.balanceDue > 0)
                _row('Balance due', c.money.major(d.balanceDue), c.bold),
              if (d.balanceDue > 0 && d.dueDate != null)
                _row(
                  'Due date',
                  DateFormat('d MMM y').format(d.dueDate!),
                  c.text,
                ),
            ],
          ),
        ),
      ],
    ),
    if (d.footer.isNotEmpty) ...[
      pw.SizedBox(height: 22),
      pw.Center(child: pw.Text(d.footer, style: c.bold)),
    ],
    if (layout.showPoweredBy) ...[
      pw.SizedBox(height: 6),
      pw.Center(child: pw.Text('Powered by StoreFlow POS', style: c.small)),
    ],
  ];
}
