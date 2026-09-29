import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../history/data/sales_repository.dart';

final receiptServiceProvider = Provider<ReceiptService>(
  (ref) => ReceiptService(),
);

class ReceiptService {
  Future<Uint8List> generate(SaleDetails details) =>
      compute(_buildReceiptPdf, _ReceiptPayload.fromDetails(details));

  Future<void> printReceipt(SaleDetails details) async {
    final bytes = await generate(details);
    await Printing.layoutPdf(
      name: 'Receipt ${details.summary.sale.invoiceNumber}',
      onLayout: (_) async => bytes,
    );
  }

  Future<String?> savePdf(SaleDetails details) async {
    final bytes = await generate(details);
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

  factory _ReceiptPayload.fromDetails(SaleDetails details) => _ReceiptPayload(
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
        .map(
          (payment) =>
              '${payment.method}: ${payment.amount.toStringAsFixed(2)}',
        )
        .toList(),
    subtotal: details.summary.sale.subtotal,
    discount: details.summary.sale.discountAmount,
    tax: details.summary.sale.taxAmount,
    total: details.summary.sale.grandTotal,
    received: details.summary.sale.paidAmount,
    change: details.summary.sale.changeAmount,
  );

  final String storeName;
  final String address;
  final String phone;
  final String invoice;
  final DateTime createdAt;
  final String cashier;
  final String customer;
  final List<_ReceiptItem> items;
  final List<String> payments;
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

Future<Uint8List> _buildReceiptPdf(_ReceiptPayload data) async {
  final document = pw.Document();
  final money = NumberFormat('#,##0.00');
  document.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.roll80,
      margin: const pw.EdgeInsets.all(12),
      build: (_) => [
        pw.Center(
          child: pw.Column(
            children: [
              pw.Text(
                data.storeName,
                style: pw.TextStyle(
                  fontSize: 15,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              if (data.address.isNotEmpty)
                pw.Text(data.address, textAlign: pw.TextAlign.center),
              if (data.phone.isNotEmpty) pw.Text(data.phone),
            ],
          ),
        ),
        pw.SizedBox(height: 8),
        pw.Divider(),
        pw.Text('Invoice: ${data.invoice}'),
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
                pw.Text(
                  item.name,
                  style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                ),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text(
                      '${item.quantity} × ${money.format(item.unitPrice)}',
                    ),
                    pw.Text(money.format(item.total)),
                  ],
                ),
                if (item.discount > 0)
                  pw.Text('Discount ${money.format(item.discount)}'),
              ],
            ),
          ),
        ),
        pw.Divider(),
        _pdfAmount('Subtotal', data.subtotal, money),
        _pdfAmount('Discount', -data.discount, money),
        _pdfAmount('Tax', data.tax, money),
        pw.SizedBox(height: 3),
        _pdfAmount('TOTAL', data.total, money, bold: true),
        ...data.payments.map(pw.Text.new),
        _pdfAmount('Received', data.received, money),
        _pdfAmount('Change', data.change, money),
        pw.SizedBox(height: 10),
        pw.Center(child: pw.Text('Thank you for your business.')),
      ],
    ),
  );
  return document.save();
}

pw.Widget _pdfAmount(
  String label,
  double value,
  NumberFormat money, {
  bool bold = false,
}) => pw.Row(
  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
  children: [
    pw.Text(
      label,
      style: bold ? pw.TextStyle(fontWeight: pw.FontWeight.bold) : null,
    ),
    pw.Text(
      money.format(value),
      style: bold ? pw.TextStyle(fontWeight: pw.FontWeight.bold) : null,
    ),
  ],
);
