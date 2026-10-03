// ignore_for_file: avoid_print
// Diagnostics for lib/core/printing/windows_printing.dart (not part of the
// suite). Needs pdfium.dll in the working directory, e.g. from a build:
//   copy build\windows\x64\runner\Release\pdfium.dll .
//   dart run tool/printing_probe.dart
import 'dart:io';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:storeflow_pos/core/printing/windows_printing.dart';

Future<void> main() async {
  final doc = pw.Document()
    ..addPage(
      pw.Page(
        pageFormat: const PdfPageFormat(
          80 * PdfPageFormat.mm,
          120 * PdfPageFormat.mm,
        ),
        build: (_) => pw.Center(child: pw.Text('StoreFlow probe')),
      ),
    );
  final pdf = await doc.save();
  print('available: ${WindowsPrinting.available}');

  final watch = Stopwatch()..start();
  final printers = await WindowsPrinting.listPrinters();
  print(
    'printers (${watch.elapsedMilliseconds} ms): '
    '${printers.map((p) => '${p.name}${p.isDefault ? ' *' : ''}').join(' | ')}',
  );

  watch.reset();
  final pages = await WindowsPrinting.raster(pdf, 144);
  final page = pages.single;
  final dark = <int>[];
  for (var i = 0; i < page.bgra.length; i += 4) {
    if (page.bgra[i] < 128) dark.add(i);
  }
  print(
    'raster (${watch.elapsedMilliseconds} ms): ${page.width}x${page.height}, '
    'dark pixels ${dark.length}, alpha ${page.bgra[3]}',
  );

  const target = 'Microsoft Print to PDF';
  if (printers.any((p) => p.name == target)) {
    final out =
        '${Directory.systemTemp.path}${Platform.pathSeparator}storeflow-probe.pdf';
    if (File(out).existsSync()) File(out).deleteSync();
    watch.reset();
    await WindowsPrinting.printPdf(
      printer: target,
      documentName: 'StoreFlow probe',
      pdf: pdf,
      rollPaper: true,
      paperWidthMm: 80,
      outputFile: out,
    );
    print(
      'print (${watch.elapsedMilliseconds} ms): '
      '${File(out).existsSync() ? File(out).lengthSync() : 0} bytes at $out',
    );
  }
  try {
    await WindowsPrinting.printPdf(
      printer: 'No Such Printer',
      documentName: 'x',
      pdf: pdf,
    );
  } on NativePrintException catch (e) {
    print('missing printer -> $e');
  }
}
