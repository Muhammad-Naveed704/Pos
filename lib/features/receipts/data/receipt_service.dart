import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../../core/money/currency.dart';
import '../../../core/money/money_format.dart';
import '../../history/data/sales_repository.dart';
import '../../settings/domain/business_settings.dart';

final receiptServiceProvider = Provider<ReceiptService>(
  (ref) => ReceiptService(),
);

class ReceiptService {
  Future<Uint8List> generate(SaleDetails details, BusinessSettings settings) =>
      compute(_buildReceiptPdf, _ReceiptPayload.fromDetails(details, settings));

  Future<void> printReceipt(
    SaleDetails details,
    BusinessSettings settings,
  ) async {
    final bytes = await generate(details, settings);
    await Printing.layoutPdf(
      name: 'Receipt ${details.summary.sale.invoiceNumber}',
      onLayout: (_) async => bytes,
    );
  }

  Future<String?> savePdf(
    SaleDetails details,
    BusinessSettings settings,
  ) async {
    final bytes = await generate(details, settings);
    final uri = await FilePicker.saveFile(
      dialogTitle: 'Save receipt PDF',
      fileName: '${details.summary.sale.invoiceNumber}.pdf',
      bytes: bytes,
      mimeType: 'application/pdf',
      type: FileType.custom,
      allowedExtensions: ['pdf'],
    );
    if (uri == null) return null;
    return uri.scheme == 'file' ? uri.toFilePath() : uri.toString();
  }
}

class _ReceiptPayload {
  const _ReceiptPayload({
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
  });

  factory _ReceiptPayload.fromDetails(
    SaleDetails details,
    BusinessSettings settings,
  ) => _ReceiptPayload(
    businessName: settings.businessName,
    header: settings.receiptHeader,
    footer: settings.receiptFooter,
    taxLabel: settings.taxLabel,
    taxNumber: settings.taxNumber,
    currencyCode: settings.currency.code,
    currencySymbol: settings.currency.symbol,
    numberStyle: settings.numberStyle.name,
    symbolAfter: settings.symbolPosition == SymbolPosition.after,
    storeName: details.store.name,
    address: details.store.address,
    phone: details.store.phone,
    invoice: details.summary.sale.invoiceNumber,
    createdAt: details.summary.sale.createdAt,
    cashier: details.summary.cashierName,
    customer: details.summary.customerName ?? 'Walk-in customer',
    items: details.items
        .map(
          (item) => _ReceiptItem(
            name: item.productNameSnapshot,
            quantity: item.qty,
            unitPrice: item.unitPrice,
            discount: item.discountAmount,
            tax: item.taxAmount,
            total: item.lineTotal,
          ),
        )
        .toList(),
    payments: details.payments
        .map((payment) => (method: payment.method, amount: payment.amount))
        .toList(),
    subtotal: details.summary.sale.subtotal,
    discount: details.summary.sale.discountAmount,
    tax: details.summary.sale.taxAmount,
    total: details.summary.sale.grandTotal,
    received: details.summary.sale.paidAmount,
    change: details.summary.sale.changeAmount,
  );

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
  final List<_ReceiptItem> items;
  final List<({String method, double amount})> payments;
  final double subtotal;
  final double discount;
  final double tax;
  final double total;
  final double received;
  final double change;
}

class _ReceiptItem {
  const _ReceiptItem({
    required this.name,
    required this.quantity,
    required this.unitPrice,
    required this.discount,
    required this.tax,
    required this.total,
  });
  final String name;
  final double quantity;
  final double unitPrice;
  final double discount;
  final double tax;
  final double total;
}

/// The built-in PDF font covers Latin-1 plus the euro sign only.
bool _pdfSafe(String text) =>
    text.runes.every((rune) => rune <= 0xFF || rune == 0x20AC);

String _quantity(double value) => value == value.roundToDouble()
    ? value.toStringAsFixed(0)
    : value.toStringAsFixed(3).replaceFirst(RegExp(r'0+$'), '');

