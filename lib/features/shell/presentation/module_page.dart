import 'package:flutter/material.dart';

import '../../auth/domain/permissions.dart';

class ModuleDefinition {
  const ModuleDefinition({
    required this.path,
    required this.label,
    required this.icon,
    required this.description,
    this.permission,
  });
  final String path;
  final String label;
  final IconData icon;
  final String description;
  final String? permission;
}

const moduleDefinitions = <ModuleDefinition>[
  ModuleDefinition(
    path: '/products',
    label: 'Products',
    icon: Icons.inventory_2_outlined,
    description: 'Product master, pricing, availability and stock.',
    permission: Permissions.productsView,
  ),
  ModuleDefinition(
    path: '/categories',
    label: 'Categories',
    icon: Icons.category_outlined,
    description: 'Reusable parent and child product categories.',
    permission: Permissions.productsView,
  ),
  ModuleDefinition(
    path: '/inventory',
    label: 'Inventory',
    icon: Icons.warehouse_outlined,
    description: 'Per-store stock, movements and adjustments.',
    permission: Permissions.inventoryView,
  ),
  ModuleDefinition(
    path: '/customers',
    label: 'Customers',
    icon: Icons.people_alt_outlined,
    description: 'Customer profiles, loyalty and purchase history.',
    permission: Permissions.customersView,
  ),
  ModuleDefinition(
    path: '/purchases',
    label: 'Purchases',
    icon: Icons.local_shipping_outlined,
    description: 'Supplier purchasing is scheduled for Phase 4.',
    permission: Permissions.inventoryView,
  ),
  ModuleDefinition(
    path: '/cashbook',
    label: 'Cashbook',
    icon: Icons.account_balance_wallet_outlined,
    description: 'Cash sessions are scheduled for Phase 4.',
    permission: Permissions.reportsCash,
  ),
  ModuleDefinition(
    path: '/reports',
    label: 'Reports',
    icon: Icons.query_stats_outlined,
    description: 'Advanced reporting is scheduled for Phase 5.',
    permission: Permissions.reportsView,
  ),
  ModuleDefinition(
    path: '/history',
    label: 'Sales history',
    icon: Icons.history_outlined,
    description: 'Completed invoices and receipt actions.',
    permission: Permissions.posView,
  ),
  ModuleDefinition(
    path: '/users',
    label: 'Users',
    icon: Icons.manage_accounts_outlined,
    description: 'Local users, roles and permissions.',
    permission: Permissions.usersView,
  ),
  ModuleDefinition(
    path: '/stores',
    label: 'Stores',
    icon: Icons.storefront_outlined,
    description: 'Branches and active store selection.',
    permission: Permissions.settingsManage,
  ),
];

class ModulePage extends StatelessWidget {
  const ModulePage({required this.module, super.key});
  final ModuleDefinition module;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(24),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(module.label, style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 6),
        Text(
          module.description,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 20),
        Expanded(
          child: Card(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    module.icon,
                    size: 42,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '${module.label} is not part of the current delivery.',
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    ),
  );
}
