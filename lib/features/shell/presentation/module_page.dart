import 'package:flutter/material.dart';

import '../../../core/ui/ui_kit.dart';
import '../../auth/domain/permissions.dart';

enum ModuleGroup {
  sell('Sell'),
  catalog('Catalog'),
  people('People'),
  operations('Operations'),
  admin('Administration');

  const ModuleGroup(this.label);
  final String label;
}

class ModuleDefinition {
  const ModuleDefinition({
    required this.path,
    required this.label,
    required this.icon,
    required this.selectedIcon,
    required this.description,
    required this.group,
    this.permission,
    this.planned = const [],
  });
  final String path;
  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final String description;
  final ModuleGroup group;
  final String? permission;

  /// Non-empty for modules that are not implemented yet.
  final List<String> planned;

  bool get isPlaceholder => planned.isNotEmpty;
}

const moduleDefinitions = <ModuleDefinition>[
  ModuleDefinition(
    path: '/dashboard',
    label: 'Dashboard',
    icon: Icons.space_dashboard_outlined,
    selectedIcon: Icons.space_dashboard_rounded,
    description: 'Today at a glance for the active store.',
    group: ModuleGroup.sell,
  ),
  ModuleDefinition(
    path: '/pos',
    label: 'Point of Sale',
    icon: Icons.point_of_sale_outlined,
    selectedIcon: Icons.point_of_sale_rounded,
    description: 'Scan, bill and take payment.',
    group: ModuleGroup.sell,
    permission: Permissions.posView,
  ),
  ModuleDefinition(
    path: '/history',
    label: 'Sales history',
    icon: Icons.receipt_long_outlined,
    selectedIcon: Icons.receipt_long_rounded,
    description: 'Completed invoices and receipt actions.',
    group: ModuleGroup.sell,
    permission: Permissions.posView,
  ),
  ModuleDefinition(
    path: '/products',
    label: 'Products',
    icon: Icons.inventory_2_outlined,
    selectedIcon: Icons.inventory_2_rounded,
    description: 'Product master, pricing, availability and stock.',
    group: ModuleGroup.catalog,
    permission: Permissions.productsView,
  ),
  ModuleDefinition(
    path: '/categories',
    label: 'Categories',
    icon: Icons.category_outlined,
    selectedIcon: Icons.category_rounded,
    description: 'Reusable parent and child product categories.',
    group: ModuleGroup.catalog,
    permission: Permissions.productsView,
  ),
  ModuleDefinition(
    path: '/inventory',
    label: 'Inventory',
    icon: Icons.warehouse_outlined,
    selectedIcon: Icons.warehouse_rounded,
    description: 'Per-store stock, movements and adjustments.',
    group: ModuleGroup.catalog,
    permission: Permissions.inventoryView,
  ),
  ModuleDefinition(
    path: '/customers',
    label: 'Customers',
    icon: Icons.people_alt_outlined,
    selectedIcon: Icons.people_alt_rounded,
    description: 'Customer profiles, loyalty and purchase history.',
    group: ModuleGroup.people,
    permission: Permissions.customersView,
  ),
  ModuleDefinition(
    path: '/users',
    label: 'Users & roles',
    icon: Icons.manage_accounts_outlined,
    selectedIcon: Icons.manage_accounts_rounded,
    description: 'Local users, roles and permissions.',
    group: ModuleGroup.people,
    permission: Permissions.usersView,
  ),
  ModuleDefinition(
    path: '/purchases',
    label: 'Purchases',
    icon: Icons.local_shipping_outlined,
    selectedIcon: Icons.local_shipping_rounded,
    description: 'Suppliers, purchase receiving and returns.',
    group: ModuleGroup.operations,
    permission: Permissions.purchasesView,
  ),
  ModuleDefinition(
    path: '/cashbook',
    label: 'Cashbook',
    icon: Icons.account_balance_wallet_outlined,
    selectedIcon: Icons.account_balance_wallet_rounded,
    description: 'Cash sessions, pay-ins and pay-outs.',
    group: ModuleGroup.operations,
    permission: Permissions.cashbookManage,
  ),
  ModuleDefinition(
    path: '/reports',
    label: 'Reports',
    icon: Icons.query_stats_outlined,
    selectedIcon: Icons.query_stats_rounded,
    description: 'Sales, profit and stock reporting.',
    group: ModuleGroup.operations,
    permission: Permissions.reportsView,
    planned: [
      'Sales by day, cashier and category',
      'Profit and margin reports',
      'Export to CSV and PDF',
    ],
  ),
  ModuleDefinition(
    path: '/stores',
    label: 'Stores',
    icon: Icons.storefront_outlined,
    selectedIcon: Icons.storefront_rounded,
    description: 'Branches and active store selection.',
    group: ModuleGroup.admin,
    permission: Permissions.settingsManage,
  ),
];

const settingsModule = ModuleDefinition(
  path: '/settings',
  label: 'Settings',
  icon: Icons.settings_outlined,
  selectedIcon: Icons.settings_rounded,
  description: 'Appearance, business, regional and checkout rules.',
  group: ModuleGroup.admin,
);

ModuleDefinition? moduleForPath(String path) {
  if (path == settingsModule.path) return settingsModule;
  for (final module in moduleDefinitions) {
    if (path == module.path || path.startsWith('${module.path}/')) {
      return module;
    }
  }
  return null;
}

/// Placeholder for modules scheduled in a later phase.
class ModulePage extends StatelessWidget {
  const ModulePage({required this.module, super.key});
  final ModuleDefinition module;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(24),
    child: Card(
      child: EmptyState(
        icon: module.selectedIcon,
        title: '${module.label} is coming in a later release',
        message: module.description,
        action: Column(
          children: [
            for (final item in module.planned)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.schedule_rounded,
                      size: 16,
                      color: context.colors.primary,
                    ),
                    const SizedBox(width: 8),
                    Text(item),
                  ],
                ),
              ),
          ],
        ),
      ),
    ).entrance(context),
  );
}