Future<Uint8List> _buildReceiptPdf(_ReceiptPayload data) async {
  final document = pw.Document();
  final formatter = MoneyFormatter(
    currency: CurrencyInfo(
      data.currencyCode,
      _pdfSafe(data.currencySymbol) ? data.currencySymbol : data.currencyCode,
      data.currencyCode,
      '',
    ),
    style: NumberStyle.byName(data.numberStyle),
    symbolPosition: data.symbolAfter
        ? SymbolPosition.after
        : SymbolPosition.before,
  );
  String money(double value) => formatter.major(value);
  String plain(double value) => formatter.number(value);
  final bold = pw.TextStyle(fontWeight: pw.FontWeight.bold);
  final small = const pw.TextStyle(fontSize: 8);
  final title = data.businessName.isNotEmpty
      ? data.businessName
      : data.storeName;
  document.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.roll80,
      margin: const pw.EdgeInsets.all(12),
      build: (_) => [
        pw.Center(
          child: pw.Column(
            children: [
              pw.Text(
                title,
                textAlign: pw.TextAlign.center,
                style: pw.TextStyle(
                  fontSize: 15,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              if (title != data.storeName) pw.Text(data.storeName),
              if (data.address.isNotEmpty)
                pw.Text(data.address, textAlign: pw.TextAlign.center),
              if (data.phone.isNotEmpty) pw.Text(data.phone),
              if (data.taxNumber.isNotEmpty)
                pw.Text('${data.taxLabel} No: ${data.taxNumber}'),
              if (data.header.isNotEmpty) ...[
                pw.SizedBox(height: 4),
                pw.Text(data.header, textAlign: pw.TextAlign.center),
              ],
            ],
          ),
        ),
        pw.SizedBox(height: 8),
        pw.Divider(),
        pw.Text('Invoice: ${data.invoice}', style: bold),
        pw.Text(
          'Date: ${DateFormat('yyyy-MM-dd HH:mm').format(data.createdAt)}',
        ),
        pw.Text('Cashier: ${data.cashier}'),
        pw.Text('Customer: ${data.customer}'),
        pw.Divider(),
        ...data.items.map(
          (item) => pw.Padding(
            padding: const pw.EdgeInsets.symmetric(vertical: 3),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(item.name, style: bold),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text(
                      '${_quantity(item.quantity)} x ${plain(item.unitPrice)}',
                    ),
                    pw.Text(plain(item.total)),
                  ],
                ),
                if (item.discount > 0)
                  pw.Text('  Discount -${plain(item.discount)}', style: small),
              ],
            ),
          ),
        ),
        pw.Divider(),
        _pdfAmount('Subtotal', money(data.subtotal)),
        if (data.discount > 0)
          _pdfAmount('Discount', '-${money(data.discount)}'),
        if (data.tax > 0) _pdfAmount(data.taxLabel, money(data.tax)),
        pw.SizedBox(height: 3),
        _pdfAmount('TOTAL', money(data.total), bold: true, size: 12),
        pw.SizedBox(height: 4),
        ...data.payments.map(
          (payment) => _pdfAmount(
            'Paid (${payment.method.toUpperCase()})',
            money(payment.amount),
          ),
        ),
        _pdfAmount('Received', money(data.received)),
        _pdfAmount('Change', money(data.change), bold: true),
        pw.SizedBox(height: 10),
        if (data.footer.isNotEmpty)
          pw.Center(
            child: pw.Text(data.footer, textAlign: pw.TextAlign.center),
          ),
        pw.SizedBox(height: 4),
        pw.Center(child: pw.Text('Powered by StoreFlow POS', style: small)),
      ],
    ),
  );
  return document.save();
}

pw.Widget _pdfAmount(
  String label,
  String value, {
  bool bold = false,
  double? size,
}) {
  final style = pw.TextStyle(
    fontWeight: bold ? pw.FontWeight.bold : null,
    fontSize: size,
  );
  return pw.Row(
    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
    children: [
      pw.Text(label, style: style),
      pw.Text(value, style: style),
    ],
  );
}
