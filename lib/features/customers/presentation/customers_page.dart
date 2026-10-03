import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/ui/ui_kit.dart';
import '../../settings/data/business_settings_repository.dart';
import '../../auth/domain/permissions.dart';

import '../../../core/database/app_database.dart';
import '../../auth/application/session_controller.dart';
import '../../backup/application/backup_providers.dart';
import 'customer_editor.dart';
import '../../../core/ui/import_dialog.dart';
import '../data/customer_import_service.dart';
import '../data/customer_repository.dart';

class CustomersPage extends ConsumerStatefulWidget {
  const CustomersPage({super.key});
  @override
  ConsumerState<CustomersPage> createState() => _CustomersPageState();
}

class _CustomersPageState extends ConsumerState<CustomersPage> {
  Future<void> _import(BuildContext context) async {
    final service = ref.read(customerImportServiceProvider);
    final session = ref.read(activeSessionProvider)!;
    await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => ImportDialog<CustomerImportPlan>(
        title: 'Import customers',
        subject: 'customers',
        templateFileName: 'storeflow-customers-template.csv',
        template: CustomerImportService.template,
        aliases: CustomerImportService.aliases,
        columnsHelp: const [
          ('name', 'Required.'),
          ('phone', 'Optional. Used to match existing customers.'),
          ('email', 'Optional.'),
          ('address', 'Optional.'),
          ('notes', 'Optional.'),
          ('credit_limit', 'Optional amount.'),
          ('opening_balance', 'Optional amount.'),
          ('loyalty_points', 'Optional whole number.'),
          ('active', 'Optional yes/no.'),
        ],
        prepare: (table, update) =>
            service.prepare(session, table, updateExisting: update),
        previewOf: (plan) => plan.preview,
        apply: (plan) async {
          // Safety backup first (if enabled in Data & backup).
          await ref
              .read(backupServiceProvider)
              .beforeRiskyOperation(session, 'customer import');
          return service.apply(session, plan);
        },
      ),
    );
  }

  Future<void> _export(BuildContext context) async {
    try {
      final rows = await ref
          .read(customerImportServiceProvider)
          .export(ref.read(activeSessionProvider)!);
      final path = await saveCsvFile(rows, fileName: 'storeflow-customers.csv');
      if (path != null && context.mounted) {
        Toast.success(context, '${rows.length - 1} customers exported.');
      }
    } catch (error) {
      if (context.mounted) Toast.error(context, error);
    }
  }

  String _search = '';
  bool? _active;
  _CustomerSort _sort = _CustomerSort.name;

  @override
  Widget build(BuildContext context) {
    final repository = ref.watch(customerRepositoryProvider);
    final session = ref.watch(activeSessionProvider)!;
    final money = ref.watch(moneyFormatterProvider);
    final balances = ref.watch(customerBalancesProvider).value ?? const {};
    final stats = ref.watch(customerStatsProvider).value ?? const {};
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PageHeader(
            title: 'Customers',
            subtitle: 'Profiles, loyalty, balances and purchase history.',
            actions: [
              DataMenu(
                canImport: session.can(Permissions.customersCreate),
                onImport: () => _import(context),
                onTemplate: () => saveCsvFile(
                  CustomerImportService.template(),
                  fileName: 'storeflow-customers-template.csv',
                ),
                onExport: () => _export(context),
              ),
              if (session.can(Permissions.customersCreate))
                FilledButton.icon(
                  onPressed: () => _edit(context),
                  icon: const Icon(Icons.person_add_alt_1_rounded),
                  label: const Text('New customer'),
                ),
            ],
          ),
          const SizedBox(height: 16),
          SearchField(
            hint: 'Search customers by name or phone number',
            onChanged: (value) => setState(() => _search = value),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              for (final (value, label, icon) in const [
                (null, 'All customers', Icons.groups_outlined),
                (true, 'Active', Icons.circle),
                (false, 'Inactive', Icons.circle_outlined),
              ])
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    avatar: Icon(
                      icon,
                      size: icon == Icons.groups_outlined ? 18 : 10,
                      color: value == true
                          ? context.tokens.success
                          : value == false
                          ? context.colors.outline
                          : null,
                    ),
                    label: Text(label),
                    selected: _active == value,
                    onSelected: (_) => setState(() => _active = value),
                  ),
                ),
              const Spacer(),
              AppSelect<_CustomerSort>(
                width: 210,
                label: 'Sort by',
                icon: Icons.swap_vert_rounded,
                items: [
                  for (final sort in _CustomerSort.values)
                    SelectItem(sort, sort.label),
                ],
                value: _sort,
                onChanged: (value) =>
                    setState(() => _sort = value ?? _CustomerSort.name),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Expanded(
            child: CachedStreamBuilder<List<Customer>>(
              keys: [_search],
              create: () => repository.watchAll(search: _search),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Card(
                    child: EmptyState(
                      icon: Icons.error_outline_rounded,
                      title: 'Customers could not be loaded',
                      message: friendlyError(snapshot.error!),
                    ),
                  );
                }
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final all = snapshot.data!;
                final customers =
                    all
                        .where((c) => _active == null || c.isActive == _active)
                        .toList()
                      ..sort((a, b) {
                        final sa = stats[a.id], sb = stats[b.id];
                        return switch (_sort) {
                          _CustomerSort.name => a.name.toLowerCase().compareTo(
                            b.name.toLowerCase(),
                          ),
                          _CustomerSort.newest => b.createdAt.compareTo(
                            a.createdAt,
                          ),
                          _CustomerSort.spend => (sb?.total ?? 0).compareTo(
                            sa?.total ?? 0,
                          ),
                          _CustomerSort.recent =>
                            (sb?.lastPurchase ?? DateTime(1970)).compareTo(
                              sa?.lastPurchase ?? DateTime(1970),
                            ),
                          _CustomerSort.balance =>
                            (balances[b.id] ?? 0).compareTo(
                              balances[a.id] ?? 0,
                            ),
                          _CustomerSort.points => b.loyaltyPoints.compareTo(
                            a.loyaltyPoints,
                          ),
                        };
                      });
                return AppTable(
                  columns: const [
                    AppColumn('Customer', flex: 4),
                    AppColumn('Phone number', flex: 3),
                    AppColumn('Loyalty points', flex: 2),
                    AppColumn('Total purchases', flex: 3),
                    AppColumn('Last purchase', flex: 3),
                    AppColumn('Balance', flex: 2, numeric: true),
                    AppColumn('Status', flex: 2),
                    AppColumn('Actions', width: 110, center: true),
                  ],
                  rowCount: customers.length,
                  rowHeight: 70,
                  onTap: (index) =>
                      context.go('/customers/${customers[index].id}'),
                  empty: EmptyState(
                    compact: true,
                    icon: Icons.person_search_rounded,
                    title: all.isEmpty && _search.isEmpty
                        ? 'No customers yet'
                        : 'No customers found',
                    message: all.isEmpty && _search.isEmpty
                        ? 'Add customers to track loyalty and credit.'
                        : 'Try another name or phone number.',
                  ),
                  footer: Text(
                    'Showing ${customers.length} of ${all.length} customers',
                    style: context.text.bodySmall?.copyWith(
                      color: context.colors.onSurfaceVariant,
                    ),
                  ),
                  cells: (context, index) {
                    final customer = customers[index];
                    final stat = stats[customer.id];
                    final owes = balances[customer.id] ?? 0;
                    final muted = context.text.bodySmall?.copyWith(
                      color: context.colors.onSurfaceVariant,
                    );
                    return [
                      Row(
                        children: [
                          NameAvatar(customer.name),
                          const SizedBox(width: 12),
                          Flexible(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  customer.name,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                Text(
                                  customer.email?.isNotEmpty ?? false
                                      ? customer.email!
                                      : 'Since ${DateFormat('MMM y').format(customer.createdAt)}',
                                  overflow: TextOverflow.ellipsis,
                                  style: muted,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      Row(
                        children: [
                          Icon(
                            Icons.call_outlined,
                            size: 16,
                            color: context.colors.onSurfaceVariant,
                          ),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              customer.phone?.isNotEmpty ?? false
                                  ? customer.phone!
                                  : '—',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: StatusPill(
                          '${customer.loyaltyPoints} pts',
                          tone: customer.loyaltyPoints > 0
                              ? PillTone.primary
                              : PillTone.neutral,
                          icon: Icons.workspace_premium_rounded,
                        ),
                      ),
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            money.major(stat?.total ?? 0),
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                          Text(
                            '${stat?.orders ?? 0} order${(stat?.orders ?? 0) == 1 ? '' : 's'}',
                            style: muted,
                          ),
                        ],
                      ),
                      stat?.lastPurchase == null
                          ? Text('No purchases yet', style: muted)
                          : Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  DateFormat('d MMM y')
                                      .format(stat!.lastPurchase!),
                                ),
                                Text(
                                  DateFormat('h:mm a')
                                      .format(stat.lastPurchase!),
                                  style: muted,
                                ),
                              ],
                            ),
                      owes > 0.004
                          ? FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                money.major(owes),
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  color: context.tokens.warning,
                                ),
                              ),
                            )
                          : Text('—', style: muted),
                      customer.isActive
                          ? const StatusPill(
                              'Active',
                              tone: PillTone.success,
                              icon: Icons.circle,
                            )
                          : const StatusPill(
                              'Inactive',
                              tone: PillTone.danger,
                              icon: Icons.circle,
                            ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton.outlined(
                            tooltip: 'Purchase summary',
                            onPressed: () => _showSummary(context, customer),
                            icon: const Icon(
                              Icons.receipt_long_outlined,
                              size: 18,
                            ),
                          ),
                          const SizedBox(width: 6),
                          IconButton.outlined(
                            tooltip: 'Edit',
                            onPressed: () => _edit(context, customer: customer),
                            icon: const Icon(Icons.edit_outlined, size: 18),
                          ),
                        ],
                      ),
                    ];
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showSummary(BuildContext context, Customer customer) async {
    final summary = await ref
        .read(customerRepositoryProvider)
        .summary(customer.id);
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(customer.name),
        content: SizedBox(
          width: 380,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                title: const Text('Total spend'),
                trailing: Text(
                  ref.watch(moneyFormatterProvider).major(summary.totalSpend),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              ListTile(
                title: const Text('Last purchase'),
                trailing: Text(
                  summary.lastPurchase?.toLocal().toString().split('.').first ??
                      'No purchases',
                ),
              ),
              ListTile(
                title: const Text('Loyalty points'),
                trailing: Text('${customer.loyaltyPoints}'),
              ),
            ],
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

  Future<void> _edit(BuildContext context, {Customer? customer}) =>
      editCustomer(context, ref, customer: customer);
}

enum _CustomerSort {
  name('Name (A–Z)'),
  newest('Newest first'),
  spend('Top spenders'),
  recent('Last purchase'),
  balance('Highest balance'),
  points('Most points');

  const _CustomerSort(this.label);
  final String label;
}
