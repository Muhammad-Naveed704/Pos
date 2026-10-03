import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../features/dashboard/presentation/dashboard_page.dart';
import '../features/cashbook/presentation/cashbook_page.dart';
import '../features/categories/presentation/categories_page.dart';
import '../features/credit/presentation/customer_detail_page.dart';
import '../features/credit/presentation/receivables_page.dart';
import '../features/customers/presentation/customers_page.dart';
import '../features/history/presentation/sales_history_page.dart';
import '../features/inventory/presentation/inventory_page.dart';
import '../features/pos/presentation/pos_page.dart';
import '../features/products/presentation/products_page.dart';
import '../features/purchases/presentation/purchases_page.dart';
import '../features/reports/presentation/reports_page.dart';
import '../features/settings/presentation/settings_page.dart';
import '../features/shell/presentation/app_shell.dart';
import '../features/shell/presentation/module_page.dart';
import '../features/stores/presentation/stores_page.dart';
import '../features/users/presentation/users_page.dart';

/// Root navigator, for dialogs opened from services (printer picker).
final rootNavigatorKey = GlobalKey<NavigatorState>();
final _shellNavigatorKey = GlobalKey<NavigatorState>();

final appRouter = GoRouter(
  navigatorKey: rootNavigatorKey,
  initialLocation: '/dashboard',
  routes: [
    ShellRoute(
      navigatorKey: _shellNavigatorKey,
      builder: (context, state, child) => AppShell(child: child),
      routes: [
        GoRoute(
          path: '/dashboard',
          builder: (context, state) => const DashboardPage(),
        ),
        GoRoute(path: '/pos', builder: (context, state) => const PosPage()),
        GoRoute(
          path: '/products',
          builder: (context, state) => const ProductsPage(),
        ),
        GoRoute(
          path: '/categories',
          builder: (context, state) => const CategoriesPage(),
        ),
        GoRoute(
          path: '/customers',
          builder: (context, state) => const CustomersPage(),
          routes: [
            GoRoute(
              path: ':id',
              builder: (context, state) =>
                  CustomerDetailPage(customerId: state.pathParameters['id']!),
            ),
          ],
        ),
        GoRoute(
          path: '/receivables',
          builder: (context, state) => ReceivablesPage(
            overdueOnly: state.uri.queryParameters['filter'] == 'overdue',
          ),
        ),
        GoRoute(
          path: '/history',
          builder: (context, state) => const SalesHistoryPage(),
        ),
        GoRoute(path: '/users', builder: (context, state) => const UsersPage()),
        GoRoute(
          path: '/inventory',
          builder: (context, state) => const InventoryPage(),
        ),
        GoRoute(
          path: '/purchases',
          builder: (context, state) => const PurchasesPage(),
        ),
        GoRoute(
          path: '/cashbook',
          builder: (context, state) => const CashbookPage(),
        ),
        GoRoute(
          path: '/reports',
          builder: (context, state) => const ReportsPage(),
        ),
        GoRoute(
          path: '/stores',
          builder: (context, state) => const StoresPage(),
        ),
        for (final module in moduleDefinitions.where(
          (module) => module.isPlaceholder,
        ))
          GoRoute(
            path: module.path,
            builder: (context, state) => ModulePage(module: module),
          ),
        GoRoute(
          path: '/settings',
          builder: (context, state) => const SettingsPage(),
        ),
      ],
    ),
  ],
);
