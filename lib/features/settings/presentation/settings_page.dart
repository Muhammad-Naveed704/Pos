import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/money/currency.dart';
import '../../../core/money/money_format.dart';
import '../../../core/theme/theme_controller.dart';
import '../../../core/theme/theme_settings.dart';
import '../../../core/ui/ui_kit.dart';
import '../../auth/application/session_controller.dart';
import '../../auth/domain/permissions.dart';
import '../../pos/domain/pos_cart.dart';
import '../data/business_settings_repository.dart';
import '../domain/business_settings.dart';
import 'receipt_designer.dart';
import 'security_settings.dart';

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final canManage = ref
        .watch(activeSessionProvider)!
        .can(Permissions.settingsManage);
    return DefaultTabController(
      length: canManage ? 5 : 1,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const PageHeader(
              title: 'Settings',
              subtitle: 'Appearance is per computer. Business settings apply to every user and store.',
            ),
            const SizedBox(height: 12),
            TabBar(
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              tabs: [
                const Tab(
                  icon: Icon(Icons.palette_outlined),
                  text: 'Appearance',
                ),
                if (canManage) ...const [
                  Tab(
                    icon: Icon(Icons.public_rounded),
                    text: 'Business & regional',
                  ),
                  Tab(
                    icon: Icon(Icons.point_of_sale_rounded),
                    text: 'Checkout & tax',
                  ),
                  Tab(
                    icon: Icon(Icons.receipt_long_rounded),
                    text: 'Receipt designer',
                  ),
                  Tab(icon: Icon(Icons.security_rounded), text: 'Security'),
                ],
              ],
            ),
            Expanded(
              child: TabBarView(
                children: [
                  const _AppearanceTab(),
                  if (canManage) ...const [
                    _BusinessForm(section: _Section.regional),
                    _BusinessForm(section: _Section.checkout),
                    ReceiptDesigner(),
                    SecuritySettings(),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Appearance
// ---------------------------------------------------------------------------

class _AppearanceTab extends ConsumerWidget {
  const _AppearanceTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(themeControllerProvider);
    final controller = ref.read(themeControllerProvider.notifier);
    void set(ThemeSettings value) => controller.update(value);
    final accent = ref.watch(windowsAccentProvider);
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 20),
      children: [
        SectionCard(
          title: 'Theme',
          subtitle: 'Changes apply instantly and are remembered on this PC.',
          icon: Icons.brightness_6_outlined,
          trailing: TextButton.icon(
            onPressed: controller.reset,
            icon: const Icon(Icons.restart_alt_rounded),
            label: const Text('Reset to defaults'),
          ),
          child: Column(
            children: [
              _SettingRow(
                title: 'Colour mode',
                subtitle: 'Follow Windows or choose a fixed appearance.',
                control: AppSegmented<ThemeMode>(
                  items: const [
                    SegmentItem(
                      ThemeMode.light,
                      'Light',
                      icon: Icons.light_mode_outlined,
                    ),
                    SegmentItem(
                      ThemeMode.dark,
                      'Dark',
                      icon: Icons.dark_mode_outlined,
                    ),
                    SegmentItem(
                      ThemeMode.system,
                      'System',
                      icon: Icons.computer_outlined,
                    ),
                  ],
                  value: settings.mode,
                  onChanged: (value) => set(settings.copyWith(mode: value)),
                ),
              ),
              const Divider(),
              _SettingRow(
                title: 'Colour source',
                subtitle: settings.source == ColorSource.windows
                    ? (accent.value == null
                          ? 'Windows accent is unavailable; using your custom colour.'
                          : 'Using your Windows accent colour.')
                    : 'Pick a preset, your Windows accent, or any colour.',
                control: AppSegmented<ColorSource>(
                  items: const [
                    SegmentItem(
                      ColorSource.preset,
                      'Presets',
                      icon: Icons.auto_awesome_outlined,
                    ),
                    SegmentItem(
                      ColorSource.windows,
                      'Windows',
                      icon: Icons.window_outlined,
                    ),
                    SegmentItem(
                      ColorSource.custom,
                      'Custom',
                      icon: Icons.colorize_outlined,
                    ),
                  ],
                  value: settings.source,
                  onChanged: (value) {
                    if (value == ColorSource.windows) {
                      ref.invalidate(windowsAccentProvider);
                    }
                    set(settings.copyWith(source: value));
                  },
                ),
              ),
              if (settings.source == ColorSource.preset) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    for (final preset in ThemePreset.values)
                      _PresetTile(
                        preset: preset,
                        selected: settings.preset == preset,
                        onTap: () => set(settings.copyWith(preset: preset)),
                      ),
                  ],
                ),
              ],
              if (settings.source == ColorSource.custom) ...[
                const SizedBox(height: 8),
                _CustomColorPicker(
                  value: Color(settings.customSeed),
                  onChanged: (color) =>
                      set(settings.copyWith(customSeed: color.toARGB32())),
                ),
              ],
              const Divider(),
              _SettingRow(
                title: 'Surface tint',
                subtitle:
                    'How much of the theme colour tints backgrounds (${settings.surfaceTint}).',
                control: SizedBox(
                  width: 280,
                  child: Slider(
                    min: 0,
                    max: 30,
                    divisions: 15,
                    value: settings.surfaceTint.toDouble(),
                    label: '${settings.surfaceTint}',
                    onChanged: (value) =>
                        set(settings.copyWith(surfaceTint: value.round())),
                  ),
                ),
              ),
              const Divider(),
              _SettingRow(
                title: 'True black dark mode',
                subtitle: 'Pure black backgrounds for OLED screens.',
                control: Switch(
                  value: settings.pureBlackDark,
                  onChanged: (value) =>
                      set(settings.copyWith(pureBlackDark: value)),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        SectionCard(
          title: 'Layout & text',
          icon: Icons.text_fields_rounded,
          child: Column(
            children: [
              _SettingRow(
                title: 'Font',
                subtitle: 'Windows system fonts keep StoreFlow fully offline.',
                control: SizedBox(
                  width: 260,
                  child: AppSelect<String>(
                    items: [
                      for (final font in systemFonts) SelectItem(font, font),
                    ],
                    value: settings.fontFamily,
                    onChanged: (value) {
                      if (value != null) {
                        set(settings.copyWith(fontFamily: value));
                      }
                    },
                  ),
                ),
              ),
              const Divider(),
              _SettingRow(
                title: 'Text size',
                subtitle:
                    '${(settings.fontScale * 100).round()}% · larger text helps at busy counters.',
                control: SizedBox(
                  width: 280,
                  child: Slider(
                    min: 0.85,
                    max: 1.3,
                    divisions: 9,
                    value: settings.fontScale,
                    label: '${(settings.fontScale * 100).round()}%',
                    onChanged: (value) =>
                        set(settings.copyWith(fontScale: value)),
                  ),
                ),
              ),
              const Divider(),
              _SettingRow(
                title: 'Density',
                subtitle: settings.density.description,
                control: AppSegmented<AppDensity>(
                  items: [
                    for (final density in AppDensity.values)
                      SegmentItem(density, density.label),
                  ],
                  value: settings.density,
                  onChanged: (value) => set(settings.copyWith(density: value)),
                ),
              ),
              const Divider(),
              _SettingRow(
                title: 'Corner radius',
                subtitle: '${settings.radius.round()} px',
                control: SizedBox(
                  width: 280,
                  child: Slider(
                    min: 0,
                    max: 24,
                    divisions: 12,
                    value: settings.radius,
                    label: '${settings.radius.round()}',
                    onChanged: (value) => set(settings.copyWith(radius: value)),
                  ),
                ),
              ),
              const Divider(),
              _SettingRow(
                title: 'Animations',
                subtitle: 'Turn off for slower PCs or reduced motion.',
                control: AppSegmented<AppAnimationLevel>(
                  items: [
                    for (final level in AppAnimationLevel.values)
                      SegmentItem(level, level.label),
                  ],
                  value: settings.animationLevel,
                  onChanged: (value) =>
                      set(settings.copyWith(animationLevel: value)),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        const _ThemePreview(),
      ],
    );
  }
}

class _PresetTile extends StatelessWidget {
  const _PresetTile({
    required this.preset,
    required this.selected,
    required this.onTap,
  });
  final ThemePreset preset;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: preset.label,
    child: InkWell(
      borderRadius: context.tokens.borderRadius,
      onTap: onTap,
      child: AnimatedContainer(
        duration: context.tokens.motion(150),
        width: 132,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          borderRadius: context.tokens.borderRadius,
          border: Border.all(
            width: selected ? 2 : 1,
            color: selected
                ? context.colors.primary
                : context.colors.outlineVariant,
          ),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 30,
              height: 30,
              child: Stack(
                children: [
                  CircleAvatar(radius: 13, backgroundColor: preset.swatch),
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: CircleAvatar(
                      radius: 8,
                      backgroundColor: preset.swatchSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                preset.label,
                maxLines: 2,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _CustomColorPicker extends StatefulWidget {
  const _CustomColorPicker({required this.value, required this.onChanged});
  final Color value;
  final ValueChanged<Color> onChanged;

  @override
  State<_CustomColorPicker> createState() => _CustomColorPickerState();
}

class _CustomColorPickerState extends State<_CustomColorPicker> {
  static const _swatches = [
    0xFF1473E6,
    0xFF2563EB,
    0xFF4F46E5,
    0xFF7C3AED,
    0xFFC026D3,
    0xFFDB2777,
    0xFFE11D48,
    0xFFDC2626,
    0xFFEA580C,
    0xFFD97706,
    0xFF65A30D,
    0xFF16A34A,
    0xFF059669,
    0xFF0D9488,
    0xFF0891B2,
    0xFF475569,
  ];
  late final _hex = TextEditingController(text: _toHex(widget.value));

  static String _toHex(Color color) => color
      .toARGB32()
      .toRadixString(16)
      .padLeft(8, '0')
      .substring(2)
      .toUpperCase();

  @override
  void didUpdateWidget(covariant _CustomColorPicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Only mirror external changes (swatch taps); never overwrite typing.
    final hex = _toHex(widget.value);
    if (oldWidget.value != widget.value && _hex.text.toUpperCase() != hex) {
      _hex.text = hex;
    }
  }

  @override
  void dispose() {
    _hex.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final value in _swatches)
              InkWell(
                customBorder: const CircleBorder(),
                onTap: () => widget.onChanged(Color(value)),
                child: Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: Color(value),
                    shape: BoxShape.circle,
                    border: Border.all(
                      width: 3,
                      color: widget.value.toARGB32() == value
                          ? context.colors.onSurface
                          : Colors.transparent,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
      const SizedBox(width: 16),
      SizedBox(
        width: 150,
        child: TextField(
          controller: _hex,
          maxLength: 6,
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp('[0-9a-fA-F]')),
          ],
          decoration: InputDecoration(
            labelText: 'Hex',
            prefixText: '#',
            counterText: '',
            suffixIcon: Padding(
              padding: const EdgeInsets.all(10),
              child: CircleAvatar(radius: 8, backgroundColor: widget.value),
            ),
          ),
          onChanged: (value) {
            if (value.length == 6) {
              widget.onChanged(Color(int.parse('FF$value', radix: 16)));
            }
          },
        ),
      ),
    ],
  );
}

class _ThemePreview extends StatelessWidget {
  const _ThemePreview();
  @override
  Widget build(BuildContext context) => SectionCard(
    title: 'Preview',
    icon: Icons.visibility_outlined,
    child: Wrap(
      spacing: 12,
      runSpacing: 12,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        FilledButton.icon(
          onPressed: () {},
          icon: const Icon(Icons.payments_rounded),
          label: const Text('Pay'),
        ),
        FilledButton.tonal(onPressed: () {}, child: const Text('Tonal')),
        OutlinedButton(onPressed: () {}, child: const Text('Outlined')),
        TextButton(onPressed: () {}, child: const Text('Text')),
        const StatusPill('Paid', tone: PillTone.success),
        const StatusPill('Low stock', tone: PillTone.warning),
        const StatusPill('Voided', tone: PillTone.danger),
        const StatusPill('Info', tone: PillTone.info),
        const SizedBox(
          width: 220,
          child: TextField(
            decoration: InputDecoration(
              labelText: 'Sample field',
              prefixIcon: Icon(Icons.search_rounded),
            ),
          ),
        ),
        Chip(
          avatar: const Icon(Icons.local_offer_outlined, size: 16),
          label: const Text('Category'),
          backgroundColor: context.colors.secondaryContainer,
        ),
      ],
    ),
  );
}

class _SettingRow extends StatelessWidget {
  const _SettingRow({
    required this.title,
    required this.subtitle,
    required this.control,
  });
  final String title;
  final String subtitle;
  final Widget control;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 12),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 3),
              Text(
                subtitle,
                style: TextStyle(color: context.colors.onSurfaceVariant),
              ),
            ],
          ),
        ),
        const SizedBox(width: 24),
        control,
      ],
    ),
  );
}

// ---------------------------------------------------------------------------
// Business settings (database backed)
// ---------------------------------------------------------------------------

enum _Section { regional, checkout }

class _BusinessForm extends ConsumerStatefulWidget {
  const _BusinessForm({required this.section});
  final _Section section;
  @override
  ConsumerState<_BusinessForm> createState() => _BusinessFormState();
}

class _BusinessFormState extends ConsumerState<_BusinessForm>
    with AutomaticKeepAliveClientMixin {
  BusinessSettings? _saved;
  late BusinessSettings _draft;
  final _name = TextEditingController();
  final _taxLabel = TextEditingController();
  final _taxNumber = TextEditingController();
  final _maxDiscount = TextEditingController();
  final _denominations = TextEditingController();
  bool _saving = false;

  /// Bumped on every load so dropdowns (which only read their initial value)
  /// are rebuilt with the reloaded values.
  int _generation = 0;

  @override
  bool get wantKeepAlive => true;

  @override
  void dispose() {
    for (final controller in [
      _name,
      _taxLabel,
      _taxNumber,
      _maxDiscount,
      _denominations,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  /// Loads values into the form. Called once on first data and after
  /// discard/save — never on ordinary rebuilds, so typing is not overwritten.
  void _load(BusinessSettings value) {
    _generation++;
    _saved = value;
    _draft = value;
    _name.text = value.businessName;
    _taxLabel.text = value.taxLabel;
    _taxNumber.text = value.taxNumber;
    _maxDiscount.text =
        value.maxDiscountPercent == value.maxDiscountPercent.roundToDouble()
        ? value.maxDiscountPercent.toStringAsFixed(0)
        : '${value.maxDiscountPercent}';
    _denominations.text = value.quickCashDenominations.join(', ');
  }

  BusinessSettings _collect() => _draft.copyWith(
    businessName: _name.text,
    taxLabel: _taxLabel.text,
    taxNumber: _taxNumber.text,
    maxDiscountPercent: (parseAmount(_maxDiscount.text) ?? 100)
        .clamp(0, 100)
        .toDouble(),
    quickCashDenominations: _denominations.text
        .split(RegExp(r'[,\s]+'))
        .map(int.tryParse)
        .whereType<int>()
        .where((value) => value > 0)
        .toList(),
  );

  /// Copies only this tab's fields from the form onto [base], so saving one
  /// tab never overwrites values saved from the other tab.
  BusinessSettings _merge(BusinessSettings base) {
    final form = _collect();
    return switch (widget.section) {
      _Section.regional => base.copyWith(
        businessName: form.businessName,
        currencyCode: form.currencyCode,
        numberStyle: form.numberStyle,
        symbolPosition: form.symbolPosition,
        timezone: form.timezone,
      ),
      _Section.checkout => base.copyWith(
        taxMode: form.taxMode,
        taxLabel: form.taxLabel,
        taxNumber: form.taxNumber,
        maxDiscountPercent: form.maxDiscountPercent,
        allowPriceOverride: form.allowPriceOverride,
        allowNegativeStock: form.allowNegativeStock,
        quickCashDenominations: form.quickCashDenominations,
      ),
    };
  }

  bool get _dirty {
    final saved = _saved;
    if (saved == null) return false;
    final a = _merge(saved).toMap();
    final b = saved.toMap();
    return a.keys.any((key) => a[key] != b[key]);
  }

  void _edit(BusinessSettings Function(BusinessSettings) change) =>
      setState(() => _draft = change(_draft));

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final latest = await ref.read(businessSettingsRepositoryProvider).load();
      final value = _merge(latest);
      await ref
          .read(businessSettingsRepositoryProvider)
          .save(ref.read(activeSessionProvider)!, value);
      if (!mounted) return;
      setState(() => _load(value));
      Toast.success(context, 'Settings saved.');
    } catch (error) {
      if (mounted) Toast.error(context, error);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    // Pick up changes saved from the other tab, unless the user is mid-edit.
    ref.listen(businessSettingsProvider, (previous, next) {
      final value = next.value;
      if (value != null && _saved != null && !_dirty && !_saving) {
        setState(() => _load(value));
      }
    });
    final async = ref.watch(businessSettingsProvider);
    if (_saved == null) {
      final value = async.value;
      if (value == null) {
        return async.hasError
            ? EmptyState(
                icon: Icons.error_outline_rounded,
                title: 'Settings could not be loaded',
                message: friendlyError(async.error!),
              )
            : const Center(child: CircularProgressIndicator());
      }
      _load(value);
    }
    final dirty = _dirty;
    return Column(
      children: [
        Expanded(
          child: ListView(
            key: ValueKey(_generation),
            padding: const EdgeInsets.symmetric(vertical: 20),
            children: widget.section == _Section.regional
                ? _regional(context)
                : _checkout(context),
          ),
        ),
        AnimatedSwitcher(
          duration: context.tokens.motion(180),
          child: dirty
              ? Container(
                  key: const ValueKey('dirty'),
                  margin: const EdgeInsets.only(bottom: 16),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: context.colors.inverseSurface,
                    borderRadius: context.tokens.borderRadius,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.edit_note_rounded,
                        color: context.colors.onInverseSurface,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'You have unsaved changes.',
                          style: TextStyle(
                            color: context.colors.onInverseSurface,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: _saving
                            ? null
                            : () => setState(() => _load(_saved!)),
                        child: Text(
                          'Discard',
                          style: TextStyle(
                            color: context.colors.inversePrimary,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      FilledButton.icon(
                        onPressed: _saving ? null : _save,
                        icon: _saving
                            ? const SizedBox.square(
                                dimension: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.save_rounded),
                        label: const Text('Save changes'),
                      ),
                    ],
                  ),
                )
              : const SizedBox.shrink(key: ValueKey('clean')),
        ),
      ],
    );
  }

  Widget _field(
    TextEditingController controller,
    String label, {
    String? helper,
    int maxLines = 1,
    bool numeric = false,
  }) => TextField(
    controller: controller,
    maxLines: maxLines,
    keyboardType: numeric
        ? const TextInputType.numberWithOptions(decimal: true)
        : null,
    decoration: InputDecoration(labelText: label, helperText: helper),
    onChanged: (_) => setState(() {}),
  );

  List<Widget> _regional(BuildContext context) {
    final preview = _draft.formatter;
    return [
      SectionCard(
        title: 'Business',
        icon: Icons.business_rounded,
        child: _field(
          _name,
          'Business name',
          helper: 'Shown in the header and at the top of receipts.',
        ),
      ),
      const SizedBox(height: 16),
      SectionCard(
        title: 'Currency & number format',
        subtitle: 'Used for every price, total and receipt.',
        icon: Icons.currency_exchange_rounded,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: AppSelect<String>(
                    items: [
                      for (final currency in Currencies.all)
                        SelectItem(
                          currency.code,
                          '${currency.code} · ${currency.symbol} · ${currency.name}',
                        ),
                    ],
                    value: _draft.currencyCode,
                    onChanged: (value) =>
                        _edit((draft) => draft.copyWith(currencyCode: value)),
                    label: 'Currency',
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: AppSelect<NumberStyle>(
                    items: [
                      for (final style in NumberStyle.values)
                        SelectItem(
                          style,
                          '${style.label}  ·  ${style.example}',
                        ),
                    ],
                    value: _draft.numberStyle,
                    onChanged: (value) =>
                        _edit((draft) => draft.copyWith(numberStyle: value)),
                    label: 'Number format',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                AppSegmented<SymbolPosition>(
                  items: [
                    SegmentItem(SymbolPosition.before, '${preview.symbol} 100'),
                    SegmentItem(SymbolPosition.after, '100 ${preview.symbol}'),
                  ],
                  value: _draft.symbolPosition,
                  onChanged: (value) =>
                      _edit((draft) => draft.copyWith(symbolPosition: value)),
                ),
                const Spacer(),
                Text(
                  'Preview  ',
                  style: TextStyle(color: context.colors.onSurfaceVariant),
                ),
                StatusPill(preview.major(1234567.5), tone: PillTone.primary),
              ],
            ),
          ],
        ),
      ),
      const SizedBox(height: 16),
      SectionCard(
        title: 'Time zone',
        icon: Icons.schedule_rounded,
        child: Align(
          alignment: Alignment.centerLeft,
          child: SizedBox(
            width: 380,
            child: AppSelect<String>(
              items: [
                for (final zone in commonTimezones) SelectItem(zone, zone),
              ],
              value: commonTimezones.contains(_draft.timezone)
                  ? _draft.timezone
                  : null,
              onChanged: (value) =>
                  _edit((draft) => draft.copyWith(timezone: value)),
              label: 'Business time zone',
            ),
          ),
        ),
      ),
    ];
  }

  List<Widget> _checkout(BuildContext context) => [
    SectionCard(
      title: 'Tax',
      subtitle:
          'Each product carries its own rate; this sets how it is applied.',
      icon: Icons.account_balance_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppSegmented<TaxMode>(
            items: const [
              SegmentItem(
                TaxMode.disabled,
                'No tax',
                icon: Icons.block_rounded,
              ),
              SegmentItem(
                TaxMode.exclusive,
                'Added on top',
                icon: Icons.add_rounded,
              ),
              SegmentItem(
                TaxMode.inclusive,
                'Included in price',
                icon: Icons.price_check_rounded,
              ),
            ],
            value: _draft.taxMode,
            onChanged: (value) =>
                _edit((draft) => draft.copyWith(taxMode: value)),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _field(
                  _taxLabel,
                  'Tax name',
                  helper: 'e.g. GST, VAT, Sales Tax',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _field(
                  _taxNumber,
                  'Tax registration number',
                  helper: 'NTN / VAT / GSTIN, printed on receipts',
                ),
              ),
            ],
          ),
        ],
      ),
    ),
    const SizedBox(height: 16),
    SectionCard(
      title: 'Checkout rules',
      icon: Icons.rule_rounded,
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _field(
                  _maxDiscount,
                  'Maximum manual discount (%)',
                  helper: 'Enforced at the counter and at checkout.',
                  numeric: true,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _field(
                  _denominations,
                  'Quick-cash notes',
                  helper: 'Comma separated, e.g. 100, 500, 1000, 5000',
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Allow price override'),
            subtitle: const Text(
              'Users with the permission may change a line price.',
            ),
            value: _draft.allowPriceOverride,
            onChanged: (value) =>
                _edit((draft) => draft.copyWith(allowPriceOverride: value)),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Allow selling below zero stock'),
            subtitle: const Text(
              'When off, tracked products cannot be sold beyond available stock.',
            ),
            value: _draft.allowNegativeStock,
            onChanged: (value) =>
                _edit((draft) => draft.copyWith(allowNegativeStock: value)),
          ),
        ],
      ),
    ),
  ];
}
