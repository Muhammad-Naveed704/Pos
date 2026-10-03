import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart' show Variable;
import 'package:go_router/go_router.dart';

import '../../../core/database/database_provider.dart';
import '../../../core/theme/theme_controller.dart';
import '../../../core/ui/ui_kit.dart';
import '../../auth/application/session_controller.dart';
import '../../auth/domain/app_session.dart';
import '../../auth/domain/permissions.dart';
import '../../backup/application/backup_providers.dart';
import '../../credit/presentation/receivables_card.dart';
import '../../support/presentation/help_support.dart';
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

  Timer? _backupTimer;
  bool _backupRunning = false;

  @override
  void initState() {
    super.initState();
    // Scheduled backups run while someone is signed in: shortly after
    // sign-in, then every 30 minutes the schedule is checked.
    _backupTimer = Timer(const Duration(seconds: 20), () {
      _scheduledBackup();
      _backupTimer = Timer.periodic(
        const Duration(minutes: 30),
        (_) => _scheduledBackup(),
      );
    });
  }

  @override
  void dispose() {
    _backupTimer?.cancel();
    super.dispose();
  }

  Future<void> _scheduledBackup() async {
    final session = ref.read(activeSessionProvider);
    if (_backupRunning || session == null || session.isLocked) return;
    _backupRunning = true;
    try {
      final result = await ref
          .read(backupServiceProvider)
          .runScheduled(session);
      if (result != null && mounted) {
        Toast.success(context, 'Scheduled backup saved and verified.');
      }
    } catch (error) {
      if (mounted) {
        Toast.show(
          context,
          'Scheduled backup failed: ${friendlyError(error)}',
          tone: PillTone.danger,
        );
      }
    } finally {
      _backupRunning = false;
    }
  }

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
        session.can(Permissions.settingsTheme) ||
        session.can(Permissions.backupCreate) ||
        session.can(Permissions.backupRestore);
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
        const SingleActivator(
          LogicalKeyboardKey.keyP,
          control: true,
          shift: true,
        ): () {
          if (session.can(Permissions.creditReceivePayment)) {
            receivePaymentShortcut(context, ref);
          }
        },
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
                session: session,
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
    required this.session,
  });
  final List<ModuleDefinition> destinations;
  final String location;
  final bool collapsed;
  final VoidCallback onToggle;
  final ValueChanged<String> onSelected;
  final bool showSettings;
  final AppSession session;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final width = collapsed ? 78.0 : 244.0;
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
            color: context.colors.outlineVariant.withValues(alpha: 0.45),
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
                height: 72,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    children: [
                      const BrandMark(size: 36),
                      if (!collapsed) ...[
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text.rich(
                            TextSpan(
                              children: [
                                const TextSpan(text: 'StoreFlow '),
                                TextSpan(
                                  text: 'POS',
                                  style: TextStyle(
                                    color: context.colors.primary,
                                  ),
                                ),
                              ],
                            ),
                            maxLines: 1,
                            style: context.text.titleLarge?.copyWith(
                              fontWeight: FontWeight.w900,
                              letterSpacing: -0.4,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(14, 2, 14, 12),
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
                                alpha: 0.75,
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
                    if (showSettings) ...[
                      const SizedBox(height: 10),
                      _NavItem(
                        item: settingsModule,
                        selected: location == settingsModule.path,
                        collapsed: collapsed,
                        onTap: () => onSelected(settingsModule.path),
                      ),
                    ],
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
                child: Column(
                  children: [
                    _StoreCard(session: session, collapsed: collapsed),
                    const SizedBox(height: 6),
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

class _NavItem extends StatefulWidget {
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
  State<_NavItem> createState() => _NavItemState();
}

class _NavItemState extends State<_NavItem> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colors;
    final tokens = context.tokens;
    final selected = widget.selected;
    final foreground = selected ? scheme.onPrimary : scheme.onSurfaceVariant;
    final radius = BorderRadius.circular(tokens.radius + 2);
    final tile = Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: tokens.motion(160),
            height: 44,
            decoration: BoxDecoration(
              borderRadius: radius,
              gradient: selected
                  ? LinearGradient(
                      colors: [
                        scheme.primary,
                        Color.lerp(scheme.primary, scheme.secondary, 0.55)!,
                      ],
                    )
                  : null,
              color: selected
                  ? null
                  : _hover
                  ? scheme.primary.withValues(alpha: 0.07)
                  : Colors.transparent,
              boxShadow: selected
                  ? [
                      BoxShadow(
                        color: scheme.primary.withValues(alpha: 0.28),
                        blurRadius: 14,
                        offset: const Offset(0, 5),
                      ),
                    ]
                  : null,
            ),
            child: Row(
              children: [
                SizedBox(width: widget.collapsed ? 13 : 14),
                SizedBox(
                  width: 24,
                  child: Icon(
                    selected ? widget.item.selectedIcon : widget.item.icon,
                    size: 21,
                    color: selected
                        ? scheme.onPrimary
                        : _hover
                        ? scheme.primary
                        : foreground,
                  ),
                ),
                if (!widget.collapsed) ...[
                  const SizedBox(width: 13),
                  Expanded(
                    child: Text(
                      widget.item.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: selected
                            ? scheme.onPrimary
                            : _hover
                            ? scheme.onSurface
                            : foreground,
                        fontWeight: selected
                            ? FontWeight.w700
                            : FontWeight.w500,
                      ),
                    ),
                  ),
                  if (widget.item.isPlaceholder)
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
    return widget.collapsed
        ? Tooltip(
            message: widget.item.label,
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
        height: 38,
        child: Row(
          children: [
            SizedBox(width: collapsed ? 13 : 14),
            SizedBox(
              width: 24,
              child: Icon(icon, size: 20, color: context.colors.outline),
            ),
            if (!collapsed) ...[
              const SizedBox(width: 13),
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

/// Active store, with a menu to switch between the user's stores.
class _StoreCard extends ConsumerWidget {
  const _StoreCard({required this.session, required this.collapsed});
  final AppSession session;
  final bool collapsed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final business = ref.watch(currentBusinessSettingsProvider).businessName;
    return _StoreMenu(
      session: session,
      builder: (context, open, canSwitch) => Material(
        color: context.theme.cardTheme.color ?? context.colors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(context.tokens.radius + 4),
          side: BorderSide(
            color: context.colors.outlineVariant.withValues(alpha: 0.6),
          ),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(context.tokens.radius + 4),
          onTap: canSwitch ? open : null,
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: collapsed ? 12 : 12,
              vertical: 10,
            ),
            child: Row(
              children: [
                Icon(
                  Icons.storefront_rounded,
                  size: 26,
                  color: context.colors.primary,
                ),
                if (!collapsed) ...[
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          business.isEmpty ? session.store.name : business,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        Text(
                          session.store.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: context.text.bodySmall?.copyWith(
                            color: context.colors.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (canSwitch)
                    Icon(
                      Icons.unfold_more_rounded,
                      size: 18,
                      color: context.colors.onSurfaceVariant,
                    ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TopBar extends ConsumerWidget {
  const _TopBar({required this.location, required this.session});
  final String location;
  final AppSession session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(themeControllerProvider);
    final dark =
        theme.mode == ThemeMode.dark ||
        (theme.mode == ThemeMode.system &&
            MediaQuery.platformBrightnessOf(context) == Brightness.dark);
    return Container(
      height: 68,
      padding: const EdgeInsets.symmetric(horizontal: 22),
      decoration: BoxDecoration(
        color: context.theme.cardTheme.color ?? context.colors.surface,
        border: Border(
          bottom: BorderSide(
            color: context.colors.outlineVariant.withValues(alpha: 0.45),
          ),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: const _GlobalSearch(),
              ),
            ),
          ),
          const SizedBox(width: 16),
          const _OfflineChip(),
          const SizedBox(width: 10),
          _StoreMenu(
            session: session,
            builder: (context, open, canSwitch) => OutlinedButton.icon(
              onPressed: canSwitch ? open : null,
              icon: const Icon(Icons.storefront_rounded, size: 18),
              label: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 150),
                    child: Text(
                      session.store.name,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (canSwitch) ...[
                    const SizedBox(width: 4),
                    const Icon(Icons.expand_more_rounded, size: 18),
                  ],
                ],
              ),
              style: OutlinedButton.styleFrom(
                disabledForegroundColor: context.colors.onSurface,
              ),
            ),
          ),
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
          _Notifications(session: session),
          const SizedBox(width: 8),
          _UserMenu(session: session),
        ],
      ),
    );
  }
}

/// Search box in the top bar: barcodes and SKUs open the product list
/// filtered to that code; F2 still jumps to the POS search.
class _GlobalSearch extends StatefulWidget {
  const _GlobalSearch();
  @override
  State<_GlobalSearch> createState() => _GlobalSearchState();
}

class _GlobalSearchState extends State<_GlobalSearch> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit(String value) {
    final term = value.trim();
    if (term.isEmpty) return;
    _controller.clear();
    context.go(Uri(path: '/products', queryParameters: {'q': term}).toString());
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 44,
    child: TextField(
      controller: _controller,
      onSubmitted: _submit,
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        hintText: 'Search products by name, SKU or barcode…',
        prefixIcon: const Icon(Icons.search_rounded),
        suffixIcon: const Padding(
          padding: EdgeInsets.only(right: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.qr_code_scanner_rounded, size: 20),
              SizedBox(width: 8),
              KeyHint('F2'),
            ],
          ),
        ),
        filled: true,
        fillColor: context.colors.surfaceContainerHighest.withValues(
          alpha: 0.45,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(context.tokens.radius + 4),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(context.tokens.radius + 4),
          borderSide: BorderSide.none,
        ),
      ),
    ),
  );
}

/// StoreFlow never needs a network; this tells users their data is safe
/// locally instead of showing an online/offline state.
class _OfflineChip extends StatelessWidget {
  const _OfflineChip();

  @override
  Widget build(BuildContext context) => Tooltip(
    message: 'All data is stored on this computer. No internet needed.',
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: context.tokens.successContainer,
        borderRadius: BorderRadius.circular(30),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: context.tokens.success,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            'Offline ready',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: context.tokens.success,
            ),
          ),
        ],
      ),
    ),
  );
}

class _StoreMenu extends ConsumerWidget {
  const _StoreMenu({required this.session, required this.builder});
  final AppSession session;
  final Widget Function(BuildContext context, VoidCallback open, bool canSwitch)
  builder;

  @override
  Widget build(BuildContext context, WidgetRef ref) => CachedStreamBuilder(
    create: ref.read(storeRepositoryProvider).watchAll,
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
        builder: (context, controller, _) => builder(
          context,
          () => controller.isOpen ? controller.close() : controller.open(),
          stores.length > 1,
        ),
      );
    },
  );
}

class _Alert {
  const _Alert(this.icon, this.label, this.count, this.route, this.tone);
  final IconData icon;
  final String label;
  final int count;
  final String route;
  final PillTone tone;
}

final _alertsProvider = FutureProvider.autoDispose<List<_Alert>>((ref) async {
  final session = ref.watch(activeSessionProvider);
  if (session == null) return const [];
  final database = ref.watch(databaseProvider);
  final row = await database
      .customSelect(
        '''
        SELECT
          (SELECT COUNT(*) FROM product_stores ps JOIN products p ON p.id = ps.product_id
            WHERE ps.store_id = ?1 AND ps.is_available = 1 AND p.is_active = 1
              AND p.track_inventory = 1 AND ps.stock_qty > 0
              AND ps.stock_qty <= ps.reorder_level) AS low,
          (SELECT COUNT(*) FROM product_stores ps JOIN products p ON p.id = ps.product_id
            WHERE ps.store_id = ?1 AND ps.is_available = 1 AND p.is_active = 1
              AND p.track_inventory = 1 AND ps.stock_qty <= 0) AS out_of_stock,
          (SELECT COUNT(*) FROM sales s WHERE s.credit_amount > 0
            AND s.due_date IS NOT NULL AND s.due_date < ?2
            AND s.payment_status <> 'paid' AND s.sale_status <> 'voided') AS overdue
        ''',
        variables: [
          Variable.withString(session.store.id),
          Variable.withDateTime(
            DateTime(
              DateTime.now().year,
              DateTime.now().month,
              DateTime.now().day,
            ),
          ),
        ],
      )
      .getSingle();
  return [
    if (session.can(Permissions.inventoryView))
      _Alert(
        Icons.warning_amber_rounded,
        'Low stock products',
        row.read<int>('low'),
        '/inventory',
        PillTone.warning,
      ),
    if (session.can(Permissions.inventoryView))
      _Alert(
        Icons.remove_shopping_cart_outlined,
        'Out of stock',
        row.read<int>('out_of_stock'),
        '/inventory',
        PillTone.danger,
      ),
    if (session.can(Permissions.creditView))
      _Alert(
        Icons.event_busy_rounded,
        'Overdue credit invoices',
        row.read<int>('overdue'),
        '/receivables?filter=overdue',
        PillTone.danger,
      ),
  ];
});

class _Notifications extends ConsumerWidget {
  const _Notifications({required this.session});
  final AppSession session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final alerts = ref.watch(_alertsProvider).value ?? const <_Alert>[];
    final active = alerts.where((a) => a.count > 0).toList();
    return MenuAnchor(
      alignmentOffset: const Offset(-240, 6),
      menuChildren: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
          child: Text(
            'Notifications',
            style: context.text.titleSmall?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        if (active.isEmpty)
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: Text('All good — nothing needs attention.'),
          ),
        for (final alert in active)
          MenuItemButton(
            leadingIcon: Icon(alert.icon, size: 18),
            trailingIcon: StatusPill('${alert.count}', tone: alert.tone),
            onPressed: () => context.go(alert.route),
            child: SizedBox(width: 200, child: Text(alert.label)),
          ),
      ],
      builder: (context, controller, _) => IconButton(
        tooltip: 'Notifications',
        onPressed: () {
          ref.invalidate(_alertsProvider);
          controller.isOpen ? controller.close() : controller.open();
        },
        icon: Badge(
          isLabelVisible: active.isNotEmpty,
          label: Text('${active.fold(0, (sum, a) => sum + a.count)}'),
          backgroundColor: context.colors.primary,
          child: const Icon(Icons.notifications_none_rounded),
        ),
      ),
    );
  }
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
      alignmentOffset: const Offset(0, 6),
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
          leadingIcon: const Icon(Icons.settings_outlined, size: 18),
          onPressed: () => context.go('/settings'),
          child: const Text('Settings'),
        ),
        MenuItemButton(
          leadingIcon: const Icon(Icons.support_agent_rounded, size: 18),
          onPressed: () => showHelpDialog(context),
          child: const Text('Help & support'),
        ),
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
      builder: (context, controller, _) => InkWell(
        borderRadius: BorderRadius.circular(context.tokens.radius + 4),
        onTap: () => controller.isOpen ? controller.close() : controller.open(),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircleAvatar(
                radius: 19,
                backgroundColor: context.colors.primaryContainer,
                foregroundColor: context.colors.primary,
                child: Text(
                  initials.isEmpty ? '?' : initials,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 150),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      session.user.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    Text(
                      session.role.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.text.bodySmall?.copyWith(
                        color: context.colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 4),
              Icon(
                Icons.expand_more_rounded,
                color: context.colors.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
