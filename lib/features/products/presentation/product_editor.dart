import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../../../core/money/money_format.dart';
import '../../../core/ui/ui_kit.dart';
import '../../auth/application/session_controller.dart';
import '../../auth/domain/permissions.dart';
import '../../scanning/camera_scanner.dart';
import '../../settings/data/business_settings_repository.dart';
import '../data/product_repository.dart';

/// Common selling units, internationally understood.
const productUnits = <(String, String)>[
  ('each', 'Each / piece'),
  ('pcs', 'Pieces (pcs)'),
  ('kg', 'Kilogram (kg)'),
  ('g', 'Gram (g)'),
  ('lb', 'Pound (lb)'),
  ('oz', 'Ounce (oz)'),
  ('l', 'Litre (L)'),
  ('ml', 'Millilitre (ml)'),
  ('m', 'Metre (m)'),
  ('cm', 'Centimetre (cm)'),
  ('ft', 'Foot (ft)'),
  ('box', 'Box'),
  ('pack', 'Pack'),
  ('carton', 'Carton'),
  ('dozen', 'Dozen'),
  ('pair', 'Pair'),
  ('set', 'Set'),
  ('bottle', 'Bottle'),
  ('can', 'Can'),
  ('bag', 'Bag'),
  ('strip', 'Strip'),
  ('roll', 'Roll'),
];

/// EAN-13 check digit for the first 12 digits.
int ean13CheckDigit(String twelve) {
  var sum = 0;
  for (var i = 0; i < 12; i++) {
    final digit = int.parse(twelve[i]);
    sum += i.isEven ? digit : digit * 3;
  }
  return (10 - sum % 10) % 10;
}

/// A random in-store EAN-13 (prefix 20–29 is reserved for internal use).
String generateInStoreEan13([Random? random]) {
  final rng = random ?? Random.secure();
  final body =
      '2${rng.nextInt(10)}${List.generate(10, (_) => rng.nextInt(10)).join()}';
  return '$body${ean13CheckDigit(body)}';
}

/// Opens the product editor. Returns true when saved.
Future<bool> showProductEditor(
  BuildContext context, {
  required List<Category> categories,
  CatalogProduct? item,
}) async =>
    await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _ProductEditor(categories: categories, item: item),
    ) ??
    false;

class _ProductEditor extends ConsumerStatefulWidget {
  const _ProductEditor({required this.categories, this.item});
  final List<Category> categories;
  final CatalogProduct? item;
  @override
  ConsumerState<_ProductEditor> createState() => _ProductEditorState();
}

class _ProductEditorState extends ConsumerState<_ProductEditor> {
  late final MoneyFormatter _money = ref.read(moneyFormatterProvider);
  late final Product? _p = widget.item?.product;
  late final ProductStore? _s = widget.item?.store;

  late final _name = TextEditingController(text: _p?.name ?? '');
  late final _shortName = TextEditingController(text: _p?.shortName ?? '');
  late final _sku = TextEditingController(text: _p?.sku ?? '');
  late final _barcode = TextEditingController(text: _p?.barcode ?? '');
  late final _cost = TextEditingController(text: _n(_p?.costPrice, ''));
  late final _price = TextEditingController(text: _n(_p?.salePrice, ''));
  late final _wholesale = TextEditingController(
    text: _n(_p?.wholesalePrice, ''),
  );
  late final _tax = TextEditingController(text: _n(_p?.taxRate, ''));
  late final _discount = TextEditingController(
    text: _n(_p?.defaultDiscount, ''),
  );
  late final _stock = TextEditingController(text: _n(_s?.stockQty, ''));
  late final _reorder = TextEditingController(text: _n(_s?.reorderLevel, ''));
  late final _storePrice = TextEditingController(
    text: _n(_s?.customSalePrice, ''),
  );
  late final _storeDiscount = TextEditingController(
    text: _n(_s?.customDiscount, ''),
  );
  late final _image = TextEditingController(text: _p?.imagePath ?? '');
  late String? _categoryId = _p?.categoryId;
  late String _unit = _p?.unit ?? 'each';
  late bool _active = _p?.isActive ?? true;
  late bool _tracked = _p?.trackInventory ?? true;
  late bool _available = _s?.isAvailable ?? true;
  final _errors = <String, String>{};
  bool _busy = false;
  String? _error;

