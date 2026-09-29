import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/first_run_service.dart';

class SetupWizard extends ConsumerStatefulWidget {
  const SetupWizard({super.key});

  @override
  ConsumerState<SetupWizard> createState() => _SetupWizardState();
}

class _SetupWizardState extends ConsumerState<SetupWizard> {
  final _business = TextEditingController();
  final _store = TextEditingController();
  final _code = TextEditingController(text: 'MAIN');
  final _address = TextEditingController();
  final _phone = TextEditingController();
  final _owner = TextEditingController();
  final _username = TextEditingController(text: 'owner');
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  final _footer = TextEditingController(text: 'Thank you for your business.');
  int _step = 0;
  String _currency = 'PKR';
  String _timezone = 'Asia/Karachi';
  String _taxMode = 'exclusive';
  bool _busy = false;
  String? _error;

  static const _steps = [
    'Business',
    'Store',
    'Owner',
    'Currency',
    'Tax & receipt',
    'Finish',
  ];

  @override
  void dispose() {
    for (final controller in [
      _business,
      _store,
      _code,
      _address,
      _phone,
      _owner,
      _username,
      _password,
      _confirm,
      _footer,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  String? _validationError() {
    return switch (_step) {
      0 when _business.text.trim().isEmpty => 'Enter your business name.',
      1 when _store.text.trim().isEmpty || _code.text.trim().isEmpty =>
        'Store name and code are required.',
      2 when _owner.text.trim().isEmpty || _username.text.trim().isEmpty =>
        'Owner name and username are required.',
      2 when _password.text.length < 8 =>
        'Password must contain at least 8 characters.',
      2 when _password.text != _confirm.text => 'Passwords do not match.',
      _ => null,
    };
  }

  Future<void> _next() async {
    final validation = _validationError();
    if (validation != null) {
      setState(() => _error = validation);
      return;
    }
    if (_step < _steps.length - 1) {
      setState(() {
        _step += 1;
        _error = null;
      });
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(firstRunServiceProvider)
          .complete(
            FirstRunInput(
              businessName: _business.text,
              storeName: _store.text,
              storeCode: _code.text,
              address: _address.text,
              phone: _phone.text,
              currency: _currency,
              timezone: _timezone,
              ownerName: _owner.text,
              username: _username.text,
              password: _password.text,
              taxMode: _taxMode,
              receiptFooter: _footer.text,
            ),
          );
      ref.invalidate(setupRequiredProvider);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Row(
      children: [
        SizedBox(
          width: 290,
          child: ColoredBox(
            color: Theme.of(context).colorScheme.primary,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(34, 44, 30, 36),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.bolt_rounded, color: Colors.white, size: 42),
                  const SizedBox(height: 16),
                  const Text(
                    'Set up StoreFlow',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 23,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 32),
                  for (var index = 0; index < _steps.length; index++)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 15),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 13,
                            backgroundColor: index <= _step
                                ? Colors.white
                                : Colors.white24,
                            child: Text(
                              '${index + 1}',
                              style: TextStyle(
                                fontSize: 11,
                                color: index <= _step
                                    ? Theme.of(context).colorScheme.primary
                                    : Colors.white,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            _steps[index],
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: index == _step
                                  ? FontWeight.w800
                                  : FontWeight.w400,
                            ),
                          ),
                        ],
                      ),
                    ),
                  const Spacer(),
                  const Text(
                    'All information remains on this PC.',
                    style: TextStyle(color: Colors.white70),
                  ),
                ],
              ),
            ),
          ),
        ),
        Expanded(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(48),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 650),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      _steps[_step],
                      style: Theme.of(context).textTheme.headlineMedium
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _subtitle,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 28),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: _content(),
                      ),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        _error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ],
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        if (_step > 0)
                          OutlinedButton(
                            onPressed: _busy
                                ? null
                                : () => setState(() => _step -= 1),
                            child: const Text('Back'),
                          ),
                        const Spacer(),
                        FilledButton.icon(
                          onPressed: _busy ? null : _next,
                          icon: _busy
                              ? const SizedBox.square(
                                  dimension: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : Icon(
                                  _step == _steps.length - 1
                                      ? Icons.check
                                      : Icons.arrow_forward,
                                ),
                          label: Text(
                            _step == _steps.length - 1
                                ? 'Create StoreFlow workspace'
                                : 'Continue',
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    ),
  );

  String get _subtitle => switch (_step) {
    0 => 'Tell us what should appear across StoreFlow and on receipts.',
    1 => 'Configure the first physical branch or billing location.',
    2 => 'Create the local owner account with full access.',
    3 => 'Choose local financial and time display defaults.',
    4 => 'Set the default tax calculation and receipt footer.',
    _ => 'Review the essentials before the local database is initialized.',
  };

  Widget _content() => switch (_step) {
    0 => _Fields(
      children: [
        TextField(
          controller: _business,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Business name',
            prefixIcon: Icon(Icons.business_outlined),
          ),
        ),
      ],
    ),
    1 => _Fields(
      children: [
        TextField(
          controller: _store,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Store name'),
        ),
        TextField(
          controller: _code,
          decoration: const InputDecoration(
            labelText: 'Store code',
            helperText: 'Used in invoice numbers, for example MAIN-2026-000001',
          ),
        ),
        TextField(
          controller: _address,
          decoration: const InputDecoration(labelText: 'Address'),
          maxLines: 2,
        ),
        TextField(
          controller: _phone,
          decoration: const InputDecoration(labelText: 'Phone'),
        ),
      ],
    ),
    2 => _Fields(
      children: [
        TextField(
          controller: _owner,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Owner name'),
        ),
        TextField(
          controller: _username,
          decoration: const InputDecoration(labelText: 'Username'),
        ),
        TextField(
          controller: _password,
          obscureText: true,
          decoration: const InputDecoration(labelText: 'Password'),
        ),
        TextField(
          controller: _confirm,
          obscureText: true,
          decoration: const InputDecoration(labelText: 'Confirm password'),
        ),
      ],
    ),
    3 => _Fields(
      children: [
        DropdownButtonFormField<String>(
          initialValue: _currency,
          decoration: const InputDecoration(labelText: 'Currency'),
          items: const ['PKR', 'USD', 'GBP', 'EUR', 'AED', 'SAR']
              .map(
                (value) => DropdownMenuItem(value: value, child: Text(value)),
              )
              .toList(),
          onChanged: (value) => setState(() => _currency = value ?? _currency),
        ),
        DropdownButtonFormField<String>(
          initialValue: _timezone,
          decoration: const InputDecoration(labelText: 'Timezone'),
          items:
              const [
                    'Asia/Karachi',
                    'Asia/Dubai',
                    'Asia/Riyadh',
                    'UTC',
                    'Europe/London',
                  ]
                  .map(
                    (value) =>
                        DropdownMenuItem(value: value, child: Text(value)),
                  )
                  .toList(),
          onChanged: (value) => setState(() => _timezone = value ?? _timezone),
        ),
      ],
    ),
    4 => _Fields(
      children: [
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'disabled', label: Text('Disabled')),
            ButtonSegment(value: 'exclusive', label: Text('Exclusive')),
            ButtonSegment(value: 'inclusive', label: Text('Inclusive')),
          ],
          selected: {_taxMode},
          onSelectionChanged: (value) => setState(() => _taxMode = value.first),
        ),
        TextField(
          controller: _footer,
          decoration: const InputDecoration(labelText: 'Receipt footer'),
          maxLines: 2,
        ),
      ],
    ),
    _ => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _ReviewRow('Business', _business.text),
        _ReviewRow('Store', '${_store.text} (${_code.text.toUpperCase()})'),
        _ReviewRow('Owner', '${_owner.text} · ${_username.text.toLowerCase()}'),
        _ReviewRow('Currency', _currency),
        _ReviewRow('Tax', _taxMode),
      ],
    ),
  };
}

class _Fields extends StatelessWidget {
  const _Fields({required this.children});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => Column(
    children: [
      for (var index = 0; index < children.length; index++) ...[
        children[index],
        if (index != children.length - 1) const SizedBox(height: 14),
      ],
    ],
  );
}

class _ReviewRow extends StatelessWidget {
  const _ReviewRow(this.label, this.value);
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 9),
    child: Row(
      children: [
        SizedBox(
          width: 120,
          child: Text(
            label,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
      ],
    ),
  );
}
