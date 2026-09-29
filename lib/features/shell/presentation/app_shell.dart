import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../auth/application/session_controller.dart';
import '../../auth/domain/permissions.dart';
import '../../stores/data/store_repository.dart';
import 'module_page.dart';

class AppShell extends ConsumerWidget {
  const AppShell({required this.child, super.key});
  final Widget child;

  static const _primary = <ModuleDefinition>[
    ModuleDefinition(
      path: '/dashboard',
      label: 'Dashboard',
      icon: Icons.space_dashboard_outlined,
      description: '',
    ),
    ModuleDefinition(
      path: '/pos',
      label: 'Point of Sale',
      icon: Icons.point_of_sale_outlined,
      description: '',
      permission: Permissions.posView,
    ),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final location = GoRouterState.of(context).uri.path;
    final session = ref.watch(activeSessionProvider)!;
    final destinations = [..._primary, ...moduleDefinitions]
        .where(
          (item) => item.permission == null || session.can(item.permission!),
        )
        .toList();
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.f2): () => context.go('/pos'),
        const SingleActivator(LogicalKeyboardKey.keyN, control: true): () =>
            context.go('/pos'),
        const SingleActivator(LogicalKeyboardKey.escape): () {
          if (Navigator.of(context).canPop()) Navigator.of(context).pop();
        },
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          body: Row(
            children: [
              _Sidebar(
                destinations: destinations,
                location: location,
                onSelected: context.go,
                showSettings:
                    session.can(Permissions.settingsManage) ||
                    session.can(Permissions.settingsTheme),
              ),
              const VerticalDivider(),
              Expanded(
                child: Column(
                  children: [
                    _TopBar(location: location),
                    const Divider(),
                    Expanded(child: child),
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
    required this.onSelected,
    required this.showSettings,
  });
  final List<ModuleDefinition> destinations;
  final String location;
  final ValueChanged<String> onSelected;
  final bool showSettings;

  @override
  Widget build(BuildContext context) => Material(
    color: Theme.of(context).colorScheme.surface,
    child: SizedBox(
      width: 224,
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
              child: Row(
                children: [
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primary,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const SizedBox(
                      width: 38,
                      height: 38,
                      child: Icon(Icons.bolt_rounded, color: Colors.white),
                    ),
                  ),
                  const SizedBox(width: 11),
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'StoreFlow',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                      Text(
                        'POINT OF SALE',
                        style: TextStyle(fontSize: 9, letterSpacing: 1.1),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                itemCount: destinations.length,
                itemBuilder: (context, index) {
                  final item = destinations[index];
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 3),
                    child: ListTile(
                      dense: true,
                      selected: location == item.path,
                      selectedTileColor: Theme.of(context)
                          .colorScheme
                          .primaryContainer
                          .withValues(alpha: 0.72),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(9),
                      ),
                      leading: Icon(item.icon, size: 20),
                      title: Text(item.label),
                      onTap: () => onSelected(item.path),
                    ),
                  );
                },
              ),
            ),
            if (showSettings)
              Padding(
                padding: const EdgeInsets.all(10),
                child: ListTile(
                  dense: true,
                  selected: location == '/settings',
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(9),
                  ),
                  leading: const Icon(Icons.settings_outlined, size: 20),
                  title: const Text('Settings'),
                  onTap: () => onSelected('/settings'),
                ),
              ),
          ],
        ),
      ),
    ),
  );
}

class _TopBar extends ConsumerWidget {
  const _TopBar({required this.location});
  final String location;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(activeSessionProvider)!;
    final title = location == '/pos'
        ? 'Point of Sale'
        : location
              .split('/')
              .last
              .replaceFirstMapped(
                RegExp(r'^.'),
                (match) => match[0]!.toUpperCase(),
              );
    return SizedBox(
      height: 64,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 22),
        child: Row(
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const Spacer(),
            StreamBuilder(
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
                return DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: session.store.id,
                    borderRadius: BorderRadius.circular(10),
                    items: stores
                        .map(
                          (store) => DropdownMenuItem(
                            value: store.id,
                            child: Row(
                              children: [
                                const Icon(Icons.storefront_outlined, size: 17),
                                const SizedBox(width: 8),
                                Text(store.name),
                              ],
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      if (value != null) {
                        ref
                            .read(sessionControllerProvider.notifier)
                            .switchStore(value);
                      }
                    },
                  ),
                );
              },
            ),
            const SizedBox(width: 12),
            PopupMenuButton<String>(
              tooltip: '${session.user.displayName} · ${session.role.name}',
              onSelected: (value) {
                final controller = ref.read(sessionControllerProvider.notifier);
                if (value == 'lock') controller.lock();
                if (value == 'logout') controller.logout();
              },
              itemBuilder: (context) => [
                PopupMenuItem(
                  enabled: false,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        session.user.displayName,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      Text(session.role.name),
                    ],
                  ),
                ),
                const PopupMenuDivider(),
                const PopupMenuItem(
                  value: 'lock',
                  child: Text('Lock StoreFlow'),
                ),
                const PopupMenuItem(value: 'logout', child: Text('Sign out')),
              ],
              child: const CircleAvatar(
                radius: 18,
                child: Icon(Icons.person_outline, size: 19),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
