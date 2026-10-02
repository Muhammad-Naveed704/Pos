import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/ui/ui_kit.dart';
import '../../auth/application/session_controller.dart';
import '../../scanning/camera_scanner.dart';
import '../data/product_repository.dart';

/// Search-as-you-type product field for dialogs (inventory, purchases).
/// Enter with an exact SKU/barcode (e.g. from a scanner) selects directly.
class ProductPicker extends ConsumerStatefulWidget {
  const ProductPicker({
    required this.onSelected,
    this.label = 'Add product (name, SKU or scan barcode)',
    this.autofocus = false,
    this.clearOnSelect = true,
    super.key,
  });

  final ValueChanged<CatalogProduct> onSelected;
  final String label;
  final bool autofocus;
  final bool clearOnSelect;

  @override
  ConsumerState<ProductPicker> createState() => _ProductPickerState();
}

class _ProductPickerState extends ConsumerState<ProductPicker> {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  int _request = 0;

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<List<CatalogProduct>> _search(String term) async {
    final query = term.trim();
    if (query.isEmpty) return const [];
    final request = ++_request;
    await Future<void>.delayed(const Duration(milliseconds: 150));
    if (request != _request) return const [];
    final session = ref.read(activeSessionProvider)!;
    return ref
        .read(productRepositoryProvider)
        .page(storeId: session.store.id, search: query, pageSize: 12);
  }

  void _select(CatalogProduct product) {
    widget.onSelected(product);
    if (widget.clearOnSelect) {
      _controller.clear();
      _focus.requestFocus();
    }
  }

  Future<void> _submit(String value) async {
    final code = value.trim();
    if (code.isEmpty) return;
    final session = ref.read(activeSessionProvider)!;
    final repository = ref.read(productRepositoryProvider);
    final exact = await repository.exactLookup(
      storeId: session.store.id,
      code: code,
    );
    if (exact != null) {
      _select(exact);
      return;
    }
    final matches = await repository.page(
      storeId: session.store.id,
      search: code,
      pageSize: 2,
    );
    if (matches.length == 1) {
      _select(matches.single);
    } else if (mounted) {
      Toast.show(
        context,
        matches.isEmpty
            ? 'No product matches “$code”.'
            : 'Several products match; pick one from the list.',
        tone: PillTone.warning,
      );
    }
  }

  @override
  Widget build(BuildContext context) => RawAutocomplete<CatalogProduct>(
    textEditingController: _controller,
    focusNode: _focus,
    displayStringForOption: (option) => option.product.name,
    optionsBuilder: (value) => _search(value.text),
    onSelected: _select,
    fieldViewBuilder: (context, controller, focusNode, onSubmit) => TextField(
      controller: controller,
      focusNode: focusNode,
      autofocus: widget.autofocus,
      decoration: InputDecoration(
        labelText: widget.label,
        prefixIcon: const Icon(Icons.qr_code_scanner_rounded),
        suffixIcon: CameraScanButton(onScanned: _submit),
      ),
      onSubmitted: _submit,
    ),
    optionsViewBuilder: (context, onSelected, options) => Align(
      alignment: Alignment.topLeft,
      child: Material(
        elevation: 6,
        borderRadius: context.tokens.borderRadius,
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 320, maxWidth: 560),
          child: ListView.builder(
            padding: EdgeInsets.zero,
            shrinkWrap: true,
            itemCount: options.length,
            itemBuilder: (context, index) {
              final option = options.elementAt(index);
              return ListTile(
                dense: true,
                title: Text(option.product.name),
                subtitle: Text(
                  '${option.product.sku}'
                  '${option.product.barcode == null ? '' : ' · ${option.product.barcode}'}',
                ),
                trailing: option.product.trackInventory
                    ? StatusPill(
                        'Stock ${option.store.stockQty.toStringAsFixed(option.store.stockQty == option.store.stockQty.roundToDouble() ? 0 : 2)}',
                      )
                    : null,
                onTap: () => onSelected(option),
              );
            },
          ),
        ),
      ),
    ),
  );
}
