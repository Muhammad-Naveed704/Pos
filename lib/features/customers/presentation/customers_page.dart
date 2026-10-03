import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

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
  @override
  Widget build(BuildContext context) {
    final repository = ref.watch(customerRepositoryProvider);
    final balances = ref.watch(customerBalancesProvider).value ?? const {};
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PageHeader(
            title: 'Customers',
            subtitle: 'Profiles, loyalty and purchase summaries.',
            actions: [
              DataMenu(
                canImport: ref
                    .watch(activeSessionProvider)!
                    .can(Permissions.customersCreate),
                onImport: () => _import(context),
                onTemplate: () => saveCsvFile(
                  CustomerImportService.template(),
                  fileName: 'storeflow-customers-template.csv',
                ),
                onExport: () => _export(context),
              ),
              if (ref
                  .watch(activeSessionProvider)!
                  .can(Permissions.customersCreate))
                FilledButton.icon(
                  onPressed: () => _edit(context),
                  icon: const Icon(Icons.person_add_alt_1_rounded),
                  label: const Text('New customer'),
                ),
            ],
          ),
          const SizedBox(height: 16),
          TextField(
            onChanged: (value) => setState(() => _search = value),
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: 'Search name or phone',
            ),
          ),
          const SizedBox(height: 14),
          Expanded(
            child: Card(
              child: CachedStreamBuilder<List<Customer>>(
                keys: [_search],
                create: () => repository.watchAll(search: _search),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final customers = snapshot.data!;
                  if (customers.isEmpty) {
                    return const Center(child: Text('No customers found.'));
                  }
                  return ListView.separated(
                    itemCount: customers.length,
                    separatorBuilder: (_, _) => const Divider(),
                    itemBuilder: (context, index) {
                      final customer = customers[index];
                      final owes = balances[customer.id] ?? 0;
                      return ListTile(
                        onTap: () => context.go('/customers/${customer.id}'),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 6,
                        ),
                        leading: CircleAvatar(
                          child: Text(
                            customer.name.characters.first.toUpperCase(),
                          ),
                        ),
                        title: Text(
                          customer.name,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        subtitle: Text(
                          [
                                customer.phone,
                                customer.email,
                                '${customer.loyaltyPoints} points',
                              ]
                              .whereType<String>()
                              .where((value) => value.isNotEmpty)
                              .join(' · '),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (owes > 0.004) ...[
                              StatusPill(
                                'Owes ${ref.watch(moneyFormatterProvider).major(owes)}',
                                tone: PillTone.warning,
                                icon: Icons.account_balance_wallet_outlined,
                              ),
                              const SizedBox(width: 8),
                            ],
                            Chip(
                              label: Text(
                                customer.isActive ? 'Active' : 'Inactive',
                              ),
                            ),
                            IconButton(
                              onPressed: () => _showSummary(context, customer),
                              tooltip: 'Purchase summary',
                              icon: const Icon(Icons.receipt_long_outlined),
                            ),
                            IconButton(
                              onPressed: () =>
                                  _edit(context, customer: customer),
                              icon: const Icon(Icons.edit_outlined),
                            ),
                          ],
                        ),
                      );
                    },
                  );
                },
              ),
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
