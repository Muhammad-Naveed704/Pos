import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/database/app_database.dart';
import '../../../core/money/money.dart';
import '../../../core/money/money_format.dart';
import '../../../core/ui/ui_kit.dart';
import '../../auth/application/session_controller.dart';
import '../../auth/domain/permissions.dart';
import '../../customers/data/customer_repository.dart';
import '../data/checkout_service.dart';
import '../data/held_cart_repository.dart';
import '../domain/pos_cart.dart';

/// Customer shown on the POS, derived from the cart so it can never drift out
/// of sync (for example after resuming a held cart).
final posCustomerProvider = FutureProvider.family<Customer?, String>(
  (ref, id) => ref.watch(customerRepositoryProvider).byId(id),
);

// ---------------------------------------------------------------------------
// Customer picker
// ---------------------------------------------------------------------------

sealed class CustomerChoice {
  const CustomerChoice();
}

class WalkInChoice extends CustomerChoice {
  const WalkInChoice();
}

class SelectedCustomer extends CustomerChoice {
  const SelectedCustomer(this.customer);
  final Customer customer;
}

Future<CustomerChoice?> showCustomerPicker(BuildContext context) =>
    showDialog<CustomerChoice>(
      context: context,
      builder: (_) => const _CustomerPicker(),
    );

class _CustomerPicker extends ConsumerStatefulWidget {
  const _CustomerPicker();
  @override
  ConsumerState<_CustomerPicker> createState() => _CustomerPickerState();
}

class _CustomerPickerState extends ConsumerState<_CustomerPicker> {
  final _search = TextEditingController();
  Timer? _debounce;
  List<Customer>? _results;
  int _request = 0;
  bool _creating = false;
  final _name = TextEditingController();
  final _phone = TextEditingController();
  String? _error;

