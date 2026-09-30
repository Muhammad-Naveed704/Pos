import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/ui/ui_kit.dart';
import '../../settings/data/business_settings_repository.dart';
import '../../auth/domain/permissions.dart';

import '../../../core/database/app_database.dart';
import '../../auth/application/session_controller.dart';
import '../data/customer_repository.dart';

class CustomersPage extends ConsumerStatefulWidget {
  const CustomersPage({super.key});
  @override
  ConsumerState<CustomersPage> createState() => _CustomersPageState();
}

class _CustomersPageState extends ConsumerState<CustomersPage> {
  String _search = '';
  @override
  Widget build(BuildContext context) {
    final repository = ref.watch(customerRepositoryProvider);
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PageHeader(
            title: 'Customers',
            subtitle: 'Profiles, loyalty and purchase summaries.',
            actions: [
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
              child: StreamBuilder<List<Customer>>(
                stream: repository.watchAll(search: _search),
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
                      return ListTile(
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

  Future<void> _edit(BuildContext context, {Customer? customer}) async {
    final name = TextEditingController(text: customer?.name ?? '');
    final phone = TextEditingController(text: customer?.phone ?? '');
    final email = TextEditingController(text: customer?.email ?? '');
    final address = TextEditingController(text: customer?.address ?? '');
    final notes = TextEditingController(text: customer?.notes ?? '');
    final money = ref.read(moneyFormatterProvider);
    String n(double? value) {
      if (value == null || value == 0) return '';
      final text = value == value.roundToDouble()
          ? value.toStringAsFixed(0)
          : value.toString();
      return money.decimalSeparator == ',' ? text.replaceAll('.', ',') : text;
    }

    final credit = TextEditingController(text: n(customer?.creditLimit));
    final opening = TextEditingController(text: n(customer?.openingBalance));
    var active = customer?.isActive ?? true;
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(customer == null ? 'New customer' : 'Edit customer'),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: name,
                    autofocus: true,
                    decoration: const InputDecoration(labelText: 'Name'),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: phone,
                          decoration: const InputDecoration(labelText: 'Phone'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: email,
                          decoration: const InputDecoration(labelText: 'Email'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: address,
                    decoration: const InputDecoration(labelText: 'Address'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: notes,
                    maxLines: 2,
                    decoration: const InputDecoration(labelText: 'Notes'),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: credit,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Credit limit',
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: opening,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Opening balance',
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (customer != null)
                    SwitchListTile(
                      value: active,
                      onChanged: (value) =>
                          setDialogState(() => active = value),
                      title: const Text('Active'),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    if (saved != true) return;
    await ref
        .read(customerRepositoryProvider)
        .save(
          session: ref.read(activeSessionProvider)!,
          id: customer?.id,
          name: name.text,
          phone: phone.text,
          email: email.text,
          address: address.text,
          notes: notes.text,
          loyaltyPoints: customer?.loyaltyPoints ?? 0,
          creditLimit: ref.read(moneyFormatterProvider).parse(credit.text) ?? 0,
          openingBalance:
              ref.read(moneyFormatterProvider).parse(opening.text) ?? 0,
          isActive: active,
        );
  }
}
