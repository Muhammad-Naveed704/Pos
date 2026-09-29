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
  };

  static const cashier = <String>{
    posView,
    posCreateSale,
    customersView,
    customersCreate,
    productsView,
  };

  static const inventoryStaff = <String>{
    productsView,
    productsCreate,
    productsEdit,
    inventoryView,
    inventoryAdjust,
    inventoryTransfer,
    inventoryViewCost,
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
