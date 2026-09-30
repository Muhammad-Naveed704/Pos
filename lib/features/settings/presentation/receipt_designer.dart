import 'dart:async';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:printing/printing.dart';

import '../../../core/ui/ui_kit.dart';
import '../../auth/application/session_controller.dart';
import '../../receipts/data/receipt_service.dart';
import '../../receipts/presentation/receipt_preview.dart';
import '../data/business_settings_repository.dart';
import '../domain/business_settings.dart';

/// Settings tab for designing the printed receipt / invoice, with a live
/// preview rendered from the same code that prints real sales.
class ReceiptDesigner extends ConsumerStatefulWidget {
  const ReceiptDesigner({super.key});
  @override
  ConsumerState<ReceiptDesigner> createState() => _ReceiptDesignerState();
}

class _ReceiptDesignerState extends ConsumerState<ReceiptDesigner>
    with AutomaticKeepAliveClientMixin {
  BusinessSettings? _saved;
  late ReceiptLayout _layout;
  final _title = TextEditingController();
  final _address = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _website = TextEditingController();
  final _header = TextEditingController();
  final _policy = TextEditingController();
  final _footer = TextEditingController();
  Timer? _debounce;
  Future<Uint8List>? _preview;
  int _generation = 0;
  bool _saving = false;

  List<Printer>? _printers;
  late ReceiptPrinterPrefs _printerPrefs;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    final service = ref.read(receiptServiceProvider);
    _printerPrefs = service.printerPrefs;
    service.printers().then((value) {
      if (mounted) setState(() => _printers = value);
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    for (final controller in [
      _title,
      _address,
      _phone,
      _email,
      _website,
      _header,
      _policy,
      _footer,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  void _load(BusinessSettings value) {
    _generation++;
    _saved = value;
    _layout = value.receipt;
    _title.text = _layout.title;
    _address.text = _layout.address;
    _phone.text = _layout.phone;
    _email.text = _layout.email;
    _website.text = _layout.website;
    _header.text = value.receiptHeader;
    _policy.text = _layout.policy;
    _footer.text = value.receiptFooter;
    _preview = ref.read(receiptServiceProvider).generateSample(_draft());
  }

  BusinessSettings _draft([BusinessSettings? base]) =>
      (base ?? _saved!).copyWith(
        receiptHeader: _header.text,
        receiptFooter: _footer.text,
        receipt: _layout.copyWith(
          title: _title.text,
          address: _address.text,
          phone: _phone.text,
          email: _email.text,
          website: _website.text,
          policy: _policy.text,
        ),
      );

  bool get _dirty {
    final saved = _saved;
    if (saved == null) return false;
    final a = _draft().toMap();
    final b = saved.toMap();
    return a.keys.any((key) => a[key] != b[key]);
  }

  void _changed() {
    setState(() {});
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      if (mounted) {
        setState(
          () => _preview = ref
              .read(receiptServiceProvider)
              .generateSample(_draft()),
        );
      }
    });
  }

  void _edit(ReceiptLayout Function(ReceiptLayout) change) {
    _layout = change(_layout);
    _changed();
  }

  Future<void> _pickLogo() async {
    final result = await FilePicker.pickFiles(
      dialogTitle: 'Choose a logo',
      type: FileType.custom,
      allowedExtensions: ['png', 'jpg', 'jpeg'],
    );
    final path = result.isEmpty ? null : result.first.path;
    if (path != null) _edit((layout) => layout.copyWith(logoPath: path));
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final latest = await ref.read(businessSettingsRepositoryProvider).load();
      final value = _draft(latest);
      await ref
          .read(businessSettingsRepositoryProvider)
          .save(ref.read(activeSessionProvider)!, value);
      if (!mounted) return;
      setState(() => _load(value));
      Toast.success(context, 'Receipt design saved.');
    } catch (error) {
      if (mounted) Toast.error(context, error);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _savePrinter(ReceiptPrinterPrefs value) async {
    setState(() => _printerPrefs = value);
    await ref.read(receiptServiceProvider).savePrinterPrefs(value);
  }

  Future<void> _testPrint() async {
    try {
      final service = ref.read(receiptServiceProvider);
      final bytes = await service.generateSample(_draft());
      await service.printBytes(
        bytes,
        name: 'StoreFlow test receipt',
        paper: _layout.paper,
      );
    } catch (error) {
      if (mounted) Toast.error(context, error);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final async = ref.watch(businessSettingsProvider);
    if (_saved == null) {
      final value = async.value;
      if (value == null) {
        return const Center(child: CircularProgressIndicator());
      }
      _load(value);
    }
    final dirty = _dirty;
    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            flex: 5,
            child: Column(
              children: [
                Expanded(
                  child: ListView(
                    key: ValueKey(_generation),
                    padding: const EdgeInsets.only(bottom: 20, right: 4),
                    children: _form(context),
                  ),
                ),
                if (dirty)
                  Container(
                    margin: const EdgeInsets.only(bottom: 16),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: context.colors.inverseSurface,
                      borderRadius: context.tokens.borderRadius,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Unsaved receipt changes',
                            style: TextStyle(
                              color: context.colors.onInverseSurface,
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: _saving
                              ? null
                              : () => setState(() => _load(_saved!)),
                          child: Text(
                            'Discard',
                            style: TextStyle(
                              color: context.colors.inversePrimary,
                            ),
                          ),
                        ),
                        FilledButton.icon(
                          onPressed: _saving ? null : _save,
                          icon: const Icon(Icons.save_rounded),
                          label: const Text('Save design'),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            flex: 4,
            child: Card(
              clipBehavior: Clip.antiAlias,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 10, 8),
                    child: Row(
                      children: [
                        Icon(
                          Icons.visibility_outlined,
                          color: context.colors.primary,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Live preview · ${_layout.paper.label}',
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                        TextButton.icon(
                          onPressed: _testPrint,
                          icon: const Icon(Icons.print_outlined, size: 18),
                          label: const Text('Test print'),
                        ),
                      ],
                    ),
                  ),
                  const Divider(),
                  Expanded(
                    child: _preview == null
                        ? const SizedBox.shrink()
                        : ReceiptPdfView(
                            bytes: _preview!,
                            paper: _layout.paper,
                          ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _field(
    TextEditingController controller,
    String label, {
    String? helper,
    int maxLines = 1,
    IconData? icon,
  }) => TextField(
    controller: controller,
    maxLines: maxLines,
    decoration: InputDecoration(
      labelText: label,
      helperText: helper,
      prefixIcon: icon == null ? null : Icon(icon),
    ),
    onChanged: (_) => _changed(),
  );

  Widget _toggle(String title, bool value, ValueChanged<bool> onChanged) =>
      SwitchListTile(
        dense: true,
        contentPadding: EdgeInsets.zero,
        title: Text(title),
        value: value,
        onChanged: onChanged,
      );

  List<Widget> _form(BuildContext context) => [
    SectionCard(
      title: 'Paper & style',
      icon: Icons.straighten_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SegmentedButton<ReceiptPaper>(
            segments: [
              for (final paper in ReceiptPaper.values)
                ButtonSegment(value: paper, label: Text(paper.label)),
            ],
            selected: {_layout.paper},
            onSelectionChanged: (value) =>
                _edit((layout) => layout.copyWith(paper: value.first)),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Text('Text size'),
              const SizedBox(width: 12),
              SegmentedButton<ReceiptFontSize>(
                segments: [
                  for (final size in ReceiptFontSize.values)
                    ButtonSegment(value: size, label: Text(size.label)),
                ],
                selected: {_layout.fontSize},
                onSelectionChanged: (value) =>
                    _edit((layout) => layout.copyWith(fontSize: value.first)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _field(
            _title,
            'Document title',
            helper: 'Leave empty for automatic: “TAX INVOICE” with a tax number, otherwise “SALES RECEIPT”.',
          ),
        ],
      ),
    ),
    const SizedBox(height: 14),
    SectionCard(
      title: 'Logo',
      icon: Icons.image_outlined,
      child: Row(
        children: [
          Expanded(
            child: Text(
              _layout.logoPath.isEmpty ? 'No logo selected' : _layout.logoPath,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (_layout.logoPath.isNotEmpty)
            IconButton(
              tooltip: 'Remove logo',
              onPressed: () => _edit((layout) => layout.copyWith(logoPath: '')),
              icon: const Icon(Icons.delete_outline_rounded),
            ),
          OutlinedButton.icon(
            onPressed: _pickLogo,
            icon: const Icon(Icons.upload_rounded),
            label: const Text('Choose image'),
          ),
        ],
      ),
    ),
    const SizedBox(height: 14),
    SectionCard(
      title: 'Business details on receipt',
      subtitle: 'Empty address/phone use the current store’s details.',
      icon: Icons.storefront_outlined,
      child: Column(
        children: [
          _field(_address, 'Address', icon: Icons.place_outlined, maxLines: 2),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _field(_phone, 'Phone', icon: Icons.phone_outlined),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _field(_email, 'Email', icon: Icons.mail_outline),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _field(_website, 'Website', icon: Icons.language_rounded),
        ],
      ),
    ),
    const SizedBox(height: 14),
    SectionCard(
      title: 'Messages',
      icon: Icons.notes_rounded,
      child: Column(
        children: [
          _field(
            _header,
            'Header message',
            helper: 'Printed under the business details.',
            maxLines: 2,
          ),
          const SizedBox(height: 10),
          _field(
            _policy,
            'Return / exchange policy',
            helper:
                'e.g. Exchange within 7 days with receipt. No cash refunds.',
            maxLines: 3,
          ),
          const SizedBox(height: 10),
          _field(_footer, 'Footer', maxLines: 2),
        ],
      ),
    ),
    const SizedBox(height: 14),
    SectionCard(
      title: 'Show on receipt',
      icon: Icons.checklist_rounded,
      child: Column(
        children: [
          _toggle(
            'Logo',
            _layout.showLogo,
            (v) => _edit((l) => l.copyWith(showLogo: v)),
          ),
          _toggle(
            'Store name (when different from business)',
            _layout.showStoreName,
            (v) => _edit((l) => l.copyWith(showStoreName: v)),
          ),
          _toggle(
            'Cashier name',
            _layout.showCashier,
            (v) => _edit((l) => l.copyWith(showCashier: v)),
          ),
          _toggle(
            'Customer name',
            _layout.showCustomer,
            (v) => _edit((l) => l.copyWith(showCustomer: v)),
          ),
          _toggle(
            'Product SKU',
            _layout.showSku,
            (v) => _edit((l) => l.copyWith(showSku: v)),
          ),
          _toggle(
            'Tax breakdown',
            _layout.showTaxBreakdown,
            (v) => _edit((l) => l.copyWith(showTaxBreakdown: v)),
          ),
          _toggle(
            'Invoice barcode (scan to find the sale)',
            _layout.showBarcode,
            (v) => _edit((l) => l.copyWith(showBarcode: v)),
          ),
          _toggle(
            '“Powered by StoreFlow POS”',
            _layout.showPoweredBy,
            (v) => _edit((l) => l.copyWith(showPoweredBy: v)),
          ),
        ],
      ),
    ),
    const SizedBox(height: 14),
    SectionCard(
      title: 'Printer on this computer',
      subtitle: 'Saved only for this PC.',
      icon: Icons.print_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DropdownButtonFormField<String?>(
            initialValue:
                _printers?.any(
                      (printer) => printer.name == _printerPrefs.printerName,
                    ) ??
                    false
                ? _printerPrefs.printerName
                : null,
            isExpanded: true,
            menuMaxHeight: 320,
            decoration: InputDecoration(
              labelText: 'Receipt printer',
              helperText: _printers == null
                  ? 'Looking for printers…'
                  : _printers!.isEmpty
                  ? 'No printers found. The Windows print dialog will be used.'
                  : null,
            ),
            items: [
              const DropdownMenuItem(
                value: null,
                child: Text('Ask every time (print dialog)'),
              ),
              for (final printer in _printers ?? const <Printer>[])
                DropdownMenuItem(
                  value: printer.name,
                  child: Text(
                    printer.isDefault
                        ? '${printer.name}  (default)'
                        : printer.name,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: (value) => _savePrinter(
              ReceiptPrinterPrefs(
                printerName: value,
                directPrint: value != null && _printerPrefs.directPrint,
              ),
            ),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Print without asking'),
            subtitle: const Text(
              'Send receipts straight to the selected printer.',
            ),
            value: _printerPrefs.directPrint,
            onChanged: _printerPrefs.printerName == null
                ? null
                : (value) => _savePrinter(
                    ReceiptPrinterPrefs(
                      printerName: _printerPrefs.printerName,
                      directPrint: value,
                    ),
                  ),
          ),
        ],
      ),
    ),
  ];
}
