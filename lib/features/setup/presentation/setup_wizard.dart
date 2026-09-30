import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/money/currency.dart';
import '../../../core/money/money_format.dart';
import '../../../core/ui/ui_kit.dart';
import '../../settings/domain/business_settings.dart';
import '../../auth/presentation/recovery_dialogs.dart';
import '../data/first_run_service.dart';

class SetupWizard extends ConsumerStatefulWidget {
  const SetupWizard({super.key});

  @override
  ConsumerState<SetupWizard> createState() => _SetupWizardState();
}

class _Step {
  const _Step(this.title, this.subtitle, this.icon);
  final String title;
  final String subtitle;
  final IconData icon;
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
  final _taxLabel = TextEditingController(text: 'Tax');
  final _footer = TextEditingController(text: 'Thank you for your business.');
  int _step = 0;
  String _currency = 'PKR';
  NumberStyle _numberStyle = NumberStyle.international;
  String _timezone = 'Asia/Karachi';
  String _taxMode = 'exclusive';
  bool _obscure = true;
  bool _busy = false;
  String? _error;

  static const _steps = [
    _Step(
      'Business',
      'Tell us what should appear across StoreFlow and on receipts.',
      Icons.business_rounded,
    ),
    _Step(
      'Store',
      'Configure the first branch or billing location.',
      Icons.storefront_rounded,
    ),
    _Step(
      'Owner account',
      'Create the local owner account with full access.',
      Icons.admin_panel_settings_rounded,
    ),
    _Step(
      'Region & currency',
      'Choose how money, numbers and time are shown.',
      Icons.public_rounded,
    ),
    _Step(
      'Tax & receipt',
      'Set the default tax behaviour and receipt footer.',
      Icons.receipt_long_rounded,
    ),
    _Step(
      'Review',
      'Check the essentials before the local database is created.',
      Icons.task_alt_rounded,
    ),
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
      _taxLabel,
      _footer,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  String? _validationError() => switch (_step) {
    0 when _business.text.trim().isEmpty => 'Enter your business name.',
    1 when _store.text.trim().isEmpty || _code.text.trim().isEmpty =>
      'Store name and code are required.',
    1 when !RegExp(r'^[A-Za-z0-9-]{2,12}$').hasMatch(_code.text.trim()) =>
      'Store code must be 2–12 letters, numbers or dashes.',
    2 when _owner.text.trim().isEmpty || _username.text.trim().isEmpty =>
      'Owner name and username are required.',
    2 when !RegExp(r'^[a-zA-Z0-9._-]{3,}$').hasMatch(_username.text.trim()) =>
      'Username must be at least 3 characters (letters, numbers, . _ -).',
    2 when _password.text.length < 8 =>
      'Password must contain at least 8 characters.',
    2 when _password.text != _confirm.text => 'Passwords do not match.',
    _ => null,
  };

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
      final recoveryKey = await ref
          .read(firstRunServiceProvider)
          .complete(
            FirstRunInput(
              businessName: _business.text,
              storeName: _store.text,
              storeCode: _code.text,
              address: _address.text,
              phone: _phone.text,
              currency: _currency,
              numberStyle: _numberStyle.name,
              timezone: _timezone,
              ownerName: _owner.text,
              username: _username.text,
              password: _password.text,
              taxMode: _taxMode,
              taxLabel: _taxLabel.text,
              receiptFooter: _footer.text,
            ),
          );
      if (mounted) await showRecoveryKeyDialog(context, recoveryKey);
      ref.invalidate(setupRequiredProvider);
    } catch (error) {
      if (mounted) setState(() => _error = friendlyError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = context.colors;
    final step = _steps[_step];
    final last = _step == _steps.length - 1;
    return Scaffold(
      body: Row(
        children: [
          Container(
            width: 320,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  scheme.primary,
                  // Darker shade of the same hue keeps white text readable
                  // with every preset (tertiary can be very light).
                  Color.alphaBlend(
                    Colors.black.withValues(alpha: 0.35),
                    scheme.primary,
                  ),
                ],
              ),
            ),
            padding: const EdgeInsets.fromLTRB(34, 44, 30, 36),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const BrandMark(size: 48, onDark: true),
                const SizedBox(height: 18),
                Text(
                  'Set up StoreFlow',
                  style: context.text.headlineSmall?.copyWith(
                    color: scheme.onPrimary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'A few details and you are ready to sell.',
                  style: TextStyle(
                    color: scheme.onPrimary.withValues(alpha: 0.8),
                  ),
                ),
                const SizedBox(height: 32),
                for (var index = 0; index < _steps.length; index++)
                  _StepIndicator(
                    number: index + 1,
                    label: _steps[index].title,
                    done: index < _step,
                    current: index == _step,
                  ),
                const Spacer(),
                Row(
                  children: [
                    Icon(
                      Icons.lock_outline_rounded,
                      size: 16,
                      color: scheme.onPrimary.withValues(alpha: 0.8),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Everything stays on this PC. No account or internet needed.',
                        style: TextStyle(
                          color: scheme.onPrimary.withValues(alpha: 0.8),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(48),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 640),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      LinearProgressIndicator(
                        value: (_step + 1) / _steps.length,
                        borderRadius: BorderRadius.circular(8),
                        minHeight: 6,
                      ),
                      const SizedBox(height: 28),
                      PageHeader(
                        icon: step.icon,
                        title: step.title,
                        subtitle: step.subtitle,
                      ),
                      const SizedBox(height: 24),
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          // A fresh subtree per step, so fields from one step
                          // never inherit the editing state of another.
                          child: KeyedSubtree(
                            key: ValueKey(_step),
                            child: _content().entrance(context, dy: 0.02),
                          ),
                        ),
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 14),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: scheme.errorContainer,
                            borderRadius: context.tokens.borderRadius,
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.error_outline_rounded,
                                color: scheme.onErrorContainer,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  _error!,
                                  style: TextStyle(
                                    color: scheme.onErrorContainer,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 22),
                      Row(
                        children: [
                          if (_step > 0)
                            OutlinedButton.icon(
                              onPressed: _busy
                                  ? null
                                  : () => setState(() {
                                      _step -= 1;
                                      _error = null;
                                    }),
                              icon: const Icon(Icons.arrow_back_rounded),
                              label: const Text('Back'),
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
                                    last
                                        ? Icons.rocket_launch_rounded
                                        : Icons.arrow_forward_rounded,
                                  ),
                            label: Text(
                              last ? 'Create my workspace' : 'Continue',
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
  }

  Widget _text(
    TextEditingController controller,
    String label, {
    IconData? icon,
    String? helper,
    bool autofocus = false,
    bool obscure = false,
    int maxLines = 1,
    Widget? suffix,
  }) => TextField(
    controller: controller,
    autofocus: autofocus,
    obscureText: obscure,
    maxLines: maxLines,
    onSubmitted: maxLines == 1 ? (_) => _next() : null,
    decoration: InputDecoration(
      labelText: label,
      helperText: helper,
      prefixIcon: icon == null ? null : Icon(icon),
      suffixIcon: suffix,
    ),
  );

  Widget _content() {
    final preview = MoneyFormatter(
      currency: Currencies.byCode(_currency),
      style: _numberStyle,
    );
    return switch (_step) {
      0 => _Fields(
        children: [
          _text(
            _business,
            'Business name',
            icon: Icons.business_outlined,
            autofocus: true,
            helper: 'Shown on receipts and across StoreFlow.',
          ),
        ],
      ),
      1 => _Fields(
        children: [
          _text(
            _store,
            'Store name',
            icon: Icons.storefront_outlined,
            autofocus: true,
          ),
          _text(
            _code,
            'Store code',
            icon: Icons.tag_rounded,
            helper: 'Used in invoice numbers, e.g. MAIN-2026-000001',
          ),
          _text(_address, 'Address', icon: Icons.place_outlined, maxLines: 2),
          _text(_phone, 'Phone', icon: Icons.phone_outlined),
        ],
      ),
      2 => _Fields(
        children: [
          _text(
            _owner,
            'Owner full name',
            icon: Icons.person_outline_rounded,
            autofocus: true,
          ),
          _text(_username, 'Username', icon: Icons.alternate_email_rounded),
          _text(
            _password,
            'Password',
            icon: Icons.lock_outline_rounded,
            obscure: _obscure,
            helper: 'At least 8 characters.',
            suffix: IconButton(
              onPressed: () => setState(() => _obscure = !_obscure),
              icon: Icon(
                _obscure
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
              ),
            ),
          ),
          _text(
            _confirm,
            'Confirm password',
            icon: Icons.lock_outline_rounded,
            obscure: _obscure,
          ),
        ],
      ),
      3 => _Fields(
        children: [
          DropdownButtonFormField<String>(
            menuMaxHeight: 360,
            initialValue: _currency,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Currency',
              prefixIcon: Icon(Icons.payments_outlined),
            ),
            items: [
              for (final currency in Currencies.all)
                DropdownMenuItem(
                  value: currency.code,
                  child: Text(
                    '${currency.code} · ${currency.symbol} · ${currency.name}',
                  ),
                ),
            ],
            onChanged: (value) =>
                setState(() => _currency = value ?? _currency),
          ),
          DropdownButtonFormField<NumberStyle>(
            menuMaxHeight: 360,
            initialValue: _numberStyle,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Number format',
              prefixIcon: Icon(Icons.pin_outlined),
            ),
            items: [
              for (final style in NumberStyle.values)
                DropdownMenuItem(
                  value: style,
                  child: Text('${style.label}  ·  ${style.example}'),
                ),
            ],
            onChanged: (value) =>
                setState(() => _numberStyle = value ?? _numberStyle),
          ),
          DropdownButtonFormField<String>(
            menuMaxHeight: 360,
            initialValue: _timezone,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Time zone',
              prefixIcon: Icon(Icons.schedule_rounded),
            ),
            items: [
              for (final zone in commonTimezones)
                DropdownMenuItem(value: zone, child: Text(zone)),
            ],
            onChanged: (value) =>
                setState(() => _timezone = value ?? _timezone),
          ),
          Row(
            children: [
              Text(
                'Prices will look like  ',
                style: TextStyle(color: context.colors.onSurfaceVariant),
              ),
              StatusPill(preview.major(1234567.5), tone: PillTone.primary),
            ],
          ),
        ],
      ),
      4 => _Fields(
        children: [
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'disabled', label: Text('No tax')),
              ButtonSegment(value: 'exclusive', label: Text('Added on top')),
              ButtonSegment(
                value: 'inclusive',
                label: Text('Included in price'),
              ),
            ],
            selected: {_taxMode},
            onSelectionChanged: (value) =>
                setState(() => _taxMode = value.first),
          ),
          _text(
            _taxLabel,
            'Tax name',
            icon: Icons.account_balance_outlined,
            helper: 'e.g. GST, VAT, Sales Tax',
          ),
          _text(
            _footer,
            'Receipt footer',
            icon: Icons.short_text_rounded,
            maxLines: 2,
          ),
        ],
      ),
      _ => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _ReviewRow('Business', _business.text),
          _ReviewRow('Store', '${_store.text} (${_code.text.toUpperCase()})'),
          _ReviewRow(
            'Owner',
            '${_owner.text} · @${_username.text.trim().toLowerCase()}',
          ),
          _ReviewRow(
            'Currency',
            '${Currencies.byCode(_currency).name} · ${preview.major(1234.5)}',
          ),
          _ReviewRow('Time zone', _timezone),
          _ReviewRow('Tax', '${_taxLabel.text} · $_taxMode'),
        ],
      ),
    };
  }
}

class _StepIndicator extends StatelessWidget {
  const _StepIndicator({
    required this.number,
    required this.label,
    required this.done,
    required this.current,
  });
  final int number;
  final String label;
  final bool done;
  final bool current;

  @override
  Widget build(BuildContext context) {
    final onPrimary = context.colors.onPrimary;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        children: [
          AnimatedContainer(
            duration: context.tokens.motion(200),
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: done || current
                  ? onPrimary
                  : onPrimary.withValues(alpha: 0.18),
            ),
            alignment: Alignment.center,
            child: done
                ? Icon(
                    Icons.check_rounded,
                    size: 16,
                    color: context.colors.primary,
                  )
                : Text(
                    '$number',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: current ? context.colors.primary : onPrimary,
                    ),
                  ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: onPrimary.withValues(alpha: current || done ? 1 : 0.75),
                fontWeight: current ? FontWeight.w800 : FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Fields extends StatelessWidget {
  const _Fields({required this.children});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (var index = 0; index < children.length; index++) ...[
        children[index],
        if (index != children.length - 1) const SizedBox(height: 16),
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
            style: TextStyle(color: context.colors.onSurfaceVariant),
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
