import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/money/money.dart';
import '../../../core/money/money_format.dart';
import '../../../core/ui/ui_kit.dart';
import '../../auth/application/session_controller.dart';
import '../../auth/domain/permissions.dart';
import '../../customers/presentation/customer_editor.dart';
import '../../pos/application/cart_controller.dart';
import '../../receipts/data/receipt_service.dart';
import '../../settings/data/business_settings_repository.dart';
import '../../settings/domain/receipt_layout.dart';
import '../../stores/data/store_repository.dart';
import '../data/credit_service.dart';
import '../data/statement_export.dart';
import '../domain/credit.dart';
import 'receive_payment_dialog.dart';

final _date = DateFormat('d MMM y');
final _dateTime = DateFormat('d MMM y, h:mm a');

/// Customer account: balance, invoices, ledger and payments.
class CustomerDetailPage extends ConsumerStatefulWidget {
  const CustomerDetailPage({required this.customerId, super.key});
  final String customerId;

  @override
  ConsumerState<CustomerDetailPage> createState() => _CustomerDetailPageState();
}

class _CustomerDetailPageState extends ConsumerState<CustomerDetailPage> {
  late Future<CustomerBalance> _balance;
  late Future<List<CustomerInvoice>> _invoices;
  late Future<List<OpenItem>> _openItems;
  late Future<List<PaymentRecord>> _payments;
  late Future<LedgerPage> _ledger;
  DateTimeRange? _range;
  String? _storeFilter;
  LedgerFilter _ledgerFilter = LedgerFilter.all;
  String _search = '';

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void didUpdateWidget(CustomerDetailPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.customerId != widget.customerId) _reload();
  }

  void _reload() {
    final session = ref.read(activeSessionProvider)!;
    final service = ref.read(creditServiceProvider);
    _balance = service.balance(session, widget.customerId);
    _invoices = service.invoices(session, widget.customerId);
    _openItems = session.can(Permissions.creditView)
        ? service.openItems(session, widget.customerId)
        : Future.value(const []);
    _payments = session.can(Permissions.creditView)
        ? service.payments(session, customerId: widget.customerId)
        : Future.value(const []);
    _loadLedger();
  }

  void _loadLedger() {
    final session = ref.read(activeSessionProvider)!;
    _ledger = session.can(Permissions.creditView)
        ? ref
              .read(creditServiceProvider)
              .ledger(
                session,
                widget.customerId,
                from: _range?.start,
                to: _range == null
                    ? null
                    : DateTime(
                        _range!.end.year,
                        _range!.end.month,
                        _range!.end.day + 1,
                      ),
                storeId: _storeFilter,
                filter: _ledgerFilter,
                search: _search,
              )
        : Future.value(
            const LedgerPage(
              opening: Money.zero,
              rows: [],
              closing: Money.zero,
            ),
          );
  }

  Future<void> _receivePayment() async {
    final session = ref.read(activeSessionProvider)!;
    if (!session.can(Permissions.creditReceivePayment)) return;
    final result = await showReceivePaymentDialog(
      context,
      customerId: widget.customerId,
    );
    if (result == null || !mounted) return;
    final money = ref.read(moneyFormatterProvider);
    Toast.success(
      context,
      '${result.number}: ${money.format(result.amount)} received. '
      'Balance now ${money.format(result.balance)}.',
    );
    setState(_reload);
  }

  Future<void> _edit() async {
    final balance = await _balance;
    if (!mounted) return;
    final saved = await editCustomer(context, ref, customer: balance.customer);
    if (saved != null && mounted) setState(_reload);
  }

  void _newSale() {
    ref.read(cartControllerProvider.notifier).selectCustomer(widget.customerId);
    context.go('/pos');
  }

  Future<void> _statement({required bool print}) async {
    final session = ref.read(activeSessionProvider)!;
    final money = ref.read(moneyFormatterProvider);
    final settings = ref.read(currentBusinessSettingsProvider);
    try {
      final balance = await _balance;
      // Statements always show every entry in the period.
      final page = await ref
          .read(creditServiceProvider)
          .ledger(
            session,
            widget.customerId,
            from: _range?.start,
            to: _range == null
                ? null
                : DateTime(
                    _range!.end.year,
                    _range!.end.month,
                    _range!.end.day + 1,
                  ),
          );
      final bytes = await buildStatementPdf(
        businessName: settings.businessName,
        storeName: session.store.name,
        period: _range == null ? 'All activity' : describeRange(_range),
        balance: balance,
        page: page,
        money: money,
      );
      final receipts = ref.read(receiptServiceProvider);
      if (print) {
        await receipts.printBytes(
          bytes,
          name: 'Statement ${balance.customer.name}',
          paper: ReceiptPaper.a4,
        );
      } else {
        final path = await receipts.saveBytes(
          bytes,
          'statement-${balance.customer.name.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '-').toLowerCase()}.pdf',
        );
        if (path != null && mounted) Toast.success(context, 'Saved $path');
      }
    } catch (error) {
      if (mounted) Toast.error(context, error);
    }
  }

  Future<void> _changeDueDate(CustomerInvoice invoice) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 2),
      initialDate: invoice.sale.dueDate ?? now,
      helpText: 'Due date for ${invoice.sale.invoiceNumber}',
    );
    if (picked == null || !mounted) return;
    try {
      await ref
          .read(creditServiceProvider)
          .setDueDate(
            ref.read(activeSessionProvider)!,
            saleId: invoice.sale.id,
            dueDate: picked,
          );
      if (mounted) {
        Toast.success(context, 'Due date changed to ${_date.format(picked)}.');
        setState(_reload);
      }
    } catch (error) {
      if (mounted) Toast.error(context, error);
    }
  }

  Future<void> _reverse(PaymentRecord record) async {
    final reason = await promptDialog(
      context,
      title: 'Reverse ${record.payment.number}?',
      label: 'Reason',
      hint: 'e.g. cheque bounced, wrong customer',
      confirmLabel: 'Reverse payment',
      validator: (value) =>
          value.trim().isEmpty ? 'Enter a reason for the reversal.' : null,
    );
    if (reason == null || !mounted) return;
    try {
      await ref
          .read(creditServiceProvider)
          .reversePayment(
            ref.read(activeSessionProvider)!,
            paymentId: record.payment.id,
            reason: reason,
          );
      if (mounted) {
        Toast.success(context, '${record.payment.number} reversed.');
        setState(_reload);
      }
    } catch (error) {
      if (mounted) Toast.error(context, error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(activeSessionProvider)!;
    final money = ref.watch(moneyFormatterProvider);
    final canReceive = session.can(Permissions.creditReceivePayment);
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(
          LogicalKeyboardKey.keyP,
          control: true,
          shift: true,
        ): _receivePayment,
      },
      child: Focus(
        autofocus: true,
        child: FutureBuilder<CustomerBalance>(
          future: _balance,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return EmptyState(
                icon: Icons.person_off_outlined,
                title: 'Customer could not be loaded',
                message: friendlyError(snapshot.error!),
                action: OutlinedButton(
                  onPressed: () => context.go('/customers'),
                  child: const Text('Back to customers'),
                ),
              );
            }
            final balance = snapshot.data;
            if (balance == null) {
              return const Center(child: CircularProgressIndicator());
            }
            return DefaultTabController(
              length: session.can(Permissions.creditView) ? 4 : 2,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _header(context, balance, money, canReceive),
                    const SizedBox(height: 16),
                    _stats(context, balance, money),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: TabBar(
                            isScrollable: true,
                            tabAlignment: TabAlignment.start,
                            tabs: [
                              const Tab(text: 'Overview'),
                              const Tab(text: 'Invoices'),
                              if (session.can(
                                Permissions.creditView,
                              )) ...const [
                                Tab(text: 'Ledger'),
                                Tab(text: 'Payments'),
                              ],
                            ],
                          ),
                        ),
                        _actions(context, balance, canReceive),
                      ],
                    ),
                    Expanded(
                      child: TabBarView(
                        children: [
                          _overview(context, balance, money),
                          _invoiceList(
                            context,
                            money,
                            session.can(Permissions.creditEditDueDate),
                          ),
                          if (session.can(Permissions.creditView)) ...[
                            _ledgerTab(
                              context,
                              money,
                              session.can(Permissions.customerStatement),
                            ),
                            _paymentList(context, money, canReceive),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _header(
    BuildContext context,
    CustomerBalance balance,
    MoneyFormatter money,
    bool canReceive,
  ) {
    final customer = balance.customer;
    return Row(
      children: [
        IconButton(
          tooltip: 'Back to customers',
          onPressed: () => context.go('/customers'),
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        const SizedBox(width: 6),
        CircleAvatar(
          radius: 26,
          child: Text(
            customer.name.characters.first.toUpperCase(),
            style: context.text.titleLarge,
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(
                      customer.name,
                      overflow: TextOverflow.ellipsis,
                      style: context.text.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  StatusPill(
                    customer.isActive ? 'Active' : 'Inactive',
                    tone: customer.isActive
                        ? PillTone.success
                        : PillTone.neutral,
                    icon: customer.isActive
                        ? Icons.check_circle_outline_rounded
                        : Icons.pause_circle_outline_rounded,
                  ),
                  if (balance.hasBalance) ...[
                    const SizedBox(width: 6),
                    DueStatusPill(balance.dueStatus),
                  ],
                ],
              ),
              Text(
                [
                  if (customer.phone?.isNotEmpty ?? false) customer.phone!,
                  if (customer.email?.isNotEmpty ?? false) customer.email!,
                  '${customer.loyaltyPoints} points',
                ].join(' · '),
                style: TextStyle(color: context.colors.onSurfaceVariant),
              ),
            ],
          ),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text('Outstanding', style: context.text.labelMedium),
            Text(
              money.format(balance.outstanding),
              style: context.text.headlineMedium?.copyWith(
                fontWeight: FontWeight.w900,
                color: balance.hasBalance ? context.tokens.warning : null,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _actions(
    BuildContext context,
    CustomerBalance balance,
    bool canReceive,
  ) {
    final session = ref.watch(activeSessionProvider)!;
    final customer = balance.customer;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        if (session.can(Permissions.posView) && customer.isActive)
          OutlinedButton.icon(
            onPressed: _newSale,
            icon: const Icon(Icons.add_shopping_cart_rounded),
            label: const Text('New sale'),
          ),
        if (session.can(Permissions.customerStatement))
          OutlinedButton.icon(
            onPressed: () => _statement(print: true),
            icon: const Icon(Icons.print_outlined),
            label: const Text('Statement'),
          ),
        if (session.can(Permissions.customersEdit))
          OutlinedButton.icon(
            onPressed: _edit,
            icon: const Icon(Icons.edit_outlined),
            label: const Text('Edit'),
          ),
        if (canReceive)
          FilledButton.icon(
            onPressed: balance.hasBalance ? _receivePayment : null,
            icon: const Icon(Icons.price_check_rounded),
            label: const Text('Receive payment'),
          ),
      ],
    );
  }

  Widget _stats(
    BuildContext context,
    CustomerBalance balance,
    MoneyFormatter money,
  ) => LayoutBuilder(
    builder: (context, constraints) {
      final width = (constraints.maxWidth - 36) / 4;
      return Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          SizedBox(
            width: width,
            child: StatCard(
              label: 'Outstanding',
              value: money.format(balance.outstanding),
              icon: Icons.account_balance_wallet_outlined,
              color: balance.hasBalance
                  ? context.tokens.warning
                  : context.tokens.success,
              footnote: balance.overdue.minorUnits > 0
                  ? '${money.format(balance.overdue)} overdue'
                  : '${balance.openInvoices} open invoice(s)',
            ),
          ),
          SizedBox(
            width: width,
            child: StatCard(
              label: 'Total purchases',
              value: money.format(balance.totalPurchases),
              icon: Icons.shopping_bag_outlined,
              color: context.colors.primary,
              footnote: 'Net of returns',
            ),
          ),
          SizedBox(
            width: width,
            child: StatCard(
              label: 'Total paid',
              value: money.format(balance.totalPaid),
              icon: Icons.payments_outlined,
              color: context.tokens.success,
              footnote: 'At the till and on account',
            ),
          ),
          SizedBox(
            width: width,
            child: StatCard(
              label: 'Credit limit',
              value: money.format(balance.creditLimit),
              icon: Icons.speed_rounded,
              color: context.tokens.info,
              footnote: balance.creditLimit.minorUnits == 0
                  ? 'Credit needs approval'
                  : '${money.format(balance.availableCredit)} available',
            ),
          ),
        ],
      );
    },
  );

  Widget _overview(
    BuildContext context,
    CustomerBalance balance,
    MoneyFormatter money,
  ) {
    final customer = balance.customer;
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 16),
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 3,
              child: SectionCard(
                title: 'Open invoices',
                subtitle: 'Unpaid balances, oldest first',
                icon: Icons.pending_actions_rounded,
                child: FutureBuilder<List<OpenItem>>(
                  future: _openItems,
                  builder: (context, snapshot) {
                    final open = snapshot.data;
                    if (open == null) {
                      return const LinearProgressIndicator();
                    }
                    if (open.isEmpty) {
                      return const EmptyState(
                        compact: true,
                        icon: Icons.task_alt_rounded,
                        title: 'Nothing outstanding',
                        message: 'All invoices are paid.',
                      );
                    }
                    return Column(
                      children: [
                        for (final item in open.take(10))
                          _OpenItemTile(item: item, money: money),
                      ],
                    );
                  },
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              flex: 2,
              child: SectionCard(
                title: 'Profile',
                icon: Icons.badge_outlined,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _Fact('Phone', customer.phone ?? '—'),
                    _Fact('Email', customer.email ?? '—'),
                    _Fact(
                      'Address',
                      customer.address.isEmpty ? '—' : customer.address,
                    ),
                    _Fact(
                      'Last purchase',
                      balance.lastPurchase == null
                          ? 'No purchases'
                          : _dateTime.format(balance.lastPurchase!),
                    ),
                    _Fact(
                      'Opening balance',
                      money.format(Money.fromMajor(customer.openingBalance)),
                    ),
                    _Fact('Customer since', _date.format(customer.createdAt)),
                    if (customer.notes.isNotEmpty)
                      _Fact('Notes', customer.notes),
                  ],
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _invoiceList(
    BuildContext context,
    MoneyFormatter money,
    bool canEditDue,
  ) => FutureBuilder<List<CustomerInvoice>>(
    future: _invoices,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return EmptyState(
          icon: Icons.error_outline_rounded,
          title: 'Invoices could not be loaded',
          message: friendlyError(snapshot.error!),
        );
      }
      final invoices = snapshot.data;
      if (invoices == null) {
        return const Center(child: CircularProgressIndicator());
      }
      if (invoices.isEmpty) {
        return const EmptyState(
          icon: Icons.receipt_long_outlined,
          title: 'No invoices yet',
          message: 'Sales to this customer appear here.',
        );
      }
      return Card(
        margin: const EdgeInsets.symmetric(vertical: 14),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            const _TableHeader([
              ('Invoice', 3, false),
              ('Date', 2, false),
              ('Total', 2, true),
              ('Paid', 2, true),
              ('Balance', 2, true),
              ('Due', 3, false),
            ]),
            Expanded(
              child: ListView.separated(
                itemCount: invoices.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final invoice = invoices[index];
                  final sale = invoice.sale;
                  final voided = sale.saleStatus == 'voided';
                  return Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          flex: 3,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                sale.invoiceNumber,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              Text(
                                voided
                                    ? 'Voided · ${invoice.storeName}'
                                    : '${PaymentStatus.label(sale.paymentStatus)} · ${invoice.storeName}',
                                style: context.text.bodySmall,
                              ),
                            ],
                          ),
                        ),
                        Expanded(
                          flex: 2,
                          child: Text(_date.format(sale.createdAt)),
                        ),
                        Expanded(
                          flex: 2,
                          child: Text(
                            money.format(invoice.total),
                            textAlign: TextAlign.end,
                            style: TextStyle(
                              decoration: voided
                                  ? TextDecoration.lineThrough
                                  : null,
                            ),
                          ),
                        ),
                        Expanded(
                          flex: 2,
                          child: Text(
                            money.format(invoice.paid),
                            textAlign: TextAlign.end,
                          ),
                        ),
                        Expanded(
                          flex: 2,
                          child: Text(
                            money.format(invoice.outstanding),
                            textAlign: TextAlign.end,
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              color: invoice.outstanding.minorUnits > 0
                                  ? context.tokens.warning
                                  : null,
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          flex: 3,
                          child: Row(
                            children: [
                              if (invoice.dueStatus != null) ...[
                                DueStatusPill(invoice.dueStatus!),
                                const SizedBox(width: 6),
                                Flexible(
                                  child: Text(
                                    sale.dueDate == null
                                        ? 'No date'
                                        : _date.format(sale.dueDate!),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                if (canEditDue)
                                  IconButton(
                                    tooltip: 'Change due date',
                                    visualDensity: VisualDensity.compact,
                                    onPressed: () => _changeDueDate(invoice),
                                    icon: const Icon(
                                      Icons.edit_calendar_outlined,
                                      size: 18,
                                    ),
                                  ),
                              ] else
                                Text(
                                  sale.creditAmount > 0 ? 'Settled' : '—',
                                  style: context.text.bodySmall,
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      );
    },
  );

  Widget _ledgerTab(
    BuildContext context,
    MoneyFormatter money,
    bool canExport,
  ) {
    final stores = ref.watch(_storesProvider).value ?? const [];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 12),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            DateRangeButton(
              value: _range,
              onChanged: (range) => setState(() {
                _range = range;
                _loadLedger();
              }),
            ),
            if (stores.length > 1)
              AppSelect<String?>(
                width: 200,
                label: 'Store',
                items: [
                  const SelectItem(null, 'All stores'),
                  for (final (id, name) in stores) SelectItem(id, name),
                ],
                value: _storeFilter,
                onChanged: (value) => setState(() {
                  _storeFilter = value;
                  _loadLedger();
                }),
              ),
            AppSegmented<LedgerFilter>(
              items: [
                for (final f in LedgerFilter.values) SegmentItem(f, f.label),
              ],
              value: _ledgerFilter,
              onChanged: (value) => setState(() {
                _ledgerFilter = value;
                _loadLedger();
              }),
            ),
            SearchField(
              width: 220,
              hint: 'Invoice, payment or note',
              onChanged: (value) => setState(() {
                _search = value;
                _loadLedger();
              }),
            ),
            if (canExport) ...[
              OutlinedButton.icon(
                onPressed: () => _statement(print: false),
                icon: const Icon(Icons.picture_as_pdf_outlined),
                label: const Text('PDF'),
              ),
              OutlinedButton.icon(
                onPressed: () => _statement(print: true),
                icon: const Icon(Icons.print_outlined),
                label: const Text('Print'),
              ),
            ],
          ],
        ),
        const SizedBox(height: 12),
        Expanded(
          child: FutureBuilder<LedgerPage>(
            future: _ledger,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return EmptyState(
                  icon: Icons.error_outline_rounded,
                  title: 'Ledger could not be loaded',
                  message: friendlyError(snapshot.error!),
                );
              }
              final page = snapshot.data;
              if (page == null) {
                return const Center(child: CircularProgressIndicator());
              }
              return Card(
                margin: const EdgeInsets.only(bottom: 14),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: [
                    const _TableHeader([
                      ('Date', 3, false),
                      ('Type', 3, false),
                      ('Reference', 4, false),
                      ('Debit', 2, true),
                      ('Credit', 2, true),
                      ('Balance', 2, true),
                      ('User', 2, false),
                    ]),
                    _LedgerLine(
                      cells: [
                        '',
                        'Opening balance',
                        _range == null
                            ? 'Start of account'
                            : describeRange(_range),
                        '',
                        '',
                        money.format(page.opening),
                        '',
                      ],
                      bold: true,
                    ),
                    Expanded(
                      child: page.rows.isEmpty
                          ? const EmptyState(
                              compact: true,
                              icon: Icons.inbox_outlined,
                              title: 'No entries for these filters',
                            )
                          : ListView.builder(
                              itemCount: page.rows.length,
                              itemBuilder: (context, index) {
                                final row = page.rows[index];
                                return _LedgerLine(
                                  shaded: index.isOdd,
                                  cells: [
                                    _dateTime.format(row.entry.createdAt),
                                    LedgerType.label(row.entry.type),
                                    [
                                      row.entry.referenceNumber,
                                      if (row.entry.note.isNotEmpty)
                                        row.entry.note,
                                    ].where((s) => s.isNotEmpty).join(' · '),
                                    row.debit.minorUnits == 0
                                        ? ''
                                        : money.format(row.debit),
                                    row.credit.minorUnits == 0
                                        ? ''
                                        : money.format(row.credit),
                                    money.format(row.balance),
                                    row.userName ?? '',
                                  ],
                                );
                              },
                            ),
                    ),
                    _LedgerLine(
                      cells: [
                        '',
                        'Closing balance',
                        '',
                        money.format(page.debit),
                        money.format(page.credit),
                        money.format(page.closing),
                        '',
                      ],
                      bold: true,
                      shaded: true,
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _paymentList(
    BuildContext context,
    MoneyFormatter money,
    bool canReverse,
  ) => FutureBuilder<List<PaymentRecord>>(
    future: _payments,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return EmptyState(
          icon: Icons.error_outline_rounded,
          title: 'Payments could not be loaded',
          message: friendlyError(snapshot.error!),
        );
      }
      final payments = snapshot.data;
      if (payments == null) {
        return const Center(child: CircularProgressIndicator());
      }
      if (payments.isEmpty) {
        return EmptyState(
          icon: Icons.price_check_rounded,
          title: 'No payments received yet',
          message: 'Payments against the account appear here.',
          action: canReverse
              ? FilledButton.icon(
                  onPressed: _receivePayment,
                  icon: const Icon(Icons.price_check_rounded),
                  label: const Text('Receive payment'),
                )
              : null,
        );
      }
      return ListView.separated(
        padding: const EdgeInsets.symmetric(vertical: 14),
        itemCount: payments.length,
        separatorBuilder: (_, _) => const SizedBox(height: 8),
        itemBuilder: (context, index) {
          final record = payments[index];
          final payment = record.payment;
          return Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  IconTile(
                    icon: record.reversed
                        ? Icons.undo_rounded
                        : Icons.price_check_rounded,
                    size: 38,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              payment.number,
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(width: 8),
                            StatusPill(
                              payment.method.toUpperCase(),
                              tone: PillTone.info,
                            ),
                            if (record.reversed) ...[
                              const SizedBox(width: 6),
                              const StatusPill(
                                'Reversed',
                                tone: PillTone.danger,
                                icon: Icons.undo_rounded,
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          [
                            _dateTime.format(payment.createdAt),
                            record.userName,
                            record.storeName,
                            if (payment.reference != null) payment.reference!,
                            if (payment.note.isNotEmpty) payment.note,
                          ].join(' · '),
                          style: context.text.bodySmall,
                        ),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            for (final (label, amount) in record.allocations)
                              Chip(
                                visualDensity: VisualDensity.compact,
                                label: Text('$label · ${money.format(amount)}'),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        money.format(record.amount),
                        style: context.text.titleMedium?.copyWith(
                          fontWeight: FontWeight.w900,
                          decoration: record.reversed
                              ? TextDecoration.lineThrough
                              : null,
                        ),
                      ),
                      if (canReverse && !record.reversed)
                        TextButton.icon(
                          onPressed: () => _reverse(record),
                          icon: const Icon(Icons.undo_rounded, size: 18),
                          label: const Text('Reverse'),
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
  );
}

final _storesProvider = FutureProvider.autoDispose<List<(String, String)>>((
  ref,
) async {
  final stores = await ref.watch(storeRepositoryProvider).watchAll().first;
  return [for (final store in stores) (store.id, store.name)];
});

class _OpenItemTile extends StatelessWidget {
  const _OpenItemTile({required this.item, required this.money});
  final OpenItem item;
  final MoneyFormatter money;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.label,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              Text(
                item.saleId == null
                    ? 'Owed before using StoreFlow'
                    : '${_date.format(item.date)}'
                          '${item.dueDate == null ? ' · no due date' : ' · due ${_date.format(item.dueDate!)}'}',
                style: context.text.bodySmall,
              ),
            ],
          ),
        ),
        if (item.saleId != null) DueStatusPill(item.dueStatus),
        const SizedBox(width: 12),
        SizedBox(
          width: 110,
          child: Text(
            money.format(item.outstanding),
            textAlign: TextAlign.end,
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
        ),
      ],
    ),
  );
}

class _Fact extends StatelessWidget {
  const _Fact(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 120,
          child: Text(
            label,
            style: TextStyle(color: context.colors.onSurfaceVariant),
          ),
        ),
        Expanded(child: Text(value)),
      ],
    ),
  );
}

class _TableHeader extends StatelessWidget {
  const _TableHeader(this.columns);
  final List<(String, int, bool)> columns;

  @override
  Widget build(BuildContext context) => Container(
    color: context.colors.surfaceContainerHigh,
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
    child: Row(
      children: [
        for (final (label, flex, numeric) in columns)
          Expanded(
            flex: flex,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Text(
                label,
                textAlign: numeric ? TextAlign.end : TextAlign.start,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ),
      ],
    ),
  );
}

class _LedgerLine extends StatelessWidget {
  const _LedgerLine({
    required this.cells,
    this.bold = false,
    this.shaded = false,
  });
  final List<String> cells;
  final bool bold;
  final bool shaded;

  static const _flex = [3, 3, 4, 2, 2, 2, 2];
  static const _numeric = [false, false, false, true, true, true, false];

  @override
  Widget build(BuildContext context) => Container(
    color: shaded
        ? context.colors.surfaceContainerLowest.withValues(alpha: 0.6)
        : null,
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    child: Row(
      children: [
        for (var i = 0; i < cells.length; i++)
          Expanded(
            flex: _flex[i],
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Text(
                cells[i],
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: _numeric[i] ? TextAlign.end : TextAlign.start,
                style: TextStyle(
                  fontWeight: bold || i == 5 ? FontWeight.w700 : null,
                ),
              ),
            ),
          ),
      ],
    ),
  );
}
