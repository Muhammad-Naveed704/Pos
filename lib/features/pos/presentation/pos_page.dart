import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../../../core/money/money.dart';
import '../../../core/money/money_format.dart';
import '../../../core/ui/ui_kit.dart';
import '../../auth/application/session_controller.dart';
import '../../auth/domain/permissions.dart';
import '../../categories/data/category_repository.dart';
import '../../credit/data/credit_service.dart';
import '../../history/data/sales_repository.dart';
import '../../products/data/product_repository.dart';
import '../../receipts/data/receipt_service.dart';
import '../../settings/data/business_settings_repository.dart';
import '../../settings/domain/business_settings.dart';
import '../application/cart_controller.dart';
import '../data/checkout_service.dart';
import '../data/held_cart_repository.dart';
import '../domain/pos_cart.dart';
import '../../receipts/presentation/receipt_preview.dart';
import '../../returns/presentation/refund_dialog.dart';
import '../../scanning/camera_scanner.dart';
import 'barcode_scanner.dart';
import 'payment_dialog.dart';
import 'pos_dialogs.dart';

class PosPage extends ConsumerStatefulWidget {
  const PosPage({super.key});
  @override
  ConsumerState<PosPage> createState() => _PosPageState();
}

class _PosPageState extends ConsumerState<PosPage> {
  final _search = TextEditingController();
  final _searchFocus = FocusNode();
  Timer? _debounce;
  String _term = '';
  String? _categoryId;
  bool _busy = false;
  List<CatalogProduct> _visible = const [];
  final _pageFocus = FocusNode(debugLabel: 'pos-page');
  late final ScannerKeyBuffer _scanner = ScannerKeyBuffer(
    isActive: () =>
        mounted &&
        _pageFocus.hasFocus &&
        !_searchFocus.hasFocus &&
        !(ref.read(activeSessionProvider)?.isLocked ?? true),
    onScan: (code) {
      _flashScan(code);
      _searchSubmitted(code);
    },
    onTyped: (text) {
      _search.text = text;
      _search.selection = TextSelection.collapsed(offset: text.length);
      _searchFocus.requestFocus();
      setState(() => _term = text.trim());
    },
  );
  String? _lastScan;
  Timer? _scanFlash;

  @override
  void initState() {
    super.initState();
    _scanner.attach();
  }

  void _flashScan(String code) {
    _scanFlash?.cancel();
    setState(() => _lastScan = code);
    _scanFlash = Timer(const Duration(milliseconds: 1500), () {
      if (mounted) setState(() => _lastScan = null);
    });
  }

