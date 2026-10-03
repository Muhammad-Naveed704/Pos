import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

/// A printer installed on this PC.
class NativePrinter {
  const NativePrinter(this.name, {this.isDefault = false});
  final String name;
  final bool isDefault;
}

/// One rendered PDF page in BGRA byte order (top-down, no padding).
class RasterPage {
  const RasterPage(this.width, this.height, this.bgra);
  final int width;
  final int height;
  final Uint8List bgra;
}

class NativePrintException implements Exception {
  const NativePrintException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Windows printing and PDF rasterising on background isolates.
///
/// The `printing` plugin does all of this on the Windows platform thread:
/// listing printers (which can contact network print servers), spooling the
/// job through the printer driver and rendering pages. A slow or offline
/// printer then froze the whole window ("Not Responding"). Here the same work
/// runs through dart:ffi (GDI, winspool and the bundled pdfium.dll) on a
/// background isolate. PDFium is not thread-safe, so its calls are queued.
abstract final class WindowsPrinting {
  static bool? _available;

  /// True on Windows when pdfium.dll ships next to the executable.
  static bool get available => _available ??= _probe();

  static bool _probe() {
    if (!Platform.isWindows) return false;
    try {
      DynamicLibrary.open('pdfium.dll');
      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<void> _queue = Future.value();

  static Future<T> _serial<T>(Future<T> Function() task) {
    final result = _queue.then((_) => task());
    _queue = result.then((_) {}, onError: (_) {});
    return result;
  }

  static Future<List<NativePrinter>> listPrinters() =>
      Isolate.run(_listPrinters);

  /// Prints [pdf] on [printer]. Roll paper gets a custom page of the
  /// document's length so thermal printers cut right after the receipt.
  static Future<void> printPdf({
    required String printer,
    required String documentName,
    required Uint8List pdf,
    bool rollPaper = false,
    double paperWidthMm = 0,
    int paperSizeCode = 0,

    /// Spool to this file instead of the device (used for diagnostics).
    String? outputFile,
  }) => _serial(
    () => Isolate.run(
      () => _print(
        printer,
        documentName,
        pdf,
        rollPaper,
        paperWidthMm,
        paperSizeCode,
        outputFile,
      ),
    ),
  );

  static Future<List<RasterPage>> raster(Uint8List pdf, double dpi) =>
      _serial(() => Isolate.run(() => _raster(pdf, dpi)));
}

// ---------------------------------------------------------------------------
// Bindings (resolved inside the worker isolate)
// ---------------------------------------------------------------------------

typedef _VoidPtr = Pointer<Void>;

final class _Pdfium {
  _Pdfium() : _lib = DynamicLibrary.open('pdfium.dll') {
    _lib.lookupFunction<Void Function(), void Function()>('FPDF_InitLibrary')();
  }

  final DynamicLibrary _lib;

  late final loadMemDocument = _lib
      .lookupFunction<
        _VoidPtr Function(_VoidPtr, Size, Pointer<Utf8>),
        _VoidPtr Function(_VoidPtr, int, Pointer<Utf8>)
      >('FPDF_LoadMemDocument64');
  late final closeDocument = _lib
      .lookupFunction<Void Function(_VoidPtr), void Function(_VoidPtr)>(
        'FPDF_CloseDocument',
      );
  late final pageCount = _lib
      .lookupFunction<Int32 Function(_VoidPtr), int Function(_VoidPtr)>(
        'FPDF_GetPageCount',
      );
  late final loadPage = _lib
      .lookupFunction<
        _VoidPtr Function(_VoidPtr, Int32),
        _VoidPtr Function(_VoidPtr, int)
      >('FPDF_LoadPage');
  late final closePage = _lib
      .lookupFunction<Void Function(_VoidPtr), void Function(_VoidPtr)>(
        'FPDF_ClosePage',
      );
  late final pageWidth = _lib
      .lookupFunction<Double Function(_VoidPtr), double Function(_VoidPtr)>(
        'FPDF_GetPageWidth',
      );
  late final pageHeight = _lib
      .lookupFunction<Double Function(_VoidPtr), double Function(_VoidPtr)>(
        'FPDF_GetPageHeight',
      );
  late final renderPage = _lib
      .lookupFunction<
        Void Function(
          _VoidPtr,
          _VoidPtr,
          Int32,
          Int32,
          Int32,
          Int32,
          Int32,
          Int32,
        ),
        void Function(_VoidPtr, _VoidPtr, int, int, int, int, int, int)
      >('FPDF_RenderPage');
  late final bitmapCreate = _lib
      .lookupFunction<
        _VoidPtr Function(Int32, Int32, Int32),
        _VoidPtr Function(int, int, int)
      >('FPDFBitmap_Create');
  late final bitmapFill = _lib
      .lookupFunction<
        Void Function(_VoidPtr, Int32, Int32, Int32, Int32, Uint32),
        void Function(_VoidPtr, int, int, int, int, int)
      >('FPDFBitmap_FillRect');
  late final renderBitmap = _lib
      .lookupFunction<
        Void Function(
          _VoidPtr,
          _VoidPtr,
          Int32,
          Int32,
          Int32,
          Int32,
          Int32,
          Int32,
        ),
        void Function(_VoidPtr, _VoidPtr, int, int, int, int, int, int)
      >('FPDF_RenderPageBitmap');
  late final bitmapBuffer = _lib
      .lookupFunction<
        Pointer<Uint8> Function(_VoidPtr),
        Pointer<Uint8> Function(_VoidPtr)
      >('FPDFBitmap_GetBuffer');
  late final bitmapStride = _lib
      .lookupFunction<Int32 Function(_VoidPtr), int Function(_VoidPtr)>(
        'FPDFBitmap_GetStride',
      );
  late final bitmapDestroy = _lib
      .lookupFunction<Void Function(_VoidPtr), void Function(_VoidPtr)>(
        'FPDFBitmap_Destroy',
      );

  static const annotations = 0x01;
  static const printing = 0x800;

  /// Loads [pdf] into native memory; call [_Document.close] when done.
  _Document open(Uint8List pdf) {
    final data = malloc<Uint8>(pdf.length);
    data.asTypedList(pdf.length).setAll(0, pdf);
    final doc = loadMemDocument(data.cast(), pdf.length, nullptr);
    if (doc == nullptr) {
      malloc.free(data);
      throw const NativePrintException('The PDF could not be read.');
    }
    return _Document(this, doc, data);
  }
}

final class _Document {
  _Document(this.pdfium, this.handle, this._data);
  final _Pdfium pdfium;
  final _VoidPtr handle;
  final Pointer<Uint8> _data;

  void close() {
    pdfium.closeDocument(handle);
    malloc.free(_data);
  }
}

final class _Gdi {
  _Gdi()
    : _gdi = DynamicLibrary.open('gdi32.dll'),
      _spool = DynamicLibrary.open('winspool.drv');

  final DynamicLibrary _gdi;
  final DynamicLibrary _spool;

  late final enumPrinters = _spool
      .lookupFunction<
        Int32 Function(
          Uint32,
          Pointer<Utf16>,
          Uint32,
          Pointer<Uint8>,
          Uint32,
          Pointer<Uint32>,
          Pointer<Uint32>,
        ),
        int Function(
          int,
          Pointer<Utf16>,
          int,
          Pointer<Uint8>,
          int,
          Pointer<Uint32>,
          Pointer<Uint32>,
        )
      >('EnumPrintersW');
  late final defaultPrinter = _spool
      .lookupFunction<
        Int32 Function(Pointer<Utf16>, Pointer<Uint32>),
        int Function(Pointer<Utf16>, Pointer<Uint32>)
      >('GetDefaultPrinterW');
  late final openPrinter = _spool
      .lookupFunction<
        Int32 Function(Pointer<Utf16>, Pointer<IntPtr>, _VoidPtr),
        int Function(Pointer<Utf16>, Pointer<IntPtr>, _VoidPtr)
      >('OpenPrinterW');
  late final closePrinter = _spool
      .lookupFunction<Int32 Function(IntPtr), int Function(int)>(
        'ClosePrinter',
      );
  late final documentProperties = _spool
      .lookupFunction<
        Int32 Function(
          IntPtr,
          IntPtr,
          Pointer<Utf16>,
          Pointer<Uint8>,
          Pointer<Uint8>,
          Uint32,
        ),
        int Function(
          int,
          int,
          Pointer<Utf16>,
          Pointer<Uint8>,
          Pointer<Uint8>,
          int,
        )
      >('DocumentPropertiesW');
  late final createDC = _gdi
      .lookupFunction<
        _VoidPtr Function(
          Pointer<Utf16>,
          Pointer<Utf16>,
          Pointer<Utf16>,
          Pointer<Uint8>,
        ),
        _VoidPtr Function(
          Pointer<Utf16>,
          Pointer<Utf16>,
          Pointer<Utf16>,
          Pointer<Uint8>,
        )
      >('CreateDCW');
  late final startDoc = _gdi
      .lookupFunction<
        Int32 Function(_VoidPtr, Pointer<Uint8>),
        int Function(_VoidPtr, Pointer<Uint8>)
      >('StartDocW');
  late final startPage = _gdi
      .lookupFunction<Int32 Function(_VoidPtr), int Function(_VoidPtr)>(
        'StartPage',
      );
  late final endPage = _gdi
      .lookupFunction<Int32 Function(_VoidPtr), int Function(_VoidPtr)>(
        'EndPage',
      );
  late final endDoc = _gdi
      .lookupFunction<Int32 Function(_VoidPtr), int Function(_VoidPtr)>(
        'EndDoc',
      );
  late final abortDoc = _gdi
      .lookupFunction<Int32 Function(_VoidPtr), int Function(_VoidPtr)>(
        'AbortDoc',
      );
  late final deleteDC = _gdi
      .lookupFunction<Int32 Function(_VoidPtr), int Function(_VoidPtr)>(
        'DeleteDC',
      );
  late final deviceCaps = _gdi
      .lookupFunction<
        Int32 Function(_VoidPtr, Int32),
        int Function(_VoidPtr, int)
      >('GetDeviceCaps');

  static const logPixelsX = 88;
  static const logPixelsY = 90;
  static const physicalWidth = 110;
  static const physicalOffsetX = 112;
  static const physicalOffsetY = 113;
}

// ---------------------------------------------------------------------------
// Worker functions (run inside Isolate.run)
// ---------------------------------------------------------------------------

List<NativePrinter> _listPrinters() {
  final gdi = _Gdi();
  return using((arena) {
    var defaultName = '';
    final size = arena<Uint32>();
    gdi.defaultPrinter(nullptr, size);
    if (size.value > 0) {
      final buffer = arena<Uint16>(size.value).cast<Utf16>();
      if (gdi.defaultPrinter(buffer, size) != 0) {
        defaultName = buffer.toDartString();
      }
    }
    // Level 4 only reads names from the registry; it does not query each
    // (possibly offline network) printer like level 2 does.
    const flags = 0x2 | 0x4; // PRINTER_ENUM_LOCAL | PRINTER_ENUM_CONNECTIONS
    final needed = arena<Uint32>();
    final returned = arena<Uint32>();
    gdi.enumPrinters(flags, nullptr, 4, nullptr, 0, needed, returned);
    if (needed.value == 0) return const <NativePrinter>[];
    final buffer = arena<Uint8>(needed.value);
    if (gdi.enumPrinters(
          flags,
          nullptr,
          4,
          buffer,
          needed.value,
          needed,
          returned,
        ) ==
        0) {
      return const <NativePrinter>[];
    }
    final printers = <NativePrinter>[];
    for (var i = 0; i < returned.value; i++) {
      // PRINTER_INFO_4W: pPrinterName, pServerName, Attributes (24 bytes).
      final entry = (buffer + i * 24).cast<Pointer<Utf16>>();
      final name = entry.value.toDartString();
      printers.add(NativePrinter(name, isDefault: name == defaultName));
    }
    printers.sort((a, b) {
      if (a.isDefault != b.isDefault) return a.isDefault ? -1 : 1;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return printers;
  });
}

/// Printer defaults with the paper set for this document, or null to use
/// the driver defaults unchanged.
Pointer<Uint8> _devMode(
  _Gdi gdi,
  Pointer<Utf16> name,
  Arena arena, {
  required bool roll,
  required double widthMm,
  required double lengthMm,
  required int paperSizeCode,
}) {
  if (!roll && paperSizeCode == 0) return nullptr;
  final handle = arena<IntPtr>();
  if (gdi.openPrinter(name, handle, nullptr) == 0) return nullptr;
  try {
    final size = gdi.documentProperties(
      0,
      handle.value,
      name,
      nullptr,
      nullptr,
      0,
    );
    if (size <= 0) return nullptr;
    final mode = arena<Uint8>(size);
    const outBuffer = 2;
    const inBuffer = 8;
    if (gdi.documentProperties(
          0,
          handle.value,
          name,
          mode,
          nullptr,
          outBuffer,
        ) <
        0) {
      return nullptr;
    }
    // DEVMODEW: dmFields @72, dmPaperSize @78, dmPaperLength @80,
    // dmPaperWidth @82 (tenths of a millimetre).
    final data = ByteData.sublistView(mode.asTypedList(size));
    var fields = data.getUint32(72, Endian.little);
    if (roll) {
      fields |=
          0x2 | 0x4 | 0x8; // DM_PAPERSIZE | DM_PAPERLENGTH | DM_PAPERWIDTH
      data.setInt16(78, 0, Endian.little);
      data.setInt16(
        80,
        (lengthMm * 10).round().clamp(100, 32000),
        Endian.little,
      );
      data.setInt16(
        82,
        (widthMm * 10).round().clamp(100, 32000),
        Endian.little,
      );
    } else {
      fields |= 0x2;
      data.setInt16(78, paperSizeCode, Endian.little);
    }
    data.setUint32(72, fields, Endian.little);
    if (gdi.documentProperties(
          0,
          handle.value,
          name,
          mode,
          mode,
          inBuffer | outBuffer,
        ) <
        0) {
      return nullptr;
    }
    return mode;
  } finally {
    gdi.closePrinter(handle.value);
  }
}

void _print(
  String printer,
  String documentName,
  Uint8List pdf,
  bool roll,
  double widthMm,
  int paperSizeCode,
  String? outputFile,
) {
  final pdfium = _Pdfium();
  final gdi = _Gdi();
  final document = pdfium.open(pdf);
  try {
    using((arena) {
      final pages = pdfium.pageCount(document.handle);
      var lengthMm = 0.0;
      if (roll && pages > 0) {
        final first = pdfium.loadPage(document.handle, 0);
        if (first != nullptr) {
          lengthMm = pdfium.pageHeight(first) / 72 * 25.4;
          pdfium.closePage(first);
        }
      }
      final name = printer.toNativeUtf16(allocator: arena);
      final mode = _devMode(
        gdi,
        name,
        arena,
        roll: roll && lengthMm > 0,
        widthMm: widthMm,
        lengthMm: lengthMm,
        paperSizeCode: paperSizeCode,
      );
      final dc = gdi.createDC(
        'WINSPOOL'.toNativeUtf16(allocator: arena),
        name,
        nullptr,
        mode,
      );
      if (dc == nullptr) {
        throw NativePrintException('Printer "$printer" is not available.');
      }
      try {
        // DOCINFOW: cbSize @0, lpszDocName @8, lpszOutput @16,
        // lpszDatatype @24, fwType @32 (40 bytes on x64).
        final info = arena<Uint8>(40);
        info.cast<Int32>().value = 40;
        (info + 8).cast<Pointer<Utf16>>().value = documentName.toNativeUtf16(
          allocator: arena,
        );
        if (outputFile != null) {
          (info + 16).cast<Pointer<Utf16>>().value = outputFile.toNativeUtf16(
            allocator: arena,
          );
        }
        if (gdi.startDoc(dc, info) <= 0) {
          throw NativePrintException(
            'Printer "$printer" did not accept the job.',
          );
        }
        final dpiX = gdi.deviceCaps(dc, _Gdi.logPixelsX) / 72;
        final dpiY = gdi.deviceCaps(dc, _Gdi.logPixelsY) / 72;
        final offsetX = gdi.deviceCaps(dc, _Gdi.physicalOffsetX);
        final offsetY = gdi.deviceCaps(dc, _Gdi.physicalOffsetY);
        final paperWidth = gdi.deviceCaps(dc, _Gdi.physicalWidth);
        for (var index = 0; index < pages; index++) {
          final page = pdfium.loadPage(document.handle, index);
          if (page == nullptr) continue;
          try {
            gdi.startPage(dc);
            var width = pdfium.pageWidth(page) * dpiX;
            var height = pdfium.pageHeight(page) * dpiY;
            // Fit wider layouts (e.g. 80 mm on a 58 mm printer) to the paper.
            if (paperWidth > 0 && width > paperWidth) {
              final scale = paperWidth / width;
              width *= scale;
              height *= scale;
            }
            pdfium.renderPage(
              dc,
              page,
              -offsetX,
              -offsetY,
              width.round(),
              height.round(),
              0,
              _Pdfium.annotations | _Pdfium.printing,
            );
            gdi.endPage(dc);
          } finally {
            pdfium.closePage(page);
          }
        }
        gdi.endDoc(dc);
      } catch (_) {
        gdi.abortDoc(dc);
        rethrow;
      } finally {
        gdi.deleteDC(dc);
      }
    });
  } finally {
    document.close();
  }
}

List<RasterPage> _raster(Uint8List pdf, double dpi) {
  final pdfium = _Pdfium();
  final document = pdfium.open(pdf);
  try {
    final result = <RasterPage>[];
    final pages = pdfium.pageCount(document.handle);
    for (var index = 0; index < pages; index++) {
      final page = pdfium.loadPage(document.handle, index);
      if (page == nullptr) continue;
      try {
        final width = (pdfium.pageWidth(page) / 72 * dpi).round();
        final height = (pdfium.pageHeight(page) / 72 * dpi).round();
        final bitmap = pdfium.bitmapCreate(width, height, 1);
        if (bitmap == nullptr) continue;
        try {
          pdfium.bitmapFill(bitmap, 0, 0, width, height, 0xFFFFFFFF);
          pdfium.renderBitmap(
            bitmap,
            page,
            0,
            0,
            width,
            height,
            0,
            _Pdfium.annotations,
          );
          final stride = pdfium.bitmapStride(bitmap);
          final source = pdfium
              .bitmapBuffer(bitmap)
              .asTypedList(stride * height);
          final rowBytes = width * 4;
          final pixels = Uint8List(rowBytes * height);
          for (var row = 0; row < height; row++) {
            pixels.setRange(
              row * rowBytes,
              row * rowBytes + rowBytes,
              source,
              row * stride,
            );
          }
          result.add(RasterPage(width, height, pixels));
        } finally {
          pdfium.bitmapDestroy(bitmap);
        }
      } finally {
        pdfium.closePage(page);
      }
    }
    return result;
  } finally {
    document.close();
  }
}