  /// Numbers shown with the store's decimal separator so they parse back.
  String _n(num? value, [String empty = '0']) {
    if (value == null) return empty;
    final text = value == value.roundToDouble()
        ? value.toStringAsFixed(0)
        : value.toString();
    return _money.decimalSeparator == ',' ? text.replaceAll('.', ',') : text;
  }

  @override
  void dispose() {
    for (final controller in [
      _name,
      _shortName,
      _sku,
      _barcode,
      _cost,
      _price,
      _wholesale,
      _tax,
      _discount,
      _stock,
      _reorder,
      _storePrice,
      _storeDiscount,
      _image,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  double? _num(TextEditingController controller) =>
      _money.parse(controller.text);

  Future<void> _generateBarcode() async {
    final repository = ref.read(productRepositoryProvider);
    for (var attempt = 0; attempt < 10; attempt++) {
      final code = generateInStoreEan13();
      final used = await repository.codesInUse(barcode: code);
      if (!used.barcode) {
        setState(() {
          _barcode.text = code;
          _errors.remove('barcode');
        });
        return;
      }
    }
  }

  void _suggestSku() {
    final words = _name.text
        .toUpperCase()
        .replaceAll(RegExp('[^A-Z0-9 ]'), '')
        .split(' ')
        .where((w) => w.isNotEmpty)
        .take(2)
        .map((w) => w.length > 4 ? w.substring(0, 4) : w)
        .join('-');
    final suffix = (1000 + Random().nextInt(9000)).toString();
    setState(() {
      _sku.text = words.isEmpty ? 'SKU-$suffix' : '$words-$suffix';
      _errors.remove('sku');
    });
  }

  bool _validate() {
    _errors.clear();
    if (_name.text.trim().isEmpty) _errors['name'] = 'Enter a product name.';
    if (_sku.text.trim().isEmpty) _errors['sku'] = 'Enter or generate a SKU.';
    final price = _num(_price);
    if (price == null || price < 0) _errors['price'] = 'Enter a selling price.';
    for (final (key, controller, label) in [
      ('cost', _cost, 'cost'),
      ('wholesale', _wholesale, 'wholesale price'),
      ('stock', _stock, 'stock'),
      ('reorder', _reorder, 'reorder level'),
      ('storePrice', _storePrice, 'store price'),
    ]) {
      if (controller.text.trim().isNotEmpty && _num(controller) == null) {
        _errors[key] = 'Invalid $label.';
      }
    }
    for (final (key, controller) in [
      ('tax', _tax),
      ('discount', _discount),
      ('storeDiscount', _storeDiscount),
    ]) {
      final value = controller.text.trim().isEmpty ? 0 : _num(controller);
      if (value == null || value < 0 || value > 100) {
        _errors[key] = '0–100 %';
      }
    }
    final barcode = _barcode.text.trim();
    if (RegExp(r'^\d{13}$').hasMatch(barcode) &&
        ean13CheckDigit(barcode) != int.parse(barcode[12])) {
      _errors['barcode'] = 'EAN-13 check digit is wrong.';
    }
    setState(() {});
    return _errors.isEmpty;
  }

  Future<void> _save() async {
    if (!_validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final repository = ref.read(productRepositoryProvider);
      final used = await repository.codesInUse(
        barcode: _barcode.text,
        sku: _sku.text,
        exceptProductId: _p?.id,
      );
      if (used.sku || used.barcode) {
        setState(() {
          if (used.sku) _errors['sku'] = 'Another product uses this SKU.';
          if (used.barcode) {
            _errors['barcode'] = 'Another product uses this barcode.';
          }
        });
        return;
      }
      await repository.save(
        session: ref.read(activeSessionProvider)!,
        id: _p?.id,
        input: ProductInput(
          sku: _sku.text,
          barcode: _barcode.text,
          name: _name.text,
          shortName: _shortName.text,
          categoryId: _categoryId,
          costPrice: _num(_cost) ?? 0,
          salePrice: _num(_price) ?? 0,
          wholesalePrice: _num(_wholesale),
          taxRate: _num(_tax) ?? 0,
          defaultDiscount: _num(_discount) ?? 0,
          unit: _unit,
          imagePath: _image.text,
          isActive: _active,
          trackInventory: _tracked,
          stockQty: _num(_stock) ?? 0,
          reorderLevel: _num(_reorder) ?? 0,
          customSalePrice: _num(_storePrice),
          customDiscount: _num(_storeDiscount),
          isAvailable: _available,
        ),
      );
      if (mounted) {
        Navigator.pop(context, true);
        Toast.success(context, '${_name.text.trim()} saved.');
      }
    } catch (error) {
      if (mounted) setState(() => _error = friendlyError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _field(
    TextEditingController controller,
    String label, {
    String? errorKey,
    bool money = false,
    bool percent = false,
    bool number = false,
    String? helper,
    IconData? icon,
    Widget? suffix,
    bool autofocus = false,
    bool enabled = true,
  }) {
    final numeric = money || percent || number;
    return TextField(
      controller: controller,
      autofocus: autofocus,
      enabled: enabled,
      keyboardType: numeric
          ? const TextInputType.numberWithOptions(decimal: true)
          : null,
      inputFormatters: numeric
          ? [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))]
          : null,
      decoration: InputDecoration(
        labelText: label,
        helperText: helper,
        errorText: errorKey == null ? null : _errors[errorKey],
        prefixIcon: icon == null ? null : Icon(icon, size: 20),
        prefixText: money ? '${_money.symbol} ' : null,
        suffixText: percent ? '%' : null,
        suffixIcon: suffix,
      ),
      onChanged: (_) => setState(() {
        if (errorKey != null) _errors.remove(errorKey);
      }),
    );
  }

  Widget _section(String title, IconData icon, List<Widget> children) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(icon, size: 18, color: context.colors.primary),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: context.text.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      );

  Widget _row(List<Widget> children) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0) const SizedBox(width: 12),
          Expanded(child: children[i]),
        ],
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(activeSessionProvider)!;
    final canStock = session.can(Permissions.inventoryAdjust);
    final cost = _num(_cost) ?? 0;
    final price = _num(_price) ?? 0;
    final margin = price <= 0 ? null : (price - cost) / price * 100;
    final units = [
      for (final (value, label) in productUnits) SelectItem(value, label),
      if (!productUnits.any((u) => u.$1 == _unit)) SelectItem(_unit, _unit),
    ];
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 860, maxHeight: 780),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 16, 8),
              child: PageHeader(
                icon: Icons.inventory_2_outlined,
                title: _p == null ? 'New product' : 'Edit product',
                subtitle: _p == null
                    ? 'Stock and store price apply to ${session.store.name}.'
                    : '${_p.sku} · stock and store price apply to ${session.store.name}.',
                actions: [
                  IconButton(
                    onPressed: _busy
                        ? null
                        : () => Navigator.pop(context, false),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            const Divider(),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(24, 18, 24, 6),
                children: [
                  _section('Basic details', Icons.badge_outlined, [
                    _row([
                      _field(
                        _name,
                        'Product name *',
                        errorKey: 'name',
                        autofocus: true,
                      ),
                      _field(
                        _shortName,
                        'Short name (receipt)',
                        helper: 'Optional, shown on small receipts',
                      ),
                    ]),
                    _row([
                      _field(
                        _sku,
                        'SKU *',
                        errorKey: 'sku',
                        icon: Icons.tag_rounded,
                        suffix: IconButton(
                          tooltip: 'Suggest a SKU from the name',
                          onPressed: _suggestSku,
                          icon: const Icon(
                            Icons.auto_fix_high_rounded,
                            size: 20,
                          ),
                        ),
                      ),
                      _field(
                        _barcode,
                        'Barcode',
                        errorKey: 'barcode',
                        icon: Icons.qr_code_2_rounded,
                        suffix: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            CameraScanButton(
                              onScanned: (code) => setState(() {
                                _barcode.text = code;
                                _errors.remove('barcode');
                              }),
                            ),
                            IconButton(
                              tooltip: 'Generate an in-store EAN-13',
                              onPressed: _generateBarcode,
                              icon: const Icon(
                                Icons.autorenew_rounded,
                                size: 20,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ]),
                    _row([
                      AppSelect<String?>(
                        label: 'Category',
                        icon: Icons.category_outlined,
                        value: _categoryId,
                        searchable: true,
                        items: [
                          const SelectItem(null, 'Uncategorized'),
                          for (final category in widget.categories)
                            SelectItem(category.id, category.name),
                        ],
                        onChanged: (value) =>
                            setState(() => _categoryId = value),
                      ),
                      AppSelect<String>(
                        label: 'Selling unit',
                        icon: Icons.straighten_rounded,
                        value: _unit,
                        searchable: true,
                        items: units,
                        onChanged: (value) =>
                            setState(() => _unit = value ?? _unit),
                      ),
                    ]),
                  ]),
                  _section('Pricing', Icons.sell_outlined, [
                    _row([
                      _field(
                        _cost,
                        'Cost price',
                        errorKey: 'cost',
                        money: true,
                      ),
                      _field(
                        _price,
                        'Selling price *',
                        errorKey: 'price',
                        money: true,
                        helper: margin == null
                            ? null
                            : 'Margin ${margin.toStringAsFixed(1)}%',
                      ),
                      _field(
                        _wholesale,
                        'Wholesale price',
                        errorKey: 'wholesale',
                        money: true,
                      ),
                    ]),
                    _row([
                      _field(_tax, 'Tax rate', errorKey: 'tax', percent: true),
                      _field(
                        _discount,
                        'Default discount',
                        errorKey: 'discount',
                        percent: true,
                      ),
                      const SizedBox.shrink(),
                    ]),
                  ]),
                  _section(
                    'Stock & ${session.store.name}',
                    Icons.warehouse_outlined,
                    [
                      _row([
                        _field(
                          _stock,
                          'Stock on hand',
                          errorKey: 'stock',
                          number: true,
                          enabled: _tracked && (_p == null || canStock),
                          helper: _p != null && !canStock
                              ? 'Needs “Adjust stock” permission'
                              : 'Changes are recorded as stock movements',
                        ),
                        _field(
                          _reorder,
                          'Reorder level',
                          errorKey: 'reorder',
                          number: true,
                          helper: 'Warn when stock falls to this',
                        ),
                        _field(
                          _storePrice,
                          'Store price override',
                          errorKey: 'storePrice',
                          money: true,
                          helper: 'Leave empty to use the selling price',
                        ),
                      ]),
                      _row([
                        _field(
                          _storeDiscount,
                          'Store discount override',
                          errorKey: 'storeDiscount',
                          percent: true,
                        ),
                        _field(
                          _image,
                          'Image file path (optional)',
                          icon: Icons.image_outlined,
                        ),
                        const SizedBox.shrink(),
                      ]),
                      Wrap(
                        spacing: 24,
                        children: [
                          for (final (label, value, setter) in [
                            ('Active', _active, (bool v) => _active = v),
                            ('Track stock', _tracked, (bool v) => _tracked = v),
                            (
                              'Sold in this store',
                              _available,
                              (bool v) => _available = v,
                            ),
                          ])
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Switch(
                                  value: value,
                                  onChanged: (v) => setState(() => setter(v)),
                                ),
                                const SizedBox(width: 6),
                                Text(label),
                              ],
                            ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const Divider(),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
              child: Row(
                children: [
                  Expanded(
                    child: _error != null
                        ? Text(
                            _error!,
                            style: TextStyle(color: context.colors.error),
                          )
                        : _errors.isNotEmpty
                        ? Text(
                            'Please fix the highlighted fields.',
                            style: TextStyle(color: context.colors.error),
                          )
                        : const SizedBox.shrink(),
                  ),
                  TextButton(
                    onPressed: _busy
                        ? null
                        : () => Navigator.pop(context, false),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: _busy ? null : _save,
                    icon: _busy
                        ? const SizedBox.square(
                            dimension: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.check_rounded),
                    label: const Text('Save product'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
