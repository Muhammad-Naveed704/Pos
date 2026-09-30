abstract final class Permissions {
  static const posView = 'pos.view';
  static const posCreateSale = 'pos.create_sale';
  static const posVoidSale = 'pos.void_sale';
  static const posApplyDiscount = 'pos.apply_discount';
  static const posOverridePrice = 'pos.override_price';
  static const posRefund = 'pos.refund';
  static const productsView = 'products.view';
  static const productsCreate = 'products.create';
  static const productsEdit = 'products.edit';
  static const productsDeactivate = 'products.deactivate';
  static const productsImport = 'products.import_csv';
  static const customersView = 'customers.view';
  static const customersCreate = 'customers.create';
  static const customersEdit = 'customers.edit';
  static const inventoryView = 'inventory.view';
  static const inventoryAdjust = 'inventory.adjust_stock';
  static const inventoryTransfer = 'inventory.transfer_stock';
  static const inventoryViewCost = 'inventory.view_cost';
  static const reportsSales = 'reports.sales';
  static const reportsProfit = 'reports.profit';
  static const reportsCash = 'reports.cash';
  static const usersManage = 'users.manage';
  static const usersView = 'users.view';
  static const reportsView = 'reports.view';
  static const settingsManage = 'settings.manage';
  static const settingsTheme = 'settings.theme';
  static const settingsStores = 'settings.stores';
  static const settingsBackup = 'settings.backup_restore';
  static const purchasesView = 'purchases.view';
  static const purchasesManage = 'purchases.manage';
  static const cashbookView = 'cashbook.view';
  static const cashbookManage = 'cashbook.manage';
  static const reportsExport = 'reports.export';

  /// Bump when permissions are added; `PermissionUpgrade` then grants the new
  /// ones to the built-in roles that include them by default.
  static const version = 2;

  /// Permissions introduced after the first release, by version.
  static const introduced = <int, Set<String>>{
    2: {
      purchasesView,
      purchasesManage,
      cashbookView,
      cashbookManage,
      reportsExport,
    },
  };

  static const all = <String>{
    posView,
    posCreateSale,
    posVoidSale,
    posApplyDiscount,
    posOverridePrice,
    posRefund,
    productsView,
    productsCreate,
    productsEdit,
    productsDeactivate,
    productsImport,
    customersView,
    customersCreate,
    customersEdit,
    inventoryView,
    inventoryAdjust,
    inventoryTransfer,
    inventoryViewCost,
    reportsSales,
    reportsProfit,
    reportsCash,
    usersManage,
    usersView,
    reportsView,
    settingsManage,
    settingsTheme,
    settingsStores,
    settingsBackup,
    purchasesView,
    purchasesManage,
    cashbookView,
    cashbookManage,
    reportsExport,
  };

  static const cashier = <String>{
    posView,
    posCreateSale,
    customersView,
    customersCreate,
    productsView,
    cashbookManage,
  };

  static const inventoryStaff = <String>{
    productsView,
    productsCreate,
    productsEdit,
    inventoryView,
    inventoryAdjust,
    inventoryTransfer,
    inventoryViewCost,
    purchasesView,
    purchasesManage,
  };

  static const manager = <String>{
    ...cashier,
    posApplyDiscount,
    posOverridePrice,
    posVoidSale,
    productsCreate,
    productsEdit,
    productsDeactivate,
    customersEdit,
    inventoryView,
    inventoryAdjust,
    reportsView,
    reportsSales,
    reportsProfit,
    reportsCash,
    usersView,
    purchasesView,
    purchasesManage,
    cashbookView,
    reportsExport,
    inventoryTransfer,
    inventoryViewCost,
  };

  static const admin = <String>{
    ...manager,
    posRefund,
    productsImport,
    usersManage,
    settingsManage,
    settingsTheme,
    settingsStores,
    settingsBackup,
  };
}

/// Human-readable description of one permission.
class PermissionInfo {
  const PermissionInfo(this.key, this.group, this.label, this.description);
  final String key;
  final String group;
  final String label;
  final String description;
}

abstract final class PermissionCatalog {
  static const groups = [
    'Point of sale',
    'Products',
    'Customers',
    'Inventory',
    'Purchases',
    'Cashbook',
    'Reports',
    'Users',
    'Settings',
  ];

