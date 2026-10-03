import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:printing/printing.dart';

import '../../../app/router.dart';
import '../../../core/ui/ui_kit.dart';
import '../data/receipt_service.dart';

/// In-app printer choice, used instead of the native Windows print dialog
/// (which, with the job that follows it, ran on the window thread).
Future<String?> choosePrinter(List<Printer> printers, String? preferred) async {
  final context = rootNavigatorKey.currentContext;
  if (context == null || !context.mounted) {
    return (printers.where((p) => p.isDefault).firstOrNull ?? printers.first)
        .name;
  }
  return showDialog<String>(
    context: context,
    builder: (_) => _PrinterPicker(printers: printers, preferred: preferred),
  );
}

class _PrinterPicker extends ConsumerStatefulWidget {
  const _PrinterPicker({required this.printers, this.preferred});
  final List<Printer> printers;
  final String? preferred;

  @override
  ConsumerState<_PrinterPicker> createState() => _PrinterPickerState();
}

class _PrinterPickerState extends ConsumerState<_PrinterPicker> {
  late String _selected =
      widget.printers
          .where((p) => p.name == widget.preferred)
          .firstOrNull
          ?.name ??
      (widget.printers.where((p) => p.isDefault).firstOrNull ??
              widget.printers.first)
          .name;
  bool _always = false;

  Future<void> _print() async {
    if (_always) {
      await ref
          .read(receiptServiceProvider)
          .savePrinterPrefs(
            ReceiptPrinterPrefs(printerName: _selected, directPrint: true),
          );
    }
    if (mounted) Navigator.pop(context, _selected);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    icon: const Icon(Icons.print_rounded),
    title: const Text('Print to'),
    content: SizedBox(
      width: 440,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 320),
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final printer in widget.printers)
                  ListTile(
                    selected: printer.name == _selected,
                    selectedTileColor: context.colors.primaryContainer,
                    shape: RoundedRectangleBorder(
                      borderRadius: context.tokens.borderRadius,
                    ),
                    leading: Icon(
                      printer.name == _selected
                          ? Icons.radio_button_checked_rounded
                          : Icons.radio_button_off_rounded,
                    ),
                    title: Text(printer.name),
                    subtitle: printer.isDefault
                        ? const Text('Windows default')
                        : null,
                    onTap: () => setState(() => _selected = printer.name),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _always,
            onChanged: (value) => setState(() => _always = value),
            title: const Text('Always print here without asking'),
            subtitle: const Text('Change later in Settings → Receipt designer'),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton.icon(
        autofocus: true,
        onPressed: _print,
        icon: const Icon(Icons.print_rounded),
        label: const Text('Print'),
      ),
    ],
  );
}
