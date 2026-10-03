import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:printing/printing.dart';

import '../../../core/printing/windows_printing.dart';
import '../../../core/ui/ui_kit.dart';
import '../../history/data/sales_repository.dart';
import '../../settings/data/business_settings_repository.dart';
import '../../settings/domain/business_settings.dart';
import '../data/receipt_service.dart';

/// Renders PDF bytes as page images, sized for desktop dialogs.
///
/// On Windows pages are rasterised with pdfium on a background isolate (the
/// printing plugin does it on the window thread). Rendering happens only when
/// [bytes] changes, and the previous render stays visible meanwhile.
class ReceiptPdfView extends StatefulWidget {
  const ReceiptPdfView({required this.bytes, required this.paper, super.key});

  final Future<Uint8List> bytes;
  final ReceiptPaper paper;

  @override
  State<ReceiptPdfView> createState() => _ReceiptPdfViewState();
}

class _ReceiptPdfViewState extends State<ReceiptPdfView> {
  List<ui.Image> _pages = const [];
  Future<Uint8List>? _rendering;
  bool _busy = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _render();
  }

  @override
  void didUpdateWidget(covariant ReceiptPdfView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.bytes, widget.bytes)) _render();
  }

  @override
  void dispose() {
    _rendering = null;
    for (final page in _pages) {
      page.dispose();
    }
    super.dispose();
  }

  double get _dpi => widget.paper.isRoll ? 144 : 110;

  Future<void> _render() async {
    final source = widget.bytes;
    _rendering = source;
    setState(() {
      _busy = true;
      _error = null;
    });
    final images = <ui.Image>[];
    try {
      final data = await source;
      if (WindowsPrinting.available) {
        for (final page in await WindowsPrinting.raster(data, _dpi)) {
          if (!identical(_rendering, source)) break;
          images.add(await _decode(page));
        }
      } else {
        await for (final page in Printing.raster(data, dpi: _dpi)) {
          if (!identical(_rendering, source)) break;
          images.add(await page.toImage());
        }
      }
    } catch (error) {
      if (mounted && identical(_rendering, source)) {
        setState(() {
          _error = error;
          _busy = false;
        });
      }
      for (final image in images) {
        image.dispose();
      }
      return;
    }
    // A newer render started (or the widget closed): discard this one.
    if (!mounted || !identical(_rendering, source)) {
      for (final image in images) {
        image.dispose();
      }
      return;
    }
    final old = _pages;
    setState(() {
      _pages = images;
      _busy = false;
    });
    for (final image in old) {
      image.dispose();
    }
  }

  static Future<ui.Image> _decode(RasterPage page) {
    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      page.bgra,
      page.width,
      page.height,
      ui.PixelFormat.bgra8888,
      completer.complete,
    );
    return completer.future;
  }

  @override
  Widget build(BuildContext context) {
    final maxWidth = widget.paper.isRoll
        ? (widget.paper == ReceiptPaper.roll58 ? 260.0 : 340.0)
        : 620.0;
    if (_error != null && _pages.isEmpty) {
      return EmptyState(
        icon: Icons.error_outline_rounded,
        title: 'Receipt could not be rendered',
        message: friendlyError(_error!),
      );
    }
    return ColoredBox(
      color: context.colors.surfaceContainerHighest,
      child: Stack(
        children: [
          if (_pages.isEmpty)
            const Center(child: CircularProgressIndicator())
          else
            Scrollbar(
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  for (final page in _pages)
                    Center(
                      child: Container(
                        constraints: BoxConstraints(maxWidth: maxWidth),
                        margin: const EdgeInsets.only(bottom: 16),
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          boxShadow: [
                            BoxShadow(color: Colors.black26, blurRadius: 8),
                          ],
                        ),
                        child: AspectRatio(
                          aspectRatio: page.width / page.height,
                          child: RawImage(
                            image: page,
                            fit: BoxFit.contain,
                            filterQuality: FilterQuality.medium,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          if (_busy && _pages.isNotEmpty)
            const Positioned(
              top: 10,
              right: 12,
              child: SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
        ],
      ),
    );
  }
}

/// Preview a saved sale's receipt with print / save actions.
Future<void> showReceiptPreview(
  BuildContext context,
  WidgetRef ref,
  SaleDetails details,
) {
  final settings = ref.read(currentBusinessSettingsProvider);
  final service = ref.read(receiptServiceProvider);
  final bytes = service.generate(details, settings);
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760, maxHeight: 820),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 18, 12, 10),
              child: Row(
                children: [
                  const IconTile(icon: Icons.receipt_long_rounded),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          details.summary.sale.invoiceNumber,
                          style: dialogContext.text.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          settings.receipt.paper.label,
                          style: TextStyle(
                            color: dialogContext.colors.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: () async {
                      try {
                        final path = await service.saveBytes(
                          await bytes,
                          '${details.summary.sale.invoiceNumber}.pdf',
                        );
                        if (path != null && dialogContext.mounted) {
                          Toast.success(dialogContext, 'Saved $path');
                        }
                      } catch (error) {
                        if (dialogContext.mounted) {
                          Toast.error(dialogContext, error);
                        }
                      }
                    },
                    icon: const Icon(Icons.picture_as_pdf_outlined),
                    label: const Text('Save PDF'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    autofocus: true,
                    onPressed: () async {
                      try {
                        await service.printBytes(
                          await bytes,
                          name: 'Receipt ${details.summary.sale.invoiceNumber}',
                          paper: settings.receipt.paper,
                        );
                      } catch (error) {
                        if (dialogContext.mounted) {
                          Toast.error(dialogContext, error);
                        }
                      }
                    },
                    icon: const Icon(Icons.print_rounded),
                    label: const Text('Print'),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: () => Navigator.pop(dialogContext),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ReceiptPdfView(
                bytes: bytes,
                paper: settings.receipt.paper,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
