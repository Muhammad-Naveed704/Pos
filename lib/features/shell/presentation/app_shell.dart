import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/theme_controller.dart';
import '../../../core/ui/ui_kit.dart';
import '../../auth/application/session_controller.dart';
import '../../auth/domain/app_session.dart';
import '../../auth/domain/permissions.dart';
import '../../settings/data/business_settings_repository.dart';
import '../../stores/data/store_repository.dart';
import 'module_page.dart';

const _collapsedPreference = 'shell.sidebarCollapsed';

class AppShell extends ConsumerStatefulWidget {
  const AppShell({required this.child, super.key});
  final Widget child;

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  late bool _collapsed =
      ref.read(sharedPreferencesProvider).getBool(_collapsedPreference) ??
      false;

  void _toggle() {
    setState(() => _collapsed = !_collapsed);
    ref
        .read(sharedPreferencesProvider)
        .setBool(_collapsedPreference, _collapsed);
  }

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).uri.path;
    final session = ref.watch(activeSessionProvider)!;
    final showSettings =
        session.can(Permissions.settingsManage) ||
        session.can(Permissions.settingsTheme);
    final destinations = moduleDefinitions
        .where(
          (item) => item.permission == null || session.can(item.permission!),
        )
        .toList();
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.f2): () => context.go('/pos'),
        const SingleActivator(LogicalKeyboardKey.keyN, control: true): () =>
            context.go('/pos'),
        const SingleActivator(LogicalKeyboardKey.keyB, control: true): _toggle,
        const SingleActivator(LogicalKeyboardKey.keyL, control: true): () =>
            ref.read(sessionControllerProvider.notifier).lock(),
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          body: Row(
            children: [
              _Sidebar(
                destinations: destinations,
                location: location,
                collapsed: _collapsed,
                onToggle: _toggle,
                onSelected: context.go,
                showSettings: showSettings,
              ),
              Expanded(
                child: Column(
                  children: [
                    _TopBar(location: location, session: session),
                    Expanded(child: widget.child),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({
    required this.destinations,
    required this.location,
    required this.collapsed,
    required this.onToggle,
    required this.onSelected,
    required this.showSettings,
  });
  final List<ModuleDefinition> destinations;
  final String location;
  final bool collapsed;
  final VoidCallback onToggle;
  final ValueChanged<String> onSelected;
  final bool showSettings;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final width = collapsed ? 76.0 : 236.0;
    final groups = <ModuleGroup, List<ModuleDefinition>>{};
    for (final item in destinations) {
      groups.putIfAbsent(item.group, () => []).add(item);
    }
    return AnimatedContainer(
      duration: tokens.motion(200),
      curve: Curves.easeOutCubic,
      width: width,
      decoration: BoxDecoration(
        color: tokens.sidebar,
        border: Border(
          right: BorderSide(
            color: context.colors.outlineVariant.withValues(alpha: 0.5),
          ),
        ),
      ),
      child: ClipRect(
        child: OverflowBox(
          alignment: Alignment.topLeft,
          minWidth: width,
          maxWidth: width,
          child: Column(
            children: [
              SizedBox(
                height: 68,
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: collapsed ? 18 : 18,
                  ),
                  child: Row(
                    children: [
                      const BrandMark(size: 38),
                      if (!collapsed) ...[
                        const SizedBox(width: 11),
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'StoreFlow',
                                style: context.text.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: -0.3,
                                ),
                              ),
                              Text(
                                'POINT OF SALE',
                                style: TextStyle(
                                  fontSize: 9.5,
                                  letterSpacing: 1.4,
                                  fontWeight: FontWeight.w600,
                                  color: context.colors.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                  children: [
                    for (final group in groups.entries) ...[
                      if (!collapsed)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(10, 14, 0, 6),
                          child: Text(
                            group.key.label.toUpperCase(),
                            style: TextStyle(
                              fontSize: 10.5,
                              letterSpacing: 1.1,
                              fontWeight: FontWeight.w700,
                              color: context.colors.onSurfaceVariant.withValues(
                                alpha: 0.8,
                              ),
                            ),
                          ),
                        )
                      else
                        const SizedBox(height: 12),
                      for (final item in group.value)
                        _NavItem(
                          item: item,
                          selected:
                              location == item.path ||
                              location.startsWith('${item.path}/'),
                          collapsed: collapsed,
                          onTap: () => onSelected(item.path),
                        ),
                    ],
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                child: Column(
                  children: [
                    if (showSettings)
                      _NavItem(
                        item: settingsModule,
                        selected: location == settingsModule.path,
                        collapsed: collapsed,
                        onTap: () => onSelected(settingsModule.path),
                      ),
                    _NavButton(
                      icon: collapsed
                          ? Icons.keyboard_double_arrow_right_rounded
                          : Icons.keyboard_double_arrow_left_rounded,
                      label: 'Collapse sidebar',
                      tooltip: collapsed
                          ? 'Expand sidebar (Ctrl+B)'
                          : 'Collapse sidebar (Ctrl+B)',
                      collapsed: collapsed,
                      onTap: onToggle,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.item,
    required this.selected,
    required this.collapsed,
    required this.onTap,
  });
  final ModuleDefinition item;
  final bool selected;
  final bool collapsed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colors;
    final tokens = context.tokens;
    final foreground = selected
        ? scheme.onPrimaryContainer
        : scheme.onSurfaceVariant;
    final tile = Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Material(
        color: selected ? scheme.primaryContainer : Colors.transparent,
        borderRadius: BorderRadius.circular(tokens.radius),
        child: InkWell(
          borderRadius: BorderRadius.circular(tokens.radius),
          onTap: onTap,
          child: SizedBox(
            height: 42,
            child: Row(
              children: [
                AnimatedContainer(
                  duration: tokens.motion(180),
                  width: 3,
                  height: selected ? 20 : 0,
                  margin: const EdgeInsets.only(right: 9),
                  decoration: BoxDecoration(
                    color: scheme.primary,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
                SizedBox(
                  width: collapsed ? 28 : 24,
                  child: Icon(
                    selected ? item.selectedIcon : item.icon,
                    size: 21,
                    color: selected ? scheme.primary : foreground,
                  ),
                ),
                if (!collapsed) ...[
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      item.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: foreground,
                        fontWeight: selected
                            ? FontWeight.w700
                            : FontWeight.w500,
                      ),
                    ),
                  ),
                  if (item.isPlaceholder)
                    Padding(
                      padding: const EdgeInsets.only(right: 10),
                      child: Text(
                        'SOON',
                        style: TextStyle(
                          fontSize: 9,
                          letterSpacing: 0.8,
                          fontWeight: FontWeight.w800,
                          color: scheme.outline,
                        ),
                      ),
                    ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
    return collapsed
        ? Tooltip(
            message: item.label,
            preferBelow: false,
            verticalOffset: 0,
            margin: const EdgeInsets.only(left: 70),
            child: tile,
          )
        : tile;
  }
}

class _NavButton extends StatelessWidget {
  const _NavButton({
    required this.icon,
    required this.label,
    required this.tooltip,
    required this.collapsed,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final String tooltip;
  final bool collapsed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    child: InkWell(
      borderRadius: BorderRadius.circular(context.tokens.radius),
      onTap: onTap,
      child: SizedBox(
        height: 40,
        child: Row(
          children: [
            const SizedBox(width: 12),
            SizedBox(
              width: collapsed ? 28 : 24,
              child: Icon(icon, size: 20, color: context.colors.outline),
            ),
            if (!collapsed) ...[
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: context.colors.outline),
                ),
              ),
            ],
          ],
        ),
      ),
    ),
  );
}

class _TopBar extends ConsumerWidget {
  const _TopBar({required this.location, required this.session});
  final String location;
  final AppSession session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final module = moduleForPath(location);
    final theme = ref.watch(themeControllerProvider);
    final business = ref.watch(currentBusinessSettingsProvider);
    final dark =
        theme.mode == ThemeMode.dark ||
        (theme.mode == ThemeMode.system &&
            MediaQuery.platformBrightnessOf(context) == Brightness.dark);
    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 22),
      decoration: BoxDecoration(
        color: context.colors.surface,
        border: Border(
          bottom: BorderSide(
            color: context.colors.outlineVariant.withValues(alpha: 0.5),
          ),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  module?.label ?? 'StoreFlow',
                  style: context.text.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  business.businessName.isEmpty
                      ? (module?.description ?? '')
                      : '${business.businessName} · ${module?.description ?? ''}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.text.bodySmall?.copyWith(
                    color: context.colors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const _Clock(),
          const SizedBox(width: 14),
          _StoreSwitcher(session: session),
          const SizedBox(width: 6),
          IconButton(
            tooltip: dark ? 'Switch to light mode' : 'Switch to dark mode',
            onPressed: () => ref
                .read(themeControllerProvider.notifier)
                .update(
                  theme.copyWith(mode: dark ? ThemeMode.light : ThemeMode.dark),
                ),
            icon: Icon(
              dark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
            ),
          ),
          IconButton(
            tooltip: 'Lock (Ctrl+L)',
            onPressed: () =>
                ref.read(sessionControllerProvider.notifier).lock(),
            icon: const Icon(Icons.lock_outline_rounded),
          ),
          const SizedBox(width: 6),
          _UserMenu(session: session),
        ],
      ),
    );
  }
}

class _Clock extends StatefulWidget {
  const _Clock();
  @override
  State<_Clock> createState() => _ClockState();
}

class _ClockState extends State<_Clock> {
  late Timer _timer;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 20), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    mainAxisAlignment: MainAxisAlignment.center,
    crossAxisAlignment: CrossAxisAlignment.end,
    children: [
      Text(
        DateFormat('h:mm a').format(_now),
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
      Text(
        DateFormat('EEE, d MMM').format(_now),
        style: context.text.bodySmall?.copyWith(
          color: context.colors.onSurfaceVariant,
        ),
      ),
    ],
  );
}

class _StoreSwitcher extends ConsumerWidget {
  const _StoreSwitcher({required this.session});
  final AppSession session;

  @override
  Widget build(BuildContext context, WidgetRef ref) => StreamBuilder(
    stream: ref.watch(storeRepositoryProvider).watchAll(),
    builder: (context, snapshot) {
      final stores = (snapshot.data ?? const [])
          .where(
            (store) =>
                store.isActive &&
                (session.user.storeId == null ||
                    store.id == session.user.storeId),
          )
          .toList();
      return MenuAnchor(
        alignmentOffset: const Offset(0, 6),
        menuChildren: [
          for (final store in stores)
            MenuItemButton(
              leadingIcon: Icon(
                store.id == session.store.id
                    ? Icons.check_circle_rounded
                    : Icons.storefront_outlined,
                size: 18,
                color: store.id == session.store.id
                    ? context.colors.primary
                    : null,
              ),
              onPressed: store.id == session.store.id
                  ? null
                  : () => ref
                        .read(sessionControllerProvider.notifier)
                        .switchStore(store.id),
              child: Text('${store.name}  ·  ${store.code}'),
            ),
        ],
        builder: (context, controller, _) => OutlinedButton.icon(
          onPressed: stores.length < 2
              ? null
              : () =>
                    controller.isOpen ? controller.close() : controller.open(),
          icon: const Icon(Icons.storefront_rounded, size: 18),
          label: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 160),
                child: Text(
                  session.store.name,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (stores.length > 1) ...[
                const SizedBox(width: 4),
                const Icon(Icons.expand_more_rounded, size: 18),
              ],
            ],
          ),
          style: OutlinedButton.styleFrom(
            disabledForegroundColor: context.colors.onSurface,
          ),
        ),
      );
    },
  );
}

class _UserMenu extends ConsumerWidget {
  const _UserMenu({required this.session});
  final AppSession session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final initials = session.user.displayName
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .take(2)
        .map((part) => part[0].toUpperCase())
        .join();
    return MenuAnchor(
      alignmentOffset: const Offset(-150, 6),
      menuChildren: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                session.user.displayName,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              Text(
                '@${session.user.username} · ${session.role.name}',
                style: context.text.bodySmall?.copyWith(
                  color: context.colors.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        const Divider(),
        MenuItemButton(
          leadingIcon: const Icon(Icons.lock_outline_rounded, size: 18),
          shortcut: const SingleActivator(
            LogicalKeyboardKey.keyL,
            control: true,
          ),
          onPressed: () => ref.read(sessionControllerProvider.notifier).lock(),
          child: const Text('Lock StoreFlow'),
        ),
        MenuItemButton(
          leadingIcon: const Icon(Icons.logout_rounded, size: 18),
          onPressed: () =>
              ref.read(sessionControllerProvider.notifier).logout(),
          child: const Text('Sign out'),
        ),
      ],
      builder: (context, controller, _) => Tooltip(
        message: '${session.user.displayName} · ${session.role.name}',
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: () =>
              controller.isOpen ? controller.close() : controller.open(),
          child: CircleAvatar(
            radius: 18,
            backgroundColor: context.colors.primaryContainer,
            foregroundColor: context.colors.onPrimaryContainer,
            child: Text(
              initials.isEmpty ? '?' : initials,
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
            ),
          ),
        ),
      ),
    );
  }
}
