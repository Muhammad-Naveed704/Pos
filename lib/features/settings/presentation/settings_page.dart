import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/theme_controller.dart';
import '../../../core/theme/theme_settings.dart';

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(themeControllerProvider);
    final controller = ref.read(themeControllerProvider.notifier);
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text('Settings', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 5),
        Text(
          'Personalize StoreFlow. Business-wide configuration will be stored in the local database.',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 20),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.palette_outlined,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(width: 10),
                    Text(
                      'Appearance',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                _SettingRow(
                  title: 'Color mode',
                  subtitle: 'Follow Windows or choose a fixed appearance.',
                  control: SegmentedButton<ThemeMode>(
                    segments: const [
                      ButtonSegment(
                        value: ThemeMode.light,
                        label: Text('Light'),
                        icon: Icon(Icons.light_mode_outlined),
                      ),
                      ButtonSegment(
                        value: ThemeMode.dark,
                        label: Text('Dark'),
                        icon: Icon(Icons.dark_mode_outlined),
                      ),
                      ButtonSegment(
                        value: ThemeMode.system,
                        label: Text('System'),
                        icon: Icon(Icons.computer_outlined),
                      ),
                    ],
                    selected: {settings.mode},
                    onSelectionChanged: (value) =>
                        controller.update(settings.copyWith(mode: value.first)),
                  ),
                ),
                const Divider(),
                _SettingRow(
                  title: 'Accent palette',
                  subtitle:
                      'Applied consistently to controls, focus and selection.',
                  control: Wrap(
                    spacing: 8,
                    children: AccentPalette.values
                        .where((palette) => palette != AccentPalette.custom)
                        .map(
                          (palette) => Tooltip(
                            message: palette.label,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(99),
                              onTap: () => controller.update(
                                settings.copyWith(palette: palette),
                              ),
                              child: Container(
                                width: 31,
                                height: 31,
                                decoration: BoxDecoration(
                                  color: Color(palette.value),
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: settings.palette == palette
                                        ? Theme.of(context)
                                              .colorScheme
                                              .onSurface
                                        : Colors.transparent,
                                    width: 3,
                                  ),
                                ),
                                child: settings.palette == palette
                                    ? const Icon(
                                        Icons.check,
                                        color: Colors.white,
                                        size: 17,
                                      )
                                    : null,
                              ),
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ),
                const Divider(),
                _SettingRow(
                  title: 'Interface density',
                  subtitle:
                      'Compact is optimized for high-volume billing counters.',
                  control: DropdownButton<AppDensity>(
                    value: settings.density,
                    items: AppDensity.values
                        .map(
                          (value) => DropdownMenuItem(
                            value: value,
                            child: Text(value.name),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      if (value != null) {
                        controller.update(settings.copyWith(density: value));
                      }
                    },
                  ),
                ),
                const Divider(),
                _SettingRow(
                  title: 'Font family',
                  subtitle: 'System fonts keep the application fully offline.',
                  control: DropdownButton<String>(
                    value: settings.fontFamily,
                    items: const ['Segoe UI', 'Arial', 'Roboto']
                        .map(
                          (value) => DropdownMenuItem(
                            value: value,
                            child: Text(value),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      if (value != null) {
                        controller.update(settings.copyWith(fontFamily: value));
                      }
                    },
                  ),
                ),
                const Divider(),
                _SettingRow(
                  title: 'Corner radius',
                  subtitle: '${settings.radius.round()} px',
                  control: SizedBox(
                    width: 260,
                    child: Slider(
                      min: 4,
                      max: 20,
                      divisions: 8,
                      value: settings.radius,
                      onChanged: (value) =>
                          controller.update(settings.copyWith(radius: value)),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Card(
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 20,
              vertical: 10,
            ),
            leading: const Icon(Icons.backup_outlined),
            title: const Text('Backup and restore'),
            subtitle: const Text(
              'Manual and scheduled local backups will be configured here.',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {},
          ),
        ),
      ],
    );
  }
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
    padding: const EdgeInsets.symmetric(vertical: 13),
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
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
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