  @override
  void dispose() {
    _scanner.detach();
    _scanFlash?.cancel();
    _pageFocus.dispose();
    _debounce?.cancel();
    _search.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  BusinessSettings get _settings => ref.read(currentBusinessSettingsProvider);
  MoneyFormatter get _money => ref.read(moneyFormatterProvider);

  /// F2: focus the search box; pressed again while it is focused, open the
  /// camera scanner.
  void _focusSearch() {
    if (_searchFocus.hasFocus) {
      _scanWithCamera();
      return;
    }
    _searchFocus.requestFocus();
    _search.selection = TextSelection(
      baseOffset: 0,
      extentOffset: _search.text.length,
    );
  }

  void _resetSearch() {
    _debounce?.cancel();
    _search.clear();
    setState(() => _term = '');
  }

  /// Adds a product, respecting stock when negative stock is not allowed.
  void _addProduct(CatalogProduct product) {
    final cart = ref.read(cartControllerProvider);
    final inCart = cart.lines
        .where((line) => line.productId == product.product.id)
        .fold(0, (sum, line) => sum + line.quantityMilli);
    if (product.product.trackInventory &&
        !_settings.allowNegativeStock &&
        (inCart + 1000) > (product.store.stockQty * 1000).round()) {
      Toast.show(
        context,
        product.store.stockQty <= 0
            ? '${product.product.name} is out of stock.'
            : 'Only ${formatQuantity((product.store.stockQty * 1000).round())} ${product.product.unit} of ${product.product.name} in stock.',
        tone: PillTone.warning,
      );
      return;
    }
    ref.read(cartControllerProvider.notifier).add(product);
  }

  Future<void> _searchSubmitted(String value) async {
    final code = value.trim();
    if (code.isEmpty) {
      if (ref.read(cartControllerProvider).lines.isNotEmpty) _payment();
      return;
    }
    final session = ref.read(activeSessionProvider)!;
    final product = await ref
        .read(productRepositoryProvider)
        .exactLookup(storeId: session.store.id, code: code);
    if (!mounted) return;
    // Only clear if the field still holds the code we looked up; the user or
    // scanner may already be typing the next one.
    final unchanged = _search.text.trim() == code;
    if (product != null) {
      _addProduct(product);
      if (unchanged) _resetSearch();
    } else if (_term == code && _visible.length == 1) {
      _addProduct(_visible.first);
      if (unchanged) _resetSearch();
    } else {
      Toast.show(
        context,
        'No product matches “$code”.',
        tone: PillTone.warning,
        icon: Icons.qr_code_scanner_rounded,
      );
      _focusSearch();
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(activeSessionProvider)!;
    final settings = ref.watch(currentBusinessSettingsProvider);
    final money = ref.watch(moneyFormatterProvider);
    final cart = ref.watch(cartControllerProvider);
    final totals = cart.totals(settings.taxMode);
    final hasLines = cart.lines.isNotEmpty;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.f2): _focusSearch,
        const SingleActivator(LogicalKeyboardKey.keyF, control: true):
            _focusSearch,
        const SingleActivator(LogicalKeyboardKey.keyN, control: true): _newSale,
        const SingleActivator(LogicalKeyboardKey.f3): _selectCustomer,
        const SingleActivator(LogicalKeyboardKey.f4): _hold,
        const SingleActivator(LogicalKeyboardKey.f6): _saleDiscount,
        const SingleActivator(LogicalKeyboardKey.f7): _payment,
        const SingleActivator(LogicalKeyboardKey.f8): _quickCash,
        const SingleActivator(LogicalKeyboardKey.f9): _heldCarts,
        const SingleActivator(LogicalKeyboardKey.f10): _payment,
        const SingleActivator(LogicalKeyboardKey.keyR, control: true):
            _startReturn,
      },
      child: Focus(
        focusNode: _pageFocus,
        autofocus: true,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: _catalog(session.store.id, money)),
              const SizedBox(width: 16),
              SizedBox(
                width: 440,
                child: _CartPanel(
                  cart: cart,
                  totals: totals,
                  settings: settings,
                  money: money,
                  busy: _busy,
                  onCustomer: _selectCustomer,
                  onHeld: _heldCarts,
                  onEditLine: _editLine,
                  onHold: hasLines ? _hold : null,
                  onDiscount:
                      hasLines && session.can(Permissions.posApplyDiscount)
                      ? _saleDiscount
                      : null,
                  onNote: _editNote,
                  onReturn: session.can(Permissions.posRefund)
                      ? _startReturn
                      : null,
                  onClear: hasLines ? _newSale : null,
                  onPay: hasLines && !_busy ? _payment : null,
                  onQuickCash: hasLines && !_busy ? _quickCash : null,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _catalog(String storeId, MoneyFormatter money) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _search,
              focusNode: _searchFocus,
              autofocus: true,
              style: const TextStyle(fontSize: 15),
              onSubmitted: _searchSubmitted,
              onChanged: (value) {
                _debounce?.cancel();
                _debounce = Timer(const Duration(milliseconds: 160), () {
                  if (mounted) setState(() => _term = value.trim());
                });
              },
              decoration: InputDecoration(
                prefixIcon: Tooltip(
                  message: 'Scan with camera (F2)',
                  child: IconButton(
                    icon: const Icon(Icons.qr_code_scanner_rounded),
                    color: context.colors.primary,
                    onPressed: _scanWithCamera,
                  ),
                ),
                hintText: 'Scan a barcode or search by name / SKU',
                suffixIcon: ListenableBuilder(
                  listenable: _search,
                  builder: (context, _) => _search.text.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _ScannerStatus(lastScan: _lastScan),
                              const SizedBox(width: 8),
                              const KeyHint('F2'),
                            ],
                          ),
                        )
                      : IconButton(
                          tooltip: 'Clear',
                          onPressed: () {
                            _resetSearch();
                            _searchFocus.requestFocus();
                          },
                          icon: const Icon(Icons.close_rounded),
                        ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 36,
              child: CachedStreamBuilder<List<Category>>(
                create: () =>
                    ref.read(categoryRepositoryProvider).watch(active: true),
                builder: (context, snapshot) => ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    _CategoryChip(
                      label: 'All items',
                      icon: Icons.apps_rounded,
                      selected: _categoryId == null,
                      onTap: () => setState(() => _categoryId = null),
                    ),
                    for (final category in snapshot.data ?? const <Category>[])
                      _CategoryChip(
                        label: category.name,
                        selected: _categoryId == category.id,
                        onTap: () => setState(
                          () => _categoryId = _categoryId == category.id
                              ? null
                              : category.id,
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: CachedStreamBuilder<List<CatalogProduct>>(
                keys: [storeId, _term, _categoryId],
                create: () => ref
                    .read(productRepositoryProvider)
                    .watchPosProducts(
                      storeId: storeId,
                      search: _term,
                      categoryId: _categoryId,
                    ),
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return EmptyState(
                      icon: Icons.error_outline_rounded,
                      title: 'Products could not be loaded',
                      message: friendlyError(snapshot.error!),
                    );
                  }
                  if (!snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final items = snapshot.data!;
                  _visible = items;
                  if (items.isEmpty) {
                    return EmptyState(
                      icon: Icons.search_off_rounded,
                      title: _term.isEmpty
                          ? 'No sellable products yet'
                          : 'Nothing matches “$_term”',
                      message: _term.isEmpty
                          ? 'Add products and make them available in this store.'
                          : 'Try another name, SKU or barcode.',
                    );
                  }
                  return GridView.builder(
                    gridDelegate:
                        const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 230,
                          mainAxisExtent: 372,
                          crossAxisSpacing: 10,
                          mainAxisSpacing: 10,
                        ),
                    itemCount: items.length,
                    itemBuilder: (context, index) => _ProductTile(
                      item: items[index],
                      money: money,
                      onTap: () => _addProduct(items[index]),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _selectCustomer() async {
    final choice = await showCustomerPicker(context);
    if (!mounted || choice == null) return;
    ref.read(cartControllerProvider.notifier).selectCustomer(switch (choice) {
      WalkInChoice() => null,
      SelectedCustomer(:final customer) => customer.id,
    });
    _searchFocus.requestFocus();
  }

  Future<void> _editLine(int index) async {
    final session = ref.read(activeSessionProvider)!;
    final line = ref.read(cartControllerProvider).lines[index];
    final edit = await showLineEditor(
      context,
      line: line,
      money: _money,
      canDiscount: session.can(Permissions.posApplyDiscount),
      canOverride:
          session.can(Permissions.posOverridePrice) &&
          _settings.allowPriceOverride,
      maxDiscountPercent: _settings.maxDiscountPercent,
    );
    if (edit == null || !mounted) return;
    final controller = ref.read(cartControllerProvider.notifier);
    if (edit.clearPrice) controller.clearPriceOverride(index);
    if (edit.price != null) controller.overridePrice(index, edit.price!);
    controller.setLineDiscount(
      index,
      percent: edit.discountPercent,
      fixed: edit.discountFixed,
    );
    controller.setQuantity(index, edit.quantity);
    _searchFocus.requestFocus();
  }

  Future<void> _hold() async {
    final cart = ref.read(cartControllerProvider);
    if (cart.lines.isEmpty) return;
    final label = await promptDialog(
      context,
      title: 'Hold sale',
      label: 'Reference or note',
      hint: 'e.g. Customer in blue shirt',
      confirmLabel: 'Hold',
    );
    if (label == null || !mounted) return;
    try {
      await ref
          .read(heldCartRepositoryProvider)
          .save(ref.read(activeSessionProvider)!, cart, label: label.trim());
      ref.read(cartControllerProvider.notifier).clear();
      if (mounted) Toast.success(context, 'Sale held. Press F9 to resume.');
    } catch (error) {
      if (mounted) Toast.error(context, error);
    }
    _searchFocus.requestFocus();
  }

  Future<void> _heldCarts() async {
    final current = ref.read(cartControllerProvider);
    final cart = await showHeldCartsDialog(context);
    if (cart == null || !mounted) return;
    if (current.lines.isNotEmpty) {
      // Park the current sale instead of silently discarding it.
      await ref
          .read(heldCartRepositoryProvider)
          .save(
            ref.read(activeSessionProvider)!,
            current,
            label: 'Auto-held before resume',
          );
    }
    ref.read(cartControllerProvider.notifier).replace(cart);
    if (mounted) Toast.success(context, 'Held sale resumed.');
    _searchFocus.requestFocus();
  }

  Future<void> _saleDiscount() async {
    final session = ref.read(activeSessionProvider)!;
    final cart = ref.read(cartControllerProvider);
    if (cart.lines.isEmpty || !session.can(Permissions.posApplyDiscount)) {
      return;
    }
    final totals = cart.totals(_settings.taxMode);
    final result = await showSaleDiscountDialog(
      context,
      cart: cart,
      discountable: (totals.subtotal - totals.lineDiscount).max(Money.zero),
      money: _money,
      maxDiscountPercent: _settings.maxDiscountPercent,
    );
    if (result == null || !mounted) return;
    ref
        .read(cartControllerProvider.notifier)
        .setSaleDiscount(
          fixed: result.fixed,
          percent: result.percent.clamp(0, 100).toDouble(),
        );
    _searchFocus.requestFocus();
  }

  Future<void> _scanWithCamera() async {
    final code = await scanWithCamera(context, title: 'Scan product');
    if (code == null || !mounted) return;
    _flashScan(code);
    await _searchSubmitted(code);
  }

  Future<void> _startReturn() async {
    if (!ref.read(activeSessionProvider)!.can(Permissions.posRefund)) return;
    await startReturnByInvoice(context, ref);
    if (mounted) _searchFocus.requestFocus();
  }

  Future<void> _editNote() async {
    final value = await promptDialog(
      context,
      title: 'Sale note',
      label: 'Note (printed in history)',
      initialValue: ref.read(cartControllerProvider).notes,
      confirmLabel: 'Save',
      maxLines: 3,
    );
    if (value != null && mounted) {
      ref.read(cartControllerProvider.notifier).setNotes(value.trim());
    }
  }

  Future<void> _newSale() async {
    final cart = ref.read(cartControllerProvider);
    if (cart.lines.isNotEmpty) {
      final confirmed = await confirmDialog(
        context,
        title: 'Start a new sale?',
        message:
            'The current cart with ${cart.lines.length} item(s) will be cleared.',
        confirmLabel: 'Clear cart',
        destructive: true,
        icon: Icons.remove_shopping_cart_outlined,
      );
      if (!confirmed || !mounted) return;
    }
    ref.read(cartControllerProvider.notifier).clear();
    _resetSearch();
    _searchFocus.requestFocus();
  }

  /// The amount due, or null (with a message) when there is nothing to charge.
  Money? _amountDue() {
    final cart = ref.read(cartControllerProvider);
    if (cart.lines.isEmpty) return null;
    final total = cart.totals(_settings.taxMode).grandTotal;
    if (total.minorUnits == 0) {
      Toast.show(
        context,
        'The sale total is zero. Adjust prices or discounts before taking payment.',
        tone: PillTone.warning,
      );
      return null;
    }
    return total;
  }

  Future<void> _quickCash() async {
    if (_busy) return;
    final total = _amountDue();
    if (total == null) return;
    await _complete([PaymentInput(method: 'cash', amount: total)]);
  }

  Future<CreditCustomer?> _creditCustomer(String? customerId) async {
    if (customerId == null) return null;
    final balance = await ref
        .read(creditServiceProvider)
        .balance(ref.read(activeSessionProvider)!, customerId);
    return CreditCustomer(
      id: customerId,
      name: balance.customer.name,
      outstanding: balance.outstanding,
      limit: balance.creditLimit,
    );
  }

  Future<void> _payment() async {
    if (_busy) return;
    final total = _amountDue();
    if (total == null) return;
    final session = ref.read(activeSessionProvider)!;
    final allowCredit = session.can(Permissions.creditCreate);
    CreditCustomer? customer;
    if (allowCredit) {
      try {
        customer = await _creditCustomer(
          ref.read(cartControllerProvider).customerId,
        );
      } catch (_) {}
    }
    if (!mounted) return;
    final decision = await showPaymentDialog(
      context,
      total: total,
      money: _money,
      denominations: _settings.quickCashDenominations,
      allowCredit: allowCredit,
      customer: customer,
      onPickCustomer: () async {
        final choice = await showCustomerPicker(context);
        if (choice is! SelectedCustomer) return null;
        ref
            .read(cartControllerProvider.notifier)
            .selectCustomer(choice.customer.id);
        return _creditCustomer(choice.customer.id);
      },
    );
    if (decision == null || !mounted) return;
    if (decision.customerId != null &&
        decision.customerId != ref.read(cartControllerProvider).customerId) {
      ref
          .read(cartControllerProvider.notifier)
          .selectCustomer(decision.customerId);
    }
    await _complete(decision.payments, dueDate: decision.dueDate);
  }

  Future<void> _complete(
    List<PaymentInput> payments, {
    DateTime? dueDate,
  }) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final session = ref.read(activeSessionProvider)!;
      Future<CheckoutResult> run(bool override) => ref
          .read(checkoutServiceProvider)
          .checkout(
            session: session,
            cart: ref.read(cartControllerProvider),
            payments: payments,
            dueDate: dueDate,
            overrideCreditLimit: override,
          );
      CheckoutResult result;
      try {
        result = await run(false);
      } on CreditLimitException catch (limit) {
        if (!mounted) return;
        if (!session.can(Permissions.creditOverrideLimit)) {
          throw CheckoutException(
            '${limit.customerName} would owe ${_money.format(limit.projected)}, '
            'over the ${_money.format(limit.limit)} credit limit. A manager can approve it.',
          );
        }
        final approved = await confirmDialog(
          context,
          title: 'Credit limit exceeded',
          icon: Icons.gpp_maybe_rounded,
          message:
              '${limit.customerName} owes ${_money.format(limit.outstanding)} with a '
              'limit of ${_money.format(limit.limit)}. This sale adds '
              '${_money.format(limit.requested)}, bringing the balance to '
              '${_money.format(limit.projected)}.\n\n'
              'Continue anyway? The override is recorded in the audit log.',
          confirmLabel: 'Override and complete',
          destructive: true,
        );
        if (!approved) return;
        result = await run(true);
      }
      ref.read(cartControllerProvider.notifier).clear();
      _resetSearch();
      if (!mounted) return;
      setState(() => _busy = false);
      final action = await showSaleCompleteDialog(
        context,
        result: result,
        money: _money,
      );
      if (action == SaleCompleteAction.preview) {
        final details = await ref
            .read(salesRepositoryProvider)
            .details(session, result.saleId);
        if (mounted) await showReceiptPreview(context, ref, details);
      } else if (action == SaleCompleteAction.print ||
          action == SaleCompleteAction.savePdf) {
        final details = await ref
            .read(salesRepositoryProvider)
            .details(session, result.saleId);
        final receipts = ref.read(receiptServiceProvider);
        if (action == SaleCompleteAction.print) {
          await receipts.printReceipt(details, _settings);
        } else {
          final path = await receipts.savePdf(details, _settings);
          if (path != null && mounted) Toast.success(context, 'Saved $path');
        }
      }
    } catch (error) {
      if (mounted) Toast.error(context, error);
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        _searchFocus.requestFocus();
      }
    }
  }
}

class _CategoryChip extends StatelessWidget {
  const _CategoryChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(right: 8),
    child: ChoiceChip(
      avatar: icon == null ? null : Icon(icon, size: 16),
      showCheckmark: false,
      label: Text(label),
      selected: selected,
      onSelected: (_) => onTap(),
    ),
  );
}

class _ProductTile extends StatefulWidget {
  const _ProductTile({
    required this.item,
    required this.money,
    required this.onTap,
  });
  final CatalogProduct item;
  final MoneyFormatter money;
  final VoidCallback onTap;

  @override
  State<_ProductTile> createState() => _ProductTileState();
}

class _ProductTileState extends State<_ProductTile> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final product = item.product;
    final scheme = context.colors;
    final tokens = context.tokens;
    final stock = item.store.stockQty;
    final (stockLabel, tone) = !product.trackInventory
        ? (null, PillTone.neutral)
        : stock <= 0
        ? ('Out of stock', PillTone.danger)
        : stock <= item.store.reorderLevel
        ? ('${formatQuantity((stock * 1000).round())} left', PillTone.warning)
        : (
            '${formatQuantity((stock * 1000).round())} in stock',
            PillTone.success,
          );
    final out = product.trackInventory && stock <= 0;
    final discount = item.effectiveDiscount.clamp(0, 100);
    final price = item.effectivePrice * (1 - discount / 100);
    final radius = BorderRadius.circular(tokens.radius + 6);
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: SystemMouseCursors.click,
      child: AnimatedContainer(
        duration: tokens.motion(140),
        transform: Matrix4.translationValues(0, _hover ? -3 : 0, 0),
        decoration: BoxDecoration(
          color: context.theme.cardTheme.color ?? scheme.surface,
          borderRadius: radius,
          border: Border.all(
            color: _hover
                ? scheme.primary.withValues(alpha: 0.55)
                : scheme.outlineVariant.withValues(alpha: 0.5),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: _hover ? 0.09 : 0.04),
              blurRadius: _hover ? 20 : 10,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: radius,
            onTap: widget.onTap,
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Photo fills the top of the card (cover).
                  Expanded(
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: LayoutBuilder(
                            builder: (context, box) => Opacity(
                              opacity: out ? 0.5 : 1,
                              child: ProductThumb(
                                name: product.name,
                                path: product.imagePath,
                                width: box.maxWidth,
                                height: box.maxHeight,
                                radius: tokens.radius + 2,
                              ),
                            ),
                          ),
                        ),
                        if (discount > 0)
                          Positioned(
                            top: 8,
                            left: 8,
                            child: StatusPill(
                              '-${discount.toStringAsFixed(0)}%',
                              tone: PillTone.info,
                            ),
                          ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 10, 4, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (item.category != null) ...[
                          StatusPill(item.category!.name, tone: PillTone.info),
                          const SizedBox(height: 6),
                        ],
                        Text(
                          product.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 15,
                          ),
                        ),
                        Text(
                          'SKU: ${product.sku}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: context.text.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                        if (stockLabel != null) ...[
                          const SizedBox(height: 6),
                          StatusPill(
                            stockLabel,
                            tone: tone,
                            icon: Icons.circle,
                          ),
                        ],
                        const SizedBox(height: 8),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.baseline,
                          textBaseline: TextBaseline.alphabetic,
                          children: [
                            Flexible(
                              child: Text(
                                widget.money.major(price),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w900,
                                  fontSize: 18,
                                ),
                              ),
                            ),
                            if (discount > 0) ...[
                              const SizedBox(width: 8),
                              Flexible(
                                child: Text(
                                  widget.money.major(item.effectivePrice),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: context.text.bodySmall?.copyWith(
                                    color: scheme.onSurfaceVariant,
                                    decoration: TextDecoration.lineThrough,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 8),
                      ],
                    ),
                  ),
                  SizedBox(
                    width: double.infinity,
                    height: 40,
                    child: FilledButton.icon(
                      onPressed: out ? null : widget.onTap,
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(0, 40),
                        padding: EdgeInsets.zero,
                      ),
                      icon: Icon(
                        out
                            ? Icons.remove_shopping_cart_outlined
                            : Icons.add_shopping_cart_rounded,
                        size: 18,
                      ),
                      label: Text(out ? 'Out of stock' : 'Add to cart'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CartPanel extends ConsumerWidget {
  const _CartPanel({
    required this.cart,
    required this.totals,
    required this.settings,
    required this.money,
    required this.busy,
    required this.onCustomer,
    required this.onHeld,
    required this.onEditLine,
    required this.onNote,
    this.onReturn,
    this.onHold,
    this.onDiscount,
    this.onClear,
    this.onPay,
    this.onQuickCash,
  });

  final PosCart cart;
  final CartTotals totals;
  final BusinessSettings settings;
  final MoneyFormatter money;
  final bool busy;
  final VoidCallback onCustomer;
  final VoidCallback onHeld;
  final ValueChanged<int> onEditLine;
  final VoidCallback onNote;
  final VoidCallback? onReturn;
  final VoidCallback? onHold;
  final VoidCallback? onDiscount;
  final VoidCallback? onClear;
  final VoidCallback? onPay;
  final VoidCallback? onQuickCash;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(activeSessionProvider)!;
    final customerId = cart.customerId;
    final customer = customerId == null
        ? null
        : ref.watch(posCustomerProvider(customerId)).value;
    final heldCount =
        ref.watch(_heldCountProvider(session.store.id)).value ?? 0;
    final scheme = context.colors;
    final tokens = context.tokens;
    final itemCount = cart.lines.fold<int>(
      0,
      (sum, line) => sum + line.quantityMilli,
    );
    final discount = totals.lineDiscount + totals.saleDiscount;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 10, 10),
            child: Row(
              children: [
                Text(
                  'Current sale',
                  style: context.text.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(width: 8),
                if (cart.lines.isNotEmpty)
                  StatusPill(
                    '${formatQuantity(itemCount)} items',
                    tone: PillTone.primary,
                  ),
                const Spacer(),
                IconButton(
                  tooltip: 'Held sales (F9)',
                  onPressed: onHeld,
                  icon: Badge(
                    isLabelVisible: heldCount > 0,
                    label: Text('$heldCount'),
                    child: const Icon(Icons.pause_circle_outline_rounded),
                  ),
                ),
                IconButton(
                  tooltip: 'Clear cart (Ctrl+N)',
                  onPressed: onClear,
                  icon: const Icon(Icons.delete_sweep_outlined),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Material(
              color: customer == null
                  ? scheme.surfaceContainerHigh
                  : scheme.secondaryContainer,
              borderRadius: tokens.borderRadius,
              child: InkWell(
                borderRadius: tokens.borderRadius,
                onTap: onCustomer,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 9,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        customer == null
                            ? Icons.directions_walk_rounded
                            : Icons.person_rounded,
                        size: 20,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              customer?.name ?? 'Walk-in customer',
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            if (customer != null)
                              Text(
                                [
                                  if ((customer.phone ?? '').isNotEmpty)
                                    customer.phone!,
                                  '${customer.loyaltyPoints} loyalty pts',
                                ].join(' · '),
                                style: context.text.bodySmall,
                              ),
                          ],
                        ),
                      ),
                      const KeyHint('F3'),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          const Divider(),
          Expanded(
            child: cart.lines.isEmpty
                ? const EmptyState(
                    icon: Icons.shopping_cart_outlined,
                    title: 'Cart is empty',
                    message:
                        'Scan a barcode or tap a product to start billing.',
                  )
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    itemCount: cart.lines.length,
                    separatorBuilder: (_, _) => const Divider(indent: 16),
                    itemBuilder: (context, index) {
                      final line = cart.lines[index];
                      return _CartLineTile(
                        key: ValueKey(line.productId),
                        line: line,
                        totals: cart.lineTotals(line, settings.taxMode),
                        money: money,
                        onEdit: () => onEditLine(index),
                        onDecrement: () => ref
                            .read(cartControllerProvider.notifier)
                            .setQuantity(index, line.quantityMilli / 1000 - 1),
                        onIncrement: () => ref
                            .read(cartControllerProvider.notifier)
                            .setQuantity(index, line.quantityMilli / 1000 + 1),
                        onRemove: () => ref
                            .read(cartControllerProvider.notifier)
                            .remove(index),
                      );
                    },
                  ),
          ),
          Container(
            decoration: BoxDecoration(
              color: scheme.surfaceContainerLow,
              border: Border(
                top: BorderSide(
                  color: scheme.outlineVariant.withValues(alpha: 0.6),
                ),
              ),
            ),
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    _ToolButton(
                      icon: Icons.pause_rounded,
                      label: 'Hold',
                      shortcut: 'F4',
                      onTap: onHold,
                    ),
                    _ToolButton(
                      icon: Icons.percent_rounded,
                      label: 'Discount',
                      shortcut: 'F6',
                      onTap: onDiscount,
                    ),
                    _ToolButton(
                      icon: Icons.sticky_note_2_outlined,
                      label: cart.notes.isEmpty ? 'Note' : 'Note ✓',
                      onTap: onNote,
                    ),
                    if (onReturn != null)
                      _ToolButton(
                        icon: Icons.assignment_return_outlined,
                        label: 'Return',
                        onTap: onReturn,
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                _AmountRow('Subtotal', money.format(totals.subtotal)),
                if (discount.minorUnits > 0)
                  _AmountRow(
                    'Discount',
                    money.format(-discount),
                    color: tokens.success,
                  ),
                if (settings.taxMode != TaxMode.disabled)
                  _AmountRow(
                    settings.taxMode == TaxMode.inclusive
                        ? '${settings.taxLabel} (included)'
                        : settings.taxLabel,
                    money.format(totals.tax),
                  ),
                const SizedBox(height: 6),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      'Total',
                      style: context.text.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const Spacer(),
                    Flexible(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          money.format(totals.grandTotal),
                          style: context.text.headlineMedium?.copyWith(
                            fontWeight: FontWeight.w900,
                            color: scheme.primary,
                            letterSpacing: -0.6,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: 54,
                        child: OutlinedButton(
                          onPressed: onQuickCash,
                          child: const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Flexible(
                                child: Text(
                                  'Exact',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(fontWeight: FontWeight.w700),
                                ),
                              ),
                              SizedBox(width: 6),
                              KeyHint('F8'),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 2,
                      child: SizedBox(
                        height: 54,
                        child: FilledButton(
                          onPressed: onPay,
                          style: FilledButton.styleFrom(
                            textStyle: context.text.labelLarge?.copyWith(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          child: busy
                              ? const SizedBox.square(
                                  dimension: 22,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.5,
                                  ),
                                )
                              : Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const Icon(Icons.payments_rounded),
                                    const SizedBox(width: 10),
                                    const Flexible(
                                      child: Text(
                                        'Pay',
                                        maxLines: 1,
                                        overflow: TextOverflow.clip,
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    KeyHint('F7', onPrimary: onPay != null),
                                  ],
                                ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

final _heldCountProvider = StreamProvider.family<int, String>((ref, storeId) {
  final session = ref.watch(activeSessionProvider);
  if (session == null) return Stream.value(0);
  return ref
      .watch(heldCartRepositoryProvider)
      .watch(session)
      .map((carts) => carts.length);
});

class _CartLineTile extends StatelessWidget {
  const _CartLineTile({
    required this.line,
    required this.totals,
    required this.money,
    required this.onEdit,
    required this.onDecrement,
    required this.onIncrement,
    required this.onRemove,
    super.key,
  });

  final CartLine line;
  final CartLineTotals totals;
  final MoneyFormatter money;
  final VoidCallback onEdit;
  final VoidCallback onDecrement;
  final VoidCallback onIncrement;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final product = line.catalogProduct.product;
    final scheme = context.colors;
    final overridden = line.overrideUnitPrice != null;
    return InkWell(
      onTap: onEdit,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
        child: Row(
          children: [
            ProductThumb(name: product.name, path: product.imagePath, size: 42),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    product.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 2),
                  Wrap(
                    spacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        '${money.format(line.unitPrice)} / ${product.unit}',
                        style: context.text.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                      if (overridden)
                        const StatusPill('Price edited', tone: PillTone.info),
                      if (totals.discount.minorUnits > 0)
                        StatusPill(
                          '−${money.format(totals.discount)}',
                          tone: PillTone.success,
                        ),
                    ],
                  ),
                ],
              ),
            ),
            _Stepper(
              quantity: formatQuantity(line.quantityMilli),
              onDecrement: onDecrement,
              onIncrement: onIncrement,
              onTap: onEdit,
            ),
            SizedBox(
              width: 96,
              child: Text(
                money.format(totals.total),
                textAlign: TextAlign.end,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
            IconButton(
              tooltip: 'Remove',
              visualDensity: VisualDensity.compact,
              onPressed: onRemove,
              icon: Icon(Icons.close_rounded, size: 18, color: scheme.outline),
            ),
          ],
        ),
      ),
    ).entrance(context, dy: 0);
  }
}

class _Stepper extends StatelessWidget {
  const _Stepper({
    required this.quantity,
    required this.onDecrement,
    required this.onIncrement,
    required this.onTap,
  });
  final String quantity;
  final VoidCallback onDecrement;
  final VoidCallback onIncrement;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.symmetric(horizontal: 6),
    decoration: BoxDecoration(
      color: context.colors.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(99),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _StepButton(icon: Icons.remove_rounded, onTap: onDecrement),
        InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 30),
            child: Text(
              quantity,
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ),
        _StepButton(icon: Icons.add_rounded, onTap: onIncrement),
      ],
    ),
  );
}

class _StepButton extends StatelessWidget {
  const _StepButton({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => InkWell(
    customBorder: const CircleBorder(),
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.all(6),
      child: Icon(icon, size: 16),
    ),
  );
}

class _ToolButton extends StatelessWidget {
  const _ToolButton({
    required this.icon,
    required this.label,
    this.shortcut,
    this.onTap,
  });
  final IconData icon;
  final String label;
  final String? shortcut;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Expanded(
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: TextButton(
        onPressed: onTap,
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 8),
        ),
        child: Column(
          children: [
            Icon(icon, size: 20),
            const SizedBox(height: 2),
            Text(
              shortcut == null ? label : '$label · $shortcut',
              style: const TextStyle(fontSize: 12),
            ),
          ],
        ),
      ),
    ),
  );
}

class _AmountRow extends StatelessWidget {
  const _AmountRow(this.label, this.value, {this.color});
  final String label;
  final String value;
  final Color? color;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(color: context.colors.onSurfaceVariant),
          ),
        ),
        Text(
          value,
          style: TextStyle(fontWeight: FontWeight.w700, color: color),
        ),
      ],
    ),
  );
}

class _ScannerStatus extends StatelessWidget {
  const _ScannerStatus({this.lastScan});
  final String? lastScan;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final scanned = lastScan != null;
    return Tooltip(
      message: 'USB barcode scanners work anywhere on this screen. Just scan.',
      child: AnimatedContainer(
        duration: tokens.motion(150),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: scanned
              ? tokens.successContainer
              : context.colors.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(99),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              scanned ? Icons.check_circle_rounded : Icons.sensors_rounded,
              size: 14,
              color: scanned ? tokens.success : context.colors.primary,
            ),
            const SizedBox(width: 5),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 160),
              child: Text(
                scanned ? lastScan! : 'Scanner ready',
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: scanned
                      ? tokens.success
                      : context.colors.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
