import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/database_provider.dart';
import '../../../core/money/money.dart';
import '../../auth/application/session_controller.dart';
import '../../auth/domain/permissions.dart';
import '../../categories/data/category_repository.dart';
import '../../customers/data/customer_repository.dart';
import '../../history/data/sales_repository.dart';
import '../../products/data/product_repository.dart';
import '../../receipts/data/receipt_service.dart';
import '../application/cart_controller.dart';
import '../data/checkout_service.dart';
import '../data/held_cart_repository.dart';
import '../domain/pos_cart.dart';

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
  Customer? _customer;
  TaxMode _taxMode = TaxMode.exclusive;

  @override
  void initState() {
    super.initState();
    _loadTaxMode();
  }

  Future<void> _loadTaxMode() async {
    final database = ref.read(databaseProvider);
    final row = await database
        .customSelect(
          "SELECT value FROM app_settings WHERE key = 'tax.mode' LIMIT 1",
        )
        .getSingleOrNull();
    final name = row?.read<String>('value');
    if (mounted) {
      setState(() {
        _taxMode =
            TaxMode.values.where((value) => value.name == name).firstOrNull ??
            TaxMode.exclusive;
      });
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  Future<void> _searchSubmitted(String value) async {
    final code = value.trim();
    if (code.isEmpty) return;
    final session = ref.read(activeSessionProvider)!;
    final product = await ref
        .read(productRepositoryProvider)
        .exactLookup(storeId: session.store.id, code: code);
    if (product != null) {
      ref.read(cartControllerProvider.notifier).add(product);
      _search.clear();
      setState(() => _term = '');
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(activeSessionProvider)!;
    final cart = ref.watch(cartControllerProvider);
    final totals = cart.totals(_taxMode);
    final products = ref
        .watch(productRepositoryProvider)
        .watchPosProducts(
          storeId: session.store.id,
          search: _term,
          categoryId: _categoryId,
        );
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.f2): _searchFocus.requestFocus,
        const SingleActivator(LogicalKeyboardKey.keyF, control: true):
            _searchFocus.requestFocus,
        const SingleActivator(LogicalKeyboardKey.keyN, control: true): () =>
            _newSale(context),
        const SingleActivator(LogicalKeyboardKey.f3): () =>
            _selectCustomer(context),
        const SingleActivator(LogicalKeyboardKey.f4): () => _hold(context),
        const SingleActivator(LogicalKeyboardKey.f6): () =>
            _saleDiscount(context),
        const SingleActivator(LogicalKeyboardKey.f7): () => _payment(context),
        const SingleActivator(LogicalKeyboardKey.f8): () => _quickCash(context),
        const SingleActivator(LogicalKeyboardKey.f10): () => _payment(context),
      },
      child: Focus(
        autofocus: true,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Expanded(
                flex: 4,
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(13),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        TextField(
                          controller: _search,
                          focusNode: _searchFocus,
                          autofocus: true,
                          onSubmitted: _searchSubmitted,
                          onChanged: (value) {
                            _debounce?.cancel();
                            _debounce = Timer(
                              const Duration(milliseconds: 160),
                              () {
                                if (mounted) {
                                  setState(() => _term = value.trim());
                                }
                              },
                            );
                          },
                          decoration: const InputDecoration(
                            prefixIcon: Icon(Icons.qr_code_scanner),
                            hintText: 'Scan barcode or search products',
                            suffixText: 'F2',
                          ),
                        ),
                        const SizedBox(height: 10),
                        SizedBox(
                          height: 36,
                          child: StreamBuilder<List<Category>>(
                            stream: ref
                                .watch(categoryRepositoryProvider)
                                .watch(active: true),
                            builder: (context, snapshot) => ListView(
                              scrollDirection: Axis.horizontal,
                              children: [
                                Padding(
                                  padding: const EdgeInsets.only(right: 6),
                                  child: ChoiceChip(
                                    label: const Text('All'),
                                    selected: _categoryId == null,
                                    onSelected: (_) =>
                                        setState(() => _categoryId = null),
                                  ),
                                ),
                                ...(snapshot.data ?? const []).map(
                                  (category) => Padding(
                                    padding: const EdgeInsets.only(right: 6),
                                    child: ChoiceChip(
                                      label: Text(category.name),
                                      selected: _categoryId == category.id,
                                      onSelected: (_) => setState(
                                        () => _categoryId = category.id,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 9),
                        Expanded(
                          child: StreamBuilder<List<CatalogProduct>>(
                            stream: products,
                            builder: (context, snapshot) {
                              if (!snapshot.hasData) {
                                return const Center(
                                  child: CircularProgressIndicator(),
                                );
                              }
                              final items = snapshot.data!;
                              if (items.isEmpty) {
                                return const Center(
                                  child: Text('No sellable products found.'),
                                );
                              }
                              return GridView.builder(
                                gridDelegate:
                                    const SliverGridDelegateWithMaxCrossAxisExtent(
                                      maxCrossAxisExtent: 205,
                                      mainAxisExtent: 120,
                                      crossAxisSpacing: 9,
                                      mainAxisSpacing: 9,
                                    ),
                                itemCount: items.length,
                                itemBuilder: (context, index) {
                                  final item = items[index];
                                  return InkWell(
                                    borderRadius: BorderRadius.circular(10),
                                    onTap: () => ref
                                        .read(cartControllerProvider.notifier)
                                        .add(item),
                                    child: Ink(
                                      padding: const EdgeInsets.all(11),
                                      decoration: BoxDecoration(
                                        border: Border.all(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .outlineVariant,
                                        ),
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            item.product.name,
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                          const Spacer(),
                                          Text(
                                            item.product.sku,
                                            style: Theme.of(context)
                                                .textTheme
                                                .labelSmall,
                                          ),
                                          Row(
                                            children: [
                                              Expanded(
                                                child: Text(
                                                  'Rs ${item.effectivePrice.toStringAsFixed(2)}',
                                                  style: TextStyle(
                                                    color: Theme.of(context)
                                                        .colorScheme
                                                        .primary,
                                                    fontWeight: FontWeight.w800,
                                                  ),
                                                ),
                                              ),
                                              if (item.product.trackInventory)
                                                Text(
                                                  item.store.stockQty
                                                      .toStringAsFixed(0),
                                                  style: Theme.of(context)
                                                      .textTheme
                                                      .labelSmall,
                                                ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                flex: 4,
                child: _CartCard(cart: cart, taxMode: _taxMode),
              ),
              const SizedBox(width: 11),
              SizedBox(
                width: 278,
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(15),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Text(
                              'Checkout',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const Spacer(),
                            IconButton(
                              tooltip: 'Held carts',
                              onPressed: () => _heldCarts(context),
                              icon: const Icon(Icons.inventory_2_outlined),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        OutlinedButton.icon(
                          onPressed: () => _selectCustomer(context),
                          icon: const Icon(Icons.person_outline),
                          label: Text(
                            _customer?.name ?? 'Walk-in customer',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(height: 18),
                        _AmountRow('Subtotal', totals.subtotal),
                        const SizedBox(height: 8),
                        _AmountRow(
                          'Discount',
                          -(totals.lineDiscount + totals.saleDiscount),
                        ),
                        const SizedBox(height: 8),
                        _AmountRow('Tax', totals.tax),
                        const SizedBox(height: 12),
                        const Divider(),
                        const SizedBox(height: 12),
                        Text(
                          'Grand total',
                          style: Theme.of(context).textTheme.labelLarge,
                        ),
                        Text(
                          'Rs ${totals.grandTotal}',
                          style: Theme.of(context).textTheme.headlineMedium
                              ?.copyWith(
                                color: Theme.of(context).colorScheme.primary,
                                fontWeight: FontWeight.w900,
                              ),
                        ),
                        const Spacer(),
                        OutlinedButton(
                          onPressed: cart.lines.isEmpty
                              ? null
                              : () => _hold(context),
                          child: const Text('Hold sale  F4'),
                        ),
                        const SizedBox(height: 8),
                        FilledButton.icon(
                          onPressed: cart.lines.isEmpty
                              ? null
                              : () => _payment(context),
                          icon: const Icon(Icons.payments_outlined),
                          label: const Text('Payment  F7'),
                        ),
                        const SizedBox(height: 5),
                        TextButton(
                          onPressed: cart.lines.isEmpty
                              ? null
                              : ref.read(cartControllerProvider.notifier).clear,
                          child: const Text('Clear cart'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _selectCustomer(BuildContext context) async {
    final search = TextEditingController();
    var results = await ref.read(customerRepositoryProvider).search('');
    if (!context.mounted) return;
    final selected = await showDialog<Customer?>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Select customer'),
          content: SizedBox(
            width: 520,
            height: 430,
            child: Column(
              children: [
                TextField(
                  controller: search,
                  autofocus: true,
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    hintText: 'Name or phone',
                  ),
                  onChanged: (value) async {
                    final next = await ref
                        .read(customerRepositoryProvider)
                        .search(value);
                    setDialogState(() => results = next);
                  },
                ),
                const SizedBox(height: 10),
                ListTile(
                  leading: const CircleAvatar(
                    child: Icon(Icons.person_outline),
                  ),
                  title: const Text('Walk-in customer'),
                  onTap: () => Navigator.pop(context),
                ),
                const Divider(),
                Expanded(
                  child: ListView.builder(
                    itemCount: results.length,
                    itemBuilder: (context, index) {
                      final customer = results[index];
                      return ListTile(
                        title: Text(customer.name),
                        subtitle: Text(customer.phone ?? ''),
                        onTap: () => Navigator.pop(context, customer),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          actions: [
            if (ref
                .read(activeSessionProvider)!
                .can(Permissions.customersCreate))
              TextButton.icon(
                onPressed: () async {
                  final created = await _createCustomer(context);
                  if (created != null && context.mounted) {
                    Navigator.pop(context, created);
                  }
                },
                icon: const Icon(Icons.person_add_alt),
                label: const Text('New customer'),
              ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
          ],
        ),
      ),
    );
    if (!mounted) return;
    setState(() => _customer = selected);
    ref.read(cartControllerProvider.notifier).selectCustomer(selected?.id);
  }

  Future<Customer?> _createCustomer(BuildContext context) async {
    final name = TextEditingController();
    final phone = TextEditingController();
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Quick customer'),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: name,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Name'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: phone,
                decoration: const InputDecoration(labelText: 'Phone'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (name.text.trim().isNotEmpty) Navigator.pop(context, true);
            },
            child: const Text('Create & select'),
          ),
        ],
      ),
    );
    if (saved != true) return null;
    final repository = ref.read(customerRepositoryProvider);
    final id = await repository.save(
      session: ref.read(activeSessionProvider)!,
      name: name.text,
      phone: phone.text,
    );
    return repository.byId(id);
  }

  Future<void> _hold(BuildContext context) async {
    final cart = ref.read(cartControllerProvider);
    if (cart.lines.isEmpty) return;
    final label = await _prompt(context, 'Hold sale', 'Reference or note');
    if (label == null) return;
    await ref
        .read(heldCartRepositoryProvider)
        .save(ref.read(activeSessionProvider)!, cart, label: label);
    ref.read(cartControllerProvider.notifier).clear();
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Sale held.')));
    }
  }

  Future<void> _heldCarts(BuildContext context) async {
    final session = ref.read(activeSessionProvider)!;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Held carts'),
        content: SizedBox(
          width: 600,
          height: 420,
          child: StreamBuilder<List<HeldCart>>(
            stream: ref.read(heldCartRepositoryProvider).watch(session),
            builder: (context, snapshot) {
              final carts = snapshot.data ?? const [];
              if (carts.isEmpty) {
                return const Center(child: Text('No held carts.'));
              }
              return ListView.separated(
                itemCount: carts.length,
                separatorBuilder: (_, _) => const Divider(),
                itemBuilder: (context, index) {
                  final held = carts[index];
                  return ListTile(
                    title: Text(held.label),
                    subtitle: Text(
                      held.updatedAt.toLocal().toString().split('.').first,
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: 'Delete',
                          onPressed: () async {
                            final confirmed = await showDialog<bool>(
                              context: context,
                              builder: (dialogContext) => AlertDialog(
                                title: const Text('Delete held cart?'),
                                content: Text(
                                  '“${held.label}” will be permanently removed.',
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () =>
                                        Navigator.pop(dialogContext, false),
                                    child: const Text('Cancel'),
                                  ),
                                  FilledButton(
                                    onPressed: () =>
                                        Navigator.pop(dialogContext, true),
                                    child: const Text('Delete'),
                                  ),
                                ],
                              ),
                            );
                            if (confirmed != true) return;
                            await ref
                                .read(heldCartRepositoryProvider)
                                .remove(session, held.id);
                          },
                          icon: const Icon(Icons.delete_outline),
                        ),
                        FilledButton(
                          onPressed: () async {
                            final cart = await ref
                                .read(heldCartRepositoryProvider)
                                .restore(session, held);
                            ref
                                .read(cartControllerProvider.notifier)
                                .replace(cart);
                            await ref
                                .read(heldCartRepositoryProvider)
                                .remove(session, held.id);
                            if (context.mounted) Navigator.pop(context);
                          },
                          child: const Text('Resume'),
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
      ),
    );
  }

  Future<void> _saleDiscount(BuildContext context) async {
    final session = ref.read(activeSessionProvider)!;
    if (!session.can(Permissions.posApplyDiscount)) return;
    final input = TextEditingController();
    var kind = 'percent';
    final result = await showDialog<(String, double)>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Sale discount'),
          content: SizedBox(
            width: 420,
            child: Row(
              children: [
                SizedBox(
                  width: 150,
                  child: DropdownButtonFormField<String>(
                    initialValue: kind,
                    items: const [
                      DropdownMenuItem(
                        value: 'percent',
                        child: Text('Percentage'),
                      ),
                      DropdownMenuItem(
                        value: 'fixed',
                        child: Text('Fixed amount'),
                      ),
                    ],
                    onChanged: (value) =>
                        setDialogState(() => kind = value ?? 'percent'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: input,
                    autofocus: true,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(
                      prefixText: kind == 'fixed' ? 'Rs ' : null,
                      suffixText: kind == 'percent' ? '%' : null,
                    ),
                    onSubmitted: (value) {
                      final amount = double.tryParse(value);
                      if (amount != null) {
                        Navigator.pop(context, (kind, amount));
                      }
                    },
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, ('percent', 0)),
              child: const Text('Clear'),
            ),
            FilledButton(
              onPressed: () {
                final amount = double.tryParse(input.text);
                if (amount != null) Navigator.pop(context, (kind, amount));
              },
              child: const Text('Apply'),
            ),
          ],
        ),
      ),
    );
    if (result == null) return;
    final controller = ref.read(cartControllerProvider.notifier);
    if (result.$1 == 'fixed') {
      controller.setSaleDiscount(fixed: Money.fromMajor(result.$2));
    } else {
      controller.setSaleDiscount(percent: result.$2.clamp(0, 100));
    }
  }

  Future<void> _newSale(BuildContext context) async {
    final cart = ref.read(cartControllerProvider);
    if (cart.lines.isNotEmpty) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Start a new sale?'),
          content: const Text('The current cart will be cleared.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Keep cart'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('New sale'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }
    ref.read(cartControllerProvider.notifier).clear();
    setState(() => _customer = null);
    _searchFocus.requestFocus();
  }

  Future<void> _quickCash(BuildContext context) async {
    final total = ref.read(cartControllerProvider).totals(_taxMode).grandTotal;
    if (total.minorUnits == 0) return;
    await _complete(context, [PaymentInput(method: 'cash', amount: total)]);
  }

  Future<void> _payment(BuildContext context) async {
    final total = ref.read(cartControllerProvider).totals(_taxMode).grandTotal;
    if (total.minorUnits == 0) return;
    final payments = <_PaymentDraft>[
      _PaymentDraft(amount: TextEditingController(text: total.toString())),
    ];
    final result = await showDialog<List<PaymentInput>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          List<PaymentInput> mappedPayments() => payments
              .map(
                (draft) => PaymentInput(
                  method: draft.method,
                  amount: Money.fromMajor(
                    double.tryParse(draft.amount.text) ?? 0,
                  ),
                ),
              )
              .toList();
          final mapped = mappedPayments();
          final paid = mapped.fold(
            Money.zero,
            (sum, payment) => sum + payment.amount,
          );
          final ready = paid.compareTo(total) >= 0;
          void complete() {
            if (ready) Navigator.pop(context, mappedPayments());
          }

          return CallbackShortcuts(
            bindings: {const SingleActivator(LogicalKeyboardKey.f10): complete},
            child: Focus(
              autofocus: true,
              child: AlertDialog(
                title: Text('Payment · Rs $total'),
                content: SizedBox(
                  width: 560,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (var index = 0; index < payments.length; index++)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Row(
                            children: [
                              Expanded(
                                child: DropdownButtonFormField<String>(
                                  initialValue: payments[index].method,
                                  decoration: const InputDecoration(
                                    labelText: 'Method',
                                  ),
                                  items: const ['cash', 'card', 'bank', 'other']
                                      .map(
                                        (value) => DropdownMenuItem(
                                          value: value,
                                          child: Text(value.toUpperCase()),
                                        ),
                                      )
                                      .toList(),
                                  onChanged: (value) =>
                                      payments[index].method = value ?? 'cash',
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: TextField(
                                  controller: payments[index].amount,
                                  autofocus: index == 0,
                                  keyboardType: TextInputType.number,
                                  decoration: const InputDecoration(
                                    labelText: 'Amount',
                                  ),
                                  onChanged: (_) => setDialogState(() {}),
                                  onSubmitted: (_) => complete(),
                                ),
                              ),
                              if (payments.length > 1)
                                IconButton(
                                  onPressed: () => setDialogState(
                                    () => payments.removeAt(index),
                                  ),
                                  icon: const Icon(Icons.close),
                                ),
                            ],
                          ),
                        ),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: () => setDialogState(
                            () => payments.add(
                              _PaymentDraft(amount: TextEditingController()),
                            ),
                          ),
                          icon: const Icon(Icons.add),
                          label: const Text('Add split payment'),
                        ),
                      ),
                      const Divider(height: 24),
                      Row(
                        children: [
                          Text('Tendered: Rs $paid'),
                          const Spacer(),
                          Text(
                            ready
                                ? 'Change: Rs ${paid - total}'
                                : 'Remaining: Rs ${total - paid}',
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                  FilledButton(
                    onPressed: ready ? complete : null,
                    child: const Text('Complete sale  F10'),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
    if (result != null && context.mounted) await _complete(context, result);
  }

  Future<void> _complete(
    BuildContext context,
    List<PaymentInput> payments,
  ) async {
    try {
      final result = await ref
          .read(checkoutServiceProvider)
          .checkout(
            session: ref.read(activeSessionProvider)!,
            cart: ref.read(cartControllerProvider),
            payments: payments,
          );
      ref.read(cartControllerProvider.notifier).clear();
      setState(() => _customer = null);
      if (!context.mounted) return;
      final print = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          icon: const Icon(Icons.check_circle_outline, size: 42),
          title: Text('Sale completed · ${result.invoiceNumber}'),
          content: Text(
            'Total: Rs ${result.total}\nReceived: Rs ${result.received}\nChange: Rs ${result.change}',
            textAlign: TextAlign.center,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Done'),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.pop(context, true),
              icon: const Icon(Icons.print_outlined),
              label: const Text('Print receipt'),
            ),
          ],
        ),
      );
      if (print == true) {
        final details = await ref
            .read(salesRepositoryProvider)
            .details(ref.read(activeSessionProvider)!, result.saleId);
        await ref.read(receiptServiceProvider).printReceipt(details);
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(error.toString()),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  Future<String?> _prompt(BuildContext context, String title, String label) {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(labelText: label),
          onSubmitted: (value) => Navigator.pop(context, value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
  }
}

class _CartCard extends ConsumerWidget {
  const _CartCard({required this.cart, required this.taxMode});
  final PosCart cart;
  final TaxMode taxMode;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(activeSessionProvider);
    final canDiscount = session?.can(Permissions.posApplyDiscount) ?? false;
    final canOverride = session?.can(Permissions.posOverridePrice) ?? false;
    return Card(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Text(
                  'Current cart',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const Spacer(),
                Badge(
                  label: Text('${cart.lines.length}'),
                  child: const Icon(Icons.shopping_bag_outlined),
                ),
              ],
            ),
          ),
          const Divider(),
          Expanded(
            child: cart.lines.isEmpty
                ? const Center(
                    child: Text('Scan or select a product to begin.'),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(10),
                    itemCount: cart.lines.length,
                    separatorBuilder: (_, _) => const Divider(),
                    itemBuilder: (context, index) {
                      final line = cart.lines[index];
                      final totals = cart.lineTotals(line, taxMode);
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 5),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    line.catalogProduct.product.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  Text(
                                    'Rs ${line.unitPrice} · ${totals.discount.minorUnits > 0 ? 'discount Rs ${totals.discount}' : line.catalogProduct.product.sku}',
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelSmall,
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              visualDensity: VisualDensity.compact,
                              onPressed: () => ref
                                  .read(cartControllerProvider.notifier)
                                  .setQuantity(
                                    index,
                                    line.quantityMilli / 1000 - 1,
                                  ),
                              icon: const Icon(
                                Icons.remove_circle_outline,
                                size: 19,
                              ),
                            ),
                            InkWell(
                              onTap: () =>
                                  _editQuantity(context, ref, index, line),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 5,
                                  vertical: 8,
                                ),
                                child: Text(
                                  (line.quantityMilli / 1000).toStringAsFixed(
                                    line.quantityMilli % 1000 == 0 ? 0 : 3,
                                  ),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                            ),
                            IconButton(
                              visualDensity: VisualDensity.compact,
                              onPressed: () => ref
                                  .read(cartControllerProvider.notifier)
                                  .setQuantity(
                                    index,
                                    line.quantityMilli / 1000 + 1,
                                  ),
                              icon: const Icon(
                                Icons.add_circle_outline,
                                size: 19,
                              ),
                            ),
                            SizedBox(
                              width: 75,
                              child: Text(
                                'Rs ${totals.total}',
                                textAlign: TextAlign.end,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                            if (canDiscount || canOverride)
                              PopupMenuButton<String>(
                                tooltip: 'Line actions',
                                onSelected: (action) => _editLineAdjustment(
                                  context,
                                  ref,
                                  index,
                                  line,
                                  action,
                                ),
                                itemBuilder: (context) => [
                                  if (canDiscount)
                                    const PopupMenuItem(
                                      value: 'discount_percent',
                                      child: Text('Line discount %'),
                                    ),
                                  if (canDiscount)
                                    const PopupMenuItem(
                                      value: 'discount_fixed',
                                      child: Text('Line discount amount'),
                                    ),
                                  if (canOverride)
                                    const PopupMenuItem(
                                      value: 'price',
                                      child: Text('Override price'),
                                    ),
                                  const PopupMenuItem(
                                    value: 'reset',
                                    child: Text('Reset adjustments'),
                                  ),
                                ],
                              ),
                            IconButton(
                              tooltip: 'Remove',
                              visualDensity: VisualDensity.compact,
                              onPressed: () => ref
                                  .read(cartControllerProvider.notifier)
                                  .remove(index),
                              icon: const Icon(Icons.close, size: 17),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
          const Divider(),
          Padding(
            padding: const EdgeInsets.fromLTRB(11, 3, 11, 3),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    cart.notes.isEmpty
                        ? 'F3 Customer · F4 Hold · F6 Discount · F7 Payment'
                        : 'Note: ${cart.notes}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11),
                  ),
                ),
                TextButton.icon(
                  onPressed: () => _editNotes(context, ref, cart.notes),
                  icon: const Icon(Icons.note_alt_outlined, size: 17),
                  label: const Text('Note'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _editLineAdjustment(
    BuildContext context,
    WidgetRef ref,
    int index,
    CartLine line,
    String action,
  ) async {
    final controller = ref.read(cartControllerProvider.notifier);
    if (action == 'reset') {
      controller.setLineDiscount(index);
      controller.clearPriceOverride(index);
      return;
    }
    final isPercent = action == 'discount_percent';
    final isFixed = action == 'discount_fixed';
    final current = isPercent
        ? line.manualDiscountPercent.toString()
        : isFixed
        ? line.manualDiscount.toString()
        : line.unitPrice.toString();
    final input = TextEditingController(text: current);
    final value = await showDialog<double>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          isPercent
              ? 'Line discount percentage'
              : isFixed
              ? 'Line discount amount'
              : 'Override price',
        ),
        content: TextField(
          controller: input,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            suffixText: isPercent ? '%' : null,
            prefixText: isPercent ? null : 'Rs ',
          ),
          onSubmitted: (value) =>
              Navigator.pop(context, double.tryParse(value)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(context, double.tryParse(input.text)),
            child: const Text('Apply'),
          ),
        ],
      ),
    );
    if (value == null) return;
    if (isPercent) {
      controller.setLineDiscount(index, percent: value.clamp(0, 100));
    } else if (isFixed) {
      controller.setLineDiscount(index, fixed: Money.fromMajor(value));
    } else if (value >= 0) {
      controller.overridePrice(index, Money.fromMajor(value));
    }
  }

  Future<void> _editNotes(
    BuildContext context,
    WidgetRef ref,
    String current,
  ) async {
    final input = TextEditingController(text: current);
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sale note'),
        content: TextField(controller: input, autofocus: true, maxLines: 3),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, input.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (value != null) {
      ref.read(cartControllerProvider.notifier).setNotes(value);
    }
  }

  Future<void> _editQuantity(
    BuildContext context,
    WidgetRef ref,
    int index,
    CartLine line,
  ) async {
    final controller = TextEditingController(
      text: (line.quantityMilli / 1000).toString(),
    );
    final value = await showDialog<double>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Quantity'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          onSubmitted: (value) =>
              Navigator.pop(context, double.tryParse(value)),
        ),
        actions: [
          FilledButton(
            onPressed: () =>
                Navigator.pop(context, double.tryParse(controller.text)),
            child: const Text('Apply'),
          ),
        ],
      ),
    );
    if (value != null) {
      ref.read(cartControllerProvider.notifier).setQuantity(index, value);
    }
  }
}

class _AmountRow extends StatelessWidget {
  const _AmountRow(this.label, this.value);
  final String label;
  final Money value;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(child: Text(label)),
      Text(
        '${value.minorUnits < 0 ? '−' : ''}Rs ${Money.fromMinor(value.minorUnits.abs())}',
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
    ],
  );
}

class _PaymentDraft {
  _PaymentDraft({required this.amount}) : method = 'cash';
  final TextEditingController amount;
  String method;
}