  @override
  void initState() {
    super.initState();
    _load('');
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _load(String term) async {
    final request = ++_request;
    final results = await ref.read(customerRepositoryProvider).search(term);
    // Ignore responses that arrive after a newer search was started.
    if (mounted && request == _request) setState(() => _results = results);
  }

  Future<void> _create() async {
    if (_name.text.trim().isEmpty) {
      setState(() => _error = 'Enter a name.');
      return;
    }
    try {
      final repository = ref.read(customerRepositoryProvider);
      final id = await repository.save(
        session: ref.read(activeSessionProvider)!,
        name: _name.text,
        phone: _phone.text,
      );
      final customer = await repository.byId(id);
      if (mounted && customer != null) {
        Navigator.pop(context, SelectedCustomer(customer));
      }
    } catch (error) {
      if (mounted) setState(() => _error = friendlyError(error));
    }
  }

  @override
  Widget build(BuildContext context) {
    final canCreate = ref
        .watch(activeSessionProvider)!
        .can(Permissions.customersCreate);
    final results = _results;
    return AlertDialog(
      title: Text(_creating ? 'New customer' : 'Select customer'),
      content: SizedBox(
        width: 520,
        height: _creating ? 190 : 440,
        child: _creating
            ? Column(
                children: [
                  TextField(
                    controller: _name,
                    autofocus: true,
                    textCapitalization: TextCapitalization.words,
                    decoration: InputDecoration(
                      labelText: 'Name',
                      prefixIcon: const Icon(Icons.person_outline_rounded),
                      errorText: _error,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _phone,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                      labelText: 'Phone',
                      prefixIcon: Icon(Icons.phone_outlined),
                    ),
                    onSubmitted: (_) => _create(),
                  ),
                ],
              )
            : Column(
                children: [
                  TextField(
                    controller: _search,
                    autofocus: true,
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search_rounded),
                      hintText: 'Search by name or phone',
                    ),
                    onChanged: (value) {
                      _debounce?.cancel();
                      _debounce = Timer(
                        const Duration(milliseconds: 180),
                        () => _load(value),
                      );
                    },
                    onSubmitted: (_) {
                      if (results != null && results.length == 1) {
                        Navigator.pop(context, SelectedCustomer(results.first));
                      }
                    },
                  ),
                  const SizedBox(height: 10),
                  ListTile(
                    leading: const CircleAvatar(
                      child: Icon(Icons.directions_walk_rounded),
                    ),
                    title: const Text('Walk-in customer'),
                    subtitle: const Text('No customer attached to the sale'),
                    onTap: () => Navigator.pop(context, const WalkInChoice()),
                  ),
                  const Divider(),
                  Expanded(
                    child: results == null
                        ? const Center(child: CircularProgressIndicator())
                        : results.isEmpty
                        ? const EmptyState(
                            compact: true,
                            icon: Icons.person_search_rounded,
                            title: 'No customers found',
                          )
                        : ListView.builder(
                            itemCount: results.length,
                            itemBuilder: (context, index) {
                              final customer = results[index];
                              return ListTile(
                                leading: CircleAvatar(
                                  child: Text(
                                    customer.name.isEmpty
                                        ? '?'
                                        : customer.name[0].toUpperCase(),
                                  ),
                                ),
                                title: Text(customer.name),
                                subtitle: Text(
                                  [
                                    if ((customer.phone ?? '').isNotEmpty)
                                      customer.phone!,
                                    '${customer.loyaltyPoints} pts',
                                  ].join(' · '),
                                ),
                                onTap: () => Navigator.pop(
                                  context,
                                  SelectedCustomer(customer),
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
      ),
      actions: [
        if (_creating)
          TextButton(
            onPressed: () => setState(() => _creating = false),
            child: const Text('Back'),
          )
        else if (canCreate)
          TextButton.icon(
            onPressed: () => setState(() {
              _creating = true;
              _name.text = _search.text;
            }),
            icon: const Icon(Icons.person_add_alt_1_rounded),
            label: const Text('New customer'),
          ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        if (_creating)
          FilledButton(
            onPressed: _create,
            child: const Text('Create & select'),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Line editor
// ---------------------------------------------------------------------------

class LineEdit {
  const LineEdit({
    required this.quantity,
    required this.discountPercent,
    required this.discountFixed,
    this.price,
    this.clearPrice = false,
  });
  final double quantity;
  final double discountPercent;
  final Money discountFixed;
  final Money? price;
  final bool clearPrice;
}

Future<LineEdit?> showLineEditor(
  BuildContext context, {
  required CartLine line,
  required MoneyFormatter money,
  required bool canDiscount,
  required bool canOverride,
  required double maxDiscountPercent,
}) => showDialog<LineEdit>(
  context: context,
  builder: (_) => _LineEditor(
    line: line,
    money: money,
    canDiscount: canDiscount,
    canOverride: canOverride,
    maxDiscountPercent: maxDiscountPercent,
  ),
);

class _LineEditor extends StatefulWidget {
  const _LineEditor({
    required this.line,
    required this.money,
    required this.canDiscount,
    required this.canOverride,
    required this.maxDiscountPercent,
  });
  final CartLine line;
  final MoneyFormatter money;
  final bool canDiscount;
  final bool canOverride;
  final double maxDiscountPercent;

  @override
  State<_LineEditor> createState() => _LineEditorState();
}

class _LineEditorState extends State<_LineEditor> {
  late final _quantity = TextEditingController(
    text: _formatQuantity(widget.line.quantityMilli),
  );
  late final _price = TextEditingController(
    text: widget.money.editable(widget.line.unitPrice),
  );
  late bool _percent = widget.line.manualDiscount.minorUnits == 0;
  late final _discount = TextEditingController(
    text: _percent
        ? _trim(widget.line.manualDiscountPercent)
        : widget.money.editable(widget.line.manualDiscount),
  );
  String? _error;

  static String _trim(double value) =>
      value == value.roundToDouble() ? value.toStringAsFixed(0) : '$value';

  @override
  void dispose() {
    _quantity.dispose();
    _price.dispose();
    _discount.dispose();
    super.dispose();
  }

  void _stepQuantity(int delta) {
    final current = widget.money.parse(_quantity.text) ?? 0;
    final next = (current + delta).clamp(0, 1e9).toDouble();
    _quantity.text = _trim(next);
  }

  void _apply() {
    final money = widget.money;
    final quantity = money.parse(_quantity.text);
    if (quantity == null || quantity <= 0) {
      setState(() => _error = 'Quantity must be greater than zero.');
      return;
    }
    Money? price;
    var clearPrice = false;
    if (widget.canOverride) {
      final value = money.parse(_price.text);
      if (value == null || value < 0) {
        setState(() => _error = 'Enter a valid price.');
        return;
      }
      final entered = Money.fromMajor(value);
      final catalog = Money.fromMajor(
        widget.line.catalogProduct.effectivePrice,
      );
      if (entered == catalog) {
        clearPrice = true;
      } else {
        price = entered;
      }
    }
    var percent = 0.0;
    var fixed = Money.zero;
    if (widget.canDiscount) {
      final value = money.parse(_discount.text) ?? 0;
      if (value < 0) {
        setState(() => _error = 'Discount cannot be negative.');
        return;
      }
      final unit = price ?? (clearPrice ? null : widget.line.overrideUnitPrice);
      final gross =
          (unit ?? Money.fromMajor(widget.line.catalogProduct.effectivePrice))
              .multiply(quantity);
      final requestedPercent = _percent
          ? value
          : (gross.minorUnits == 0
                ? 0
                : Money.fromMajor(value).minorUnits * 100 / gross.minorUnits);
      if (requestedPercent > widget.maxDiscountPercent + 1e-9) {
        setState(
          () => _error =
              'Maximum allowed discount is ${_trim(widget.maxDiscountPercent)}%.',
        );
        return;
      }
      if (_percent) {
        percent = value;
      } else {
        fixed = Money.fromMajor(value);
      }
    } else {
      percent = widget.line.manualDiscountPercent;
      fixed = widget.line.manualDiscount;
    }
    Navigator.pop(
      context,
      LineEdit(
        quantity: quantity,
        discountPercent: percent,
        discountFixed: fixed,
        price: price,
        clearPrice: clearPrice,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final product = widget.line.catalogProduct.product;
    final money = widget.money;
    final numeric = [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))];
    return AlertDialog(
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(product.name),
          Text(
            '${product.sku} · list price ${money.major(widget.line.catalogProduct.effectivePrice)} / ${product.unit}',
            style: context.text.bodySmall?.copyWith(
              color: context.colors.onSurfaceVariant,
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                IconButton.filledTonal(
                  onPressed: () => _stepQuantity(-1),
                  icon: const Icon(Icons.remove_rounded),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _quantity,
                    autofocus: true,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    inputFormatters: numeric,
                    decoration: InputDecoration(
                      labelText: 'Quantity',
                      suffixText: product.unit,
                    ),
                    onSubmitted: (_) => _apply(),
                  ),
                ),
                const SizedBox(width: 10),
                IconButton.filledTonal(
                  onPressed: () => _stepQuantity(1),
                  icon: const Icon(Icons.add_rounded),
                ),
              ],
            ),
            if (widget.canOverride) ...[
              const SizedBox(height: 14),
              TextField(
                controller: _price,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: numeric,
                decoration: InputDecoration(
                  labelText: 'Unit price',
                  prefixText: '${money.symbol} ',
                  helperText: 'Changing the price is recorded as an override.',
                ),
                onSubmitted: (_) => _apply(),
              ),
            ],
            if (widget.canDiscount) ...[
              const SizedBox(height: 14),
              Row(
                children: [
                  AppSegmented<bool>(
                    items: [
                      SegmentItem(true, '%'),
                      SegmentItem(false, money.symbol),
                    ],
                    value: _percent,
                    onChanged: (value) => setState(() {
                      _percent = value;
                      _discount.clear();
                    }),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _discount,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      inputFormatters: numeric,
                      decoration: InputDecoration(
                        labelText: 'Line discount',
                        helperText:
                            'Max ${_trim(widget.maxDiscountPercent)}% · added to any product discount',
                      ),
                      onSubmitted: (_) => _apply(),
                    ),
                  ),
                ],
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: TextStyle(color: context.colors.error)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _apply, child: const Text('Apply')),
      ],
    );
  }
}

String _formatQuantity(int milli) => (milli / 1000).toStringAsFixed(
  milli % 1000 == 0 ? 0 : (milli % 100 == 0 ? 1 : (milli % 10 == 0 ? 2 : 3)),
);

String formatQuantity(int milli) => _formatQuantity(milli);

// ---------------------------------------------------------------------------
// Sale discount
// ---------------------------------------------------------------------------

class SaleDiscount {
  const SaleDiscount({this.percent = 0, this.fixed = Money.zero});
  final double percent;
  final Money fixed;
}

Future<SaleDiscount?> showSaleDiscountDialog(
  BuildContext context, {
  required PosCart cart,
  required Money discountable,
  required MoneyFormatter money,
  required double maxDiscountPercent,
}) => showDialog<SaleDiscount>(
  context: context,
  builder: (_) => _SaleDiscountDialog(
    cart: cart,
    discountable: discountable,
    money: money,
    maxDiscountPercent: maxDiscountPercent,
  ),
);

class _SaleDiscountDialog extends StatefulWidget {
  const _SaleDiscountDialog({
    required this.cart,
    required this.discountable,
    required this.money,
    required this.maxDiscountPercent,
  });
  final PosCart cart;
  final Money discountable;
  final MoneyFormatter money;
  final double maxDiscountPercent;

  @override
  State<_SaleDiscountDialog> createState() => _SaleDiscountDialogState();
}

class _SaleDiscountDialogState extends State<_SaleDiscountDialog> {
  late bool _percent = widget.cart.saleDiscount.minorUnits == 0;
  late final _value = TextEditingController(
    text: _percent
        ? (widget.cart.saleDiscountPercent == 0
              ? ''
              : _LineEditorState._trim(widget.cart.saleDiscountPercent))
        : widget.money.editable(widget.cart.saleDiscount),
  );
  String? _error;

  @override
  void dispose() {
    _value.dispose();
    super.dispose();
  }

  void _apply([double? preset]) {
    final value = preset ?? widget.money.parse(_value.text) ?? 0;
    if (value < 0) {
      setState(() => _error = 'Discount cannot be negative.');
      return;
    }
    final asPercent = preset != null || _percent
        ? value
        : (widget.discountable.minorUnits == 0
              ? 0
              : Money.fromMajor(value).minorUnits *
                    100 /
                    widget.discountable.minorUnits);
    if (asPercent > widget.maxDiscountPercent + 1e-9) {
      setState(
        () => _error =
            'Maximum allowed discount is ${_LineEditorState._trim(widget.maxDiscountPercent)}%.',
      );
      return;
    }
    Navigator.pop(
      context,
      preset != null || _percent
          ? SaleDiscount(percent: value)
          : SaleDiscount(fixed: Money.fromMajor(value)),
    );
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    icon: const Icon(Icons.percent_rounded),
    title: const Text('Sale discount'),
    content: SizedBox(
      width: 420,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              AppSegmented<bool>(
                items: [
                  SegmentItem(true, 'Percent'),
                  SegmentItem(false, widget.money.symbol),
                ],
                value: _percent,
                onChanged: (value) => setState(() {
                  _percent = value;
                  _value.clear();
                }),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _value,
                  autofocus: true,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                  ],
                  decoration: InputDecoration(
                    suffixText: _percent ? '%' : null,
                    prefixText: _percent ? null : '${widget.money.symbol} ',
                    errorText: _error,
                  ),
                  onSubmitted: (_) => _apply(),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            children: [
              for (final preset in const [5, 10, 15, 20, 25])
                if (preset <= widget.maxDiscountPercent)
                  ActionChip(
                    label: Text('$preset%'),
                    onPressed: () => _apply(preset.toDouble()),
                  ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Applies to ${widget.money.format(widget.discountable)} after line discounts. '
            'Maximum ${_LineEditorState._trim(widget.maxDiscountPercent)}%.',
            style: context.text.bodySmall?.copyWith(
              color: context.colors.onSurfaceVariant,
            ),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context, const SaleDiscount()),
        child: const Text('Remove discount'),
      ),
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(onPressed: _apply, child: const Text('Apply')),
    ],
  );
}

// ---------------------------------------------------------------------------
// Held carts
// ---------------------------------------------------------------------------

/// Shows held carts; returns the restored cart when one is resumed.
Future<PosCart?> showHeldCartsDialog(BuildContext context) =>
    showDialog<PosCart>(context: context, builder: (_) => const _HeldCarts());

class _HeldCarts extends ConsumerWidget {
  const _HeldCarts();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(activeSessionProvider)!;
    final repository = ref.watch(heldCartRepositoryProvider);
    return AlertDialog(
      icon: const Icon(Icons.pause_circle_outline_rounded),
      title: const Text('Held sales'),
      content: SizedBox(
        width: 620,
        height: 420,
        child: StreamBuilder<List<HeldCart>>(
          stream: repository.watch(session),
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final carts = snapshot.data!;
            if (carts.isEmpty) {
              return const EmptyState(
                icon: Icons.inbox_rounded,
                title: 'No held sales',
                message: 'Press F4 on the POS to park the current sale.',
              );
            }
            return ListView.separated(
              itemCount: carts.length,
              separatorBuilder: (_, _) => const Divider(),
              itemBuilder: (context, index) {
                final held = carts[index];
                return ListTile(
                  leading: const CircleAvatar(
                    child: Icon(Icons.shopping_basket_outlined),
                  ),
                  title: Text(held.label.isEmpty ? 'Untitled' : held.label),
                  subtitle: Text(
                    DateFormat('d MMM, h:mm a')
                        .format(held.updatedAt.toLocal()),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: 'Delete',
                        onPressed: () async {
                          final confirmed = await confirmDialog(
                            context,
                            title: 'Delete held sale?',
                            message:
                                '“${held.label}” will be permanently removed.',
                            confirmLabel: 'Delete',
                            destructive: true,
                          );
                          if (confirmed) {
                            await repository.remove(session, held.id);
                          }
                        },
                        icon: const Icon(Icons.delete_outline_rounded),
                      ),
                      const SizedBox(width: 6),
                      FilledButton.tonalIcon(
                        onPressed: () async {
                          try {
                            final cart = await repository.restore(
                              session,
                              held,
                            );
                            await repository.remove(session, held.id);
                            if (context.mounted) Navigator.pop(context, cart);
                          } catch (error) {
                            if (context.mounted) Toast.error(context, error);
                          }
                        },
                        icon: const Icon(Icons.play_arrow_rounded),
                        label: const Text('Resume'),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Sale completed
// ---------------------------------------------------------------------------

enum SaleCompleteAction { done, print, savePdf, preview }

Future<SaleCompleteAction?> showSaleCompleteDialog(
  BuildContext context, {
  required CheckoutResult result,
  required MoneyFormatter money,
}) => showDialog<SaleCompleteAction>(
  context: context,
  builder: (context) {
    final tokens = context.tokens;
    final hasChange = result.change.minorUnits > 0;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyP): () =>
            Navigator.pop(context, SaleCompleteAction.print),
        const SingleActivator(LogicalKeyboardKey.keyV): () =>
            Navigator.pop(context, SaleCompleteAction.preview),
      },
      child: AlertDialog(
        icon: Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            color: tokens.successContainer,
            shape: BoxShape.circle,
          ),
          child: Icon(Icons.check_rounded, size: 42, color: tokens.success),
        ).entrance(context, dy: 0.2),
        title: const Text('Sale completed'),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              StatusPill(result.invoiceNumber, tone: PillTone.primary),
              const SizedBox(height: 18),
              if (hasChange) ...[
                Text(
                  'Change to return',
                  style: TextStyle(color: context.colors.onSurfaceVariant),
                ),
                Text(
                  money.format(result.change),
                  style: context.text.displaySmall?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: tokens.success,
                  ),
                ),
                const SizedBox(height: 12),
              ],
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _Summary('Total', money.format(result.total)),
                  _Summary('Received', money.format(result.received)),
                ],
              ),
            ],
          ),
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          OutlinedButton.icon(
            onPressed: () => Navigator.pop(context, SaleCompleteAction.preview),
            icon: const Icon(Icons.visibility_outlined),
            label: const Text('Preview  (V)'),
          ),
          OutlinedButton.icon(
            onPressed: () => Navigator.pop(context, SaleCompleteAction.savePdf),
            icon: const Icon(Icons.picture_as_pdf_outlined),
            label: const Text('Save PDF'),
          ),
          OutlinedButton.icon(
            onPressed: () => Navigator.pop(context, SaleCompleteAction.print),
            icon: const Icon(Icons.print_outlined),
            label: const Text('Print  (P)'),
          ),
          FilledButton.icon(
            autofocus: true,
            onPressed: () => Navigator.pop(context, SaleCompleteAction.done),
            icon: const Icon(Icons.add_shopping_cart_rounded),
            label: const Text('New sale  (Enter)'),
          ),
        ],
      ),
    );
  },
);

class _Summary extends StatelessWidget {
  const _Summary(this.label, this.value);
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => Column(
    children: [
      Text(label, style: TextStyle(color: context.colors.onSurfaceVariant)),
      Text(value, style: const TextStyle(fontWeight: FontWeight.w800)),
    ],
  );
}
