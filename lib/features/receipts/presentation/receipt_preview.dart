import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:printing/printing.dart';

import '../../../core/ui/ui_kit.dart';
import '../../history/data/sales_repository.dart';
import '../../settings/data/business_settings_repository.dart';
import '../../settings/domain/business_settings.dart';
import '../data/receipt_service.dart';

/// Renders PDF bytes as page images, sized for desktop dialogs.
class ReceiptPdfView extends StatelessWidget {
  const ReceiptPdfView({required this.bytes, required this.paper, super.key});

  final Future<Uint8List> bytes;
  final ReceiptPaper paper;

  @override
  Widget build(BuildContext context) => PdfPreview(
    build: (_) => bytes,
    useActions: false,
    allowPrinting: false,
    allowSharing: false,
    canChangePageFormat: false,
    canChangeOrientation: false,
    canDebug: false,
    maxPageWidth: paper.isRoll
        ? (paper == ReceiptPaper.roll58 ? 260 : 340)
        : 620,
    scrollViewDecoration: BoxDecoration(
      color: context.colors.surfaceContainerHighest,
    ),
    pdfPreviewPageDecoration: const BoxDecoration(
      color: Colors.white,
      boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 8)],
    ),
    loadingWidget: const Center(child: CircularProgressIndicator()),
    onError: (context, error) => EmptyState(
      icon: Icons.error_outline_rounded,
      title: 'Receipt could not be rendered',
      message: friendlyError(error),
    ),
  );
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