  static const items = <PermissionInfo>[
    PermissionInfo(
      Permissions.posView,
      'Point of sale',
      'Open POS',
      'Use the checkout screen and view sales history.',
    ),
    PermissionInfo(
      Permissions.posCreateSale,
      'Point of sale',
      'Complete sales',
      'Take payment and finish sales.',
    ),
    PermissionInfo(
      Permissions.posApplyDiscount,
      'Point of sale',
      'Give discounts',
      'Apply line and sale discounts (within the maximum).',
    ),
    PermissionInfo(
      Permissions.posOverridePrice,
      'Point of sale',
      'Change prices',
      'Override a product price in the cart.',
    ),
    PermissionInfo(
      Permissions.posVoidSale,
      'Point of sale',
      'Void sales',
      'Cancel a completed sale.',
    ),
    PermissionInfo(
      Permissions.posRefund,
      'Point of sale',
      'Refunds',
      'Refund completed sales.',
    ),
    PermissionInfo(
      Permissions.productsView,
      'Products',
      'View products',
      'See the catalog and prices.',
    ),
    PermissionInfo(
      Permissions.productsCreate,
      'Products',
      'Create products',
      'Add products and categories.',
    ),
    PermissionInfo(
      Permissions.productsEdit,
      'Products',
      'Edit products',
      'Change product details and prices.',
    ),
    PermissionInfo(
      Permissions.productsDeactivate,
      'Products',
      'Deactivate products',
      'Hide products from sale.',
    ),
    PermissionInfo(
      Permissions.productsImport,
      'Products',
      'Import products',
      'Bulk import products from CSV.',
    ),
    PermissionInfo(
      Permissions.customersView,
      'Customers',
      'View customers',
      'See customer profiles and history.',
    ),
    PermissionInfo(
      Permissions.customersCreate,
      'Customers',
      'Create customers',
      'Add customers, including CSV import.',
    ),
    PermissionInfo(
      Permissions.customersEdit,
      'Customers',
      'Edit customers',
      'Change customer details.',
    ),
    PermissionInfo(
      Permissions.inventoryView,
      'Inventory',
      'View inventory',
      'See stock levels and movements.',
    ),
    PermissionInfo(
      Permissions.inventoryAdjust,
      'Inventory',
      'Adjust stock',
      'Correct stock counts with a reason.',
    ),
    PermissionInfo(
      Permissions.inventoryTransfer,
      'Inventory',
      'Transfer stock',
      'Move stock between stores.',
    ),
    PermissionInfo(
      Permissions.inventoryViewCost,
      'Inventory',
      'See cost prices',
      'View cost prices and stock value.',
    ),
    PermissionInfo(
      Permissions.purchasesView,
      'Purchases',
      'View purchases',
      'See suppliers and purchase history.',
    ),
    PermissionInfo(
      Permissions.purchasesManage,
      'Purchases',
      'Manage purchases',
      'Receive stock, return to suppliers, edit suppliers.',
    ),
    PermissionInfo(
      Permissions.cashbookView,
      'Cashbook',
      'View cashbook',
      'See all cash sessions and entries.',
    ),
    PermissionInfo(
      Permissions.cashbookManage,
      'Cashbook',
      'Operate cash drawer',
      'Open/close own session, record pay-ins and pay-outs.',
    ),
    PermissionInfo(
      Permissions.reportsView,
      'Reports',
      'Open reports',
      'Access the reports module.',
    ),
    PermissionInfo(
      Permissions.reportsSales,
      'Reports',
      'Sales reports',
      'Sales by day, product, category and cashier.',
    ),
    PermissionInfo(
      Permissions.reportsProfit,
      'Reports',
      'Profit reports',
      'Gross profit and margins.',
    ),
    PermissionInfo(
      Permissions.reportsCash,
      'Reports',
      'Cash reports',
      'Payment method and cash totals.',
    ),
    PermissionInfo(
      Permissions.reportsExport,
      'Reports',
      'Export reports',
      'Save reports as CSV or PDF.',
    ),
    PermissionInfo(
      Permissions.usersView,
      'Users',
      'View users',
      'See user accounts.',
    ),
    PermissionInfo(
      Permissions.usersManage,
      'Users',
      'Manage users & roles',
      'Create users and roles, change permissions.',
    ),
    PermissionInfo(
      Permissions.settingsManage,
      'Settings',
      'Business settings',
      'Business, tax, receipt and store settings.',
    ),
    PermissionInfo(
      Permissions.settingsTheme,
      'Settings',
      'Appearance',
      'Change theme on this computer.',
    ),
    PermissionInfo(
      Permissions.settingsStores,
      'Settings',
      'Stores',
      'Manage branches.',
    ),
    PermissionInfo(
      Permissions.settingsBackup,
      'Settings',
      'Backup & restore',
      'Create and restore backups.',
    ),
  ];

  static PermissionInfo? of(String key) =>
      items.where((item) => item.key == key).firstOrNull;

  static List<PermissionInfo> inGroup(String group) =>
      items.where((item) => item.group == group).toList();
}
