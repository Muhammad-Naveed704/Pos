import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../receipts/data/receipt_service.dart';

/// Pre-formatted report content for PDF export (isolate-safe).
class ReportPdfData {
  const ReportPdfData({
    required this.title,
    required this.businessName,
    required this.storeName,
    required this.period,
    required this.kpis,
    required this.headers,
    required this.numeric,
    required this.rows,
    this.footnote,
  });

  final String title;
  final String businessName;
  final String storeName;
  final String period;
  final List<(String, String)> kpis;
  final List<String> headers;
  final List<bool> numeric;
  final List<List<String>> rows;
  final String? footnote;
}

Future<Uint8List> generateReportPdf(ReportPdfData data) =>
    compute(_buildReportPdf, data);

Future<Uint8List> _buildReportPdf(ReportPdfData data) async {
  const accent = PdfColor.fromInt(0xFF1F2937);
  final document = pw.Document(
    theme: pdfSystemTheme(),
    title: data.title,
    creator: 'StoreFlow POS',
  );
  final wide = data.headers.length > 5;
  document.addPage(
    pw.MultiPage(
      pageFormat: (wide ? PdfPageFormat.a4.landscape : PdfPageFormat.a4)
          .copyWith(
            marginLeft: 28,
            marginRight: 28,
            marginTop: 28,
            marginBottom: 28,
          ),
      header: (context) => pw.Container(
        padding: const pw.EdgeInsets.only(bottom: 10),
        margin: const pw.EdgeInsets.only(bottom: 12),
        decoration: const pw.BoxDecoration(
          border: pw.Border(bottom: pw.BorderSide(color: accent, width: 1.5)),
        ),
        child: pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    data.title,
                    style: pw.TextStyle(
                      fontSize: 18,
                      fontWeight: pw.FontWeight.bold,
                      color: accent,
                    ),
                  ),
                  pw.Text(
                    '${data.businessName.isEmpty ? '' : '${data.businessName} · '}${data.storeName}',
                    style: const pw.TextStyle(fontSize: 10),
                  ),
                ],
              ),
            ),
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                pw.Text(data.period, style: const pw.TextStyle(fontSize: 10)),
                pw.Text(
                  'Generated ${DateFormat('d MMM y, h:mm a').format(DateTime.now())}',
                  style: const pw.TextStyle(
                    fontSize: 8,
                    color: PdfColors.grey700,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      footer: (context) => pw.Align(
        alignment: pw.Alignment.centerRight,
        child: pw.Text(
          'Page ${context.pageNumber} of ${context.pagesCount}',
          style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
        ),
      ),
      build: (_) => [
        if (data.kpis.isNotEmpty) ...[
          pw.Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final (label, value) in data.kpis)
                pw.Container(
                  width: 150,
                  padding: const pw.EdgeInsets.all(8),
                  decoration: pw.BoxDecoration(
                    color: const PdfColor.fromInt(0xFFF1F5F9),
                    borderRadius: pw.BorderRadius.circular(4),
                  ),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        label,
                        style: const pw.TextStyle(
                          fontSize: 8,
                          color: PdfColors.grey700,
                        ),
                      ),
                      pw.Text(
                        value,
                        style: pw.TextStyle(
                          fontSize: 12,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          pw.SizedBox(height: 14),
        ],
        if (data.rows.isEmpty)
          pw.Text('No data for this period.')
        else
          pw.TableHelper.fromTextArray(
            headers: data.headers,
            data: data.rows,
            headerStyle: pw.TextStyle(
              fontSize: 9,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.white,
            ),
            headerDecoration: const pw.BoxDecoration(color: accent),
            cellStyle: const pw.TextStyle(fontSize: 8.5),
            cellPadding: const pw.EdgeInsets.symmetric(
              horizontal: 5,
              vertical: 3,
            ),
            oddRowDecoration: const pw.BoxDecoration(
              color: PdfColor.fromInt(0xFFF8FAFC),
            ),
            cellAlignments: {
              for (var i = 0; i < data.numeric.length; i++)
                i: data.numeric[i]
                    ? pw.Alignment.centerRight
                    : pw.Alignment.centerLeft,
            },
            headerAlignments: {
              for (var i = 0; i < data.numeric.length; i++)
                i: data.numeric[i]
                    ? pw.Alignment.centerRight
                    : pw.Alignment.centerLeft,
            },
          ),
        if (data.footnote != null) ...[
          pw.SizedBox(height: 10),
          pw.Text(
            data.footnote!,
            style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
          ),
        ],
      ],
    ),
  );
  return document.save();
}
