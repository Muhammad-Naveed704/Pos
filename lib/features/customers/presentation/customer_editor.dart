import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../../settings/data/business_settings_repository.dart';
import '../../../core/ui/ui_kit.dart';
import '../../auth/application/session_controller.dart';
import '../../credit/data/credit_service.dart';
import '../data/customer_repository.dart';

/// Creates or edits a customer. Returns the customer id when saved.
Future<String?> editCustomer(
  BuildContext context,
  WidgetRef ref, {
  Customer? customer,
}) => showDialog<String>(
  context: context,
  builder: (_) => _CustomerEditor(customer: customer),
);

class _CustomerEditor extends ConsumerStatefulWidget {
  const _CustomerEditor({this.customer});
  final Customer? customer;

  @override
  ConsumerState<_CustomerEditor> createState() => _CustomerEditorState();
}

class _CustomerEditorState extends ConsumerState<_CustomerEditor> {
  late final _name = TextEditingController(text: widget.customer?.name ?? '');
  late final _phone = TextEditingController(text: widget.customer?.phone ?? '');
  late final _email = TextEditingController(text: widget.customer?.email ?? '');
  late final _address = TextEditingController(
    text: widget.customer?.address ?? '',
  );
  late final _notes = TextEditingController(text: widget.customer?.notes ?? '');
  late final _credit = TextEditingController(
    text: _number(widget.customer?.creditLimit),
  );
  late final _opening = TextEditingController(
    text: _number(widget.customer?.openingBalance),
  );
  late bool _active = widget.customer?.isActive ?? true;
  bool _busy = false;
  String? _error;

  String _number(double? value) {
    if (value == null || value == 0) return '';
    final text = value == value.roundToDouble()
        ? value.toStringAsFixed(0)
        : value.toString();
    return ref.read(moneyFormatterProvider).decimalSeparator == ','
        ? text.replaceAll('.', ',')
        : text;
  }

  @override
  void dispose() {
    for (final controller in [
      _name,
      _phone,
      _email,
      _address,
      _notes,
      _credit,
      _opening,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final money = ref.read(moneyFormatterProvider);
    final session = ref.read(activeSessionProvider)!;
    if (_name.text.trim().isEmpty) {
      setState(() => _error = 'Enter the customer name.');
      return;
    }
    final customer = widget.customer;
    // Deactivating hides the customer from sale, but an unpaid balance stays
    // on the books and visible in receivables.
    if (customer != null && customer.isActive && !_active) {
      try {
        final balance = await ref
            .read(creditServiceProvider)
            .balance(session, customer.id);
        if (balance.hasBalance && mounted) {
          final proceed = await confirmDialog(
            context,
            title: 'Customer still owes money',
            message:
                '${customer.name} has an outstanding balance of '
                '${money.format(balance.outstanding)}. Deactivating stops new sales; '
                'the balance stays visible and payments can still be received.',
            confirmLabel: 'Deactivate anyway',
            icon: Icons.warning_amber_rounded,
          );
          if (!proceed) return;
        }
      } catch (_) {}
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final id = await ref
          .read(customerRepositoryProvider)
          .save(
            session: session,
            id: customer?.id,
            name: _name.text,
            phone: _phone.text,
            email: _email.text,
            address: _address.text,
            notes: _notes.text,
            loyaltyPoints: customer?.loyaltyPoints ?? 0,
            creditLimit: money.parse(_credit.text) ?? 0,
            openingBalance: money.parse(_opening.text) ?? 0,
            isActive: _active,
          );
      if (mounted) Navigator.pop(context, id);
    } catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = friendlyError(error);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final symbol = ref.watch(moneyFormatterProvider).symbol;
    return AlertDialog(
      title: Text(widget.customer == null ? 'New customer' : 'Edit customer'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _name,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Name'),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _phone,
                      decoration: const InputDecoration(labelText: 'Phone'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _email,
                      decoration: const InputDecoration(labelText: 'Email'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _address,
                decoration: const InputDecoration(labelText: 'Address'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _notes,
                maxLines: 2,
                decoration: const InputDecoration(labelText: 'Notes'),
              ),
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _credit,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: 'Credit limit',
                        prefixText: '$symbol ',
                        helperText: '0 = credit only with manager approval',
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _opening,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: 'Opening balance',
                        prefixText: '$symbol ',
                        helperText: 'Owed before using StoreFlow',
                      ),
                    ),
                  ),
                ],
              ),
              if (widget.customer != null)
                SwitchListTile(
                  value: _active,
                  onChanged: (value) => setState(() => _active = value),
                  title: const Text('Active'),
                ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(_error!, style: TextStyle(color: context.colors.error)),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _busy ? null : _save,
          child: const Text('Save'),
        ),
      ],
    );
  }
}
