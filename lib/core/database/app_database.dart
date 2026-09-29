import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

part 'app_database.g.dart';

class Stores extends Table {
  TextColumn get id => text()();
  TextColumn get name => text().withLength(min: 1, max: 120)();
  TextColumn get code => text().withLength(min: 1, max: 32).unique()();
  TextColumn get address => text().withDefault(const Constant(''))();
  TextColumn get phone => text().withDefault(const Constant(''))();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class Roles extends Table {
  TextColumn get id => text()();
  TextColumn get name => text().withLength(min: 1, max: 80).unique()();
  TextColumn get permissionsJson => text().withDefault(const Constant('[]'))();
  BoolColumn get isSystem => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class Users extends Table {
  TextColumn get id => text()();
  TextColumn get username => text().withLength(min: 1, max: 80).unique()();
  TextColumn get displayName => text().withLength(min: 1, max: 120)();
  TextColumn get passwordHash => text()();
  TextColumn get passwordSalt => text()();
  TextColumn get roleId => text().references(Roles, #id)();
  TextColumn get storeId => text().nullable().references(Stores, #id)();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get lastLoginAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class Categories extends Table {
  TextColumn get id => text()();
  TextColumn get name => text().withLength(min: 1, max: 120)();
  TextColumn get code => text().withLength(min: 1, max: 32).unique()();
  TextColumn get parentId => text().nullable().references(Categories, #id)();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  IntColumn get colorValue => integer().nullable()();
  TextColumn get iconKey => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class Products extends Table {
  TextColumn get id => text()();
  TextColumn get sku => text().withLength(min: 1, max: 80).unique()();
  TextColumn get barcode => text().nullable().unique()();
  TextColumn get name => text().withLength(min: 1, max: 180)();
  TextColumn get shortName => text().nullable()();
  TextColumn get categoryId => text().nullable().references(Categories, #id)();
  RealColumn get costPrice => real().withDefault(const Constant(0))();
  RealColumn get salePrice => real()();
  RealColumn get wholesalePrice => real().nullable()();
  RealColumn get taxRate => real().withDefault(const Constant(0))();
  RealColumn get defaultDiscount => real().withDefault(const Constant(0))();
  TextColumn get unit => text().withDefault(const Constant('each'))();
  TextColumn get imagePath => text().nullable()();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  BoolColumn get trackInventory =>
      boolean().withDefault(const Constant(true))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class ProductStores extends Table {
  TextColumn get productId => text().references(Products, #id)();
  TextColumn get storeId => text().references(Stores, #id)();
  RealColumn get stockQty => real().withDefault(const Constant(0))();
  RealColumn get reorderLevel => real().withDefault(const Constant(0))();
  RealColumn get customSalePrice => real().nullable()();
  RealColumn get customDiscount => real().nullable()();
  BoolColumn get isAvailable => boolean().withDefault(const Constant(true))();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {productId, storeId};
}

class Customers extends Table {
  TextColumn get id => text()();
  TextColumn get name => text().withLength(min: 1, max: 160)();
  TextColumn get phone => text().nullable()();
  TextColumn get email => text().nullable()();
  TextColumn get address => text().withDefault(const Constant(''))();
  TextColumn get notes => text().withDefault(const Constant(''))();
  IntColumn get loyaltyPoints => integer().withDefault(const Constant(0))();
  RealColumn get creditLimit => real().withDefault(const Constant(0))();
  RealColumn get openingBalance => real().withDefault(const Constant(0))();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class Suppliers extends Table {
  TextColumn get id => text()();
  TextColumn get name => text().withLength(min: 1, max: 160)();
  TextColumn get phone => text().nullable()();
  TextColumn get email => text().nullable()();
  TextColumn get address => text().withDefault(const Constant(''))();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class Sales extends Table {
  TextColumn get id => text()();
  TextColumn get invoiceNumber => text().unique()();
  TextColumn get storeId => text().references(Stores, #id)();
  TextColumn get userId => text().references(Users, #id)();
  TextColumn get customerId => text().nullable().references(Customers, #id)();
  RealColumn get subtotal => real()();
  RealColumn get discountAmount => real().withDefault(const Constant(0))();
  RealColumn get taxAmount => real().withDefault(const Constant(0))();
  RealColumn get grandTotal => real()();
  RealColumn get paidAmount => real().withDefault(const Constant(0))();
  RealColumn get changeAmount => real().withDefault(const Constant(0))();
  TextColumn get paymentStatus => text()();
  TextColumn get saleStatus => text()();
  TextColumn get notes => text().withDefault(const Constant(''))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class SaleItems extends Table {
  TextColumn get id => text()();
  TextColumn get saleId => text().references(Sales, #id)();
  TextColumn get productId => text().references(Products, #id)();
  TextColumn get productNameSnapshot => text()();
  TextColumn get skuSnapshot => text()();
  RealColumn get qty => real()();
  RealColumn get unitPrice => real()();
  RealColumn get discountAmount => real().withDefault(const Constant(0))();
  RealColumn get taxAmount => real().withDefault(const Constant(0))();
  RealColumn get lineTotal => real()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class Payments extends Table {
  TextColumn get id => text()();
  TextColumn get saleId => text().references(Sales, #id)();
  TextColumn get method => text()();
  RealColumn get amount => real()();
  TextColumn get reference => text().nullable()();
  TextColumn get receivedBy => text().references(Users, #id)();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class CashSessions extends Table {
  TextColumn get id => text()();
  TextColumn get storeId => text().references(Stores, #id)();
  TextColumn get userId => text().references(Users, #id)();
  RealColumn get openingBalance => real()();
  RealColumn get expectedClosing => real().nullable()();
  RealColumn get actualClosing => real().nullable()();
  TextColumn get status => text()();
  DateTimeColumn get openedAt => dateTime()();
  DateTimeColumn get closedAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class CashTransactions extends Table {
  TextColumn get id => text()();
  TextColumn get storeId => text().references(Stores, #id)();
  TextColumn get userId => text().references(Users, #id)();
  TextColumn get sessionId => text().nullable().references(CashSessions, #id)();
  TextColumn get type => text()();
  TextColumn get category => text()();
  RealColumn get amount => real()();
  TextColumn get description => text().withDefault(const Constant(''))();
  TextColumn get reference => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class Purchases extends Table {
  TextColumn get id => text()();
  TextColumn get storeId => text().references(Stores, #id)();
  TextColumn get supplierId => text().nullable().references(Suppliers, #id)();
  TextColumn get invoiceNumber => text()();
  RealColumn get subtotal => real()();
  RealColumn get discount => real().withDefault(const Constant(0))();
  RealColumn get tax => real().withDefault(const Constant(0))();
  RealColumn get total => real()();
  TextColumn get status => text()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class PurchaseItems extends Table {
  TextColumn get id => text()();
  TextColumn get purchaseId => text().references(Purchases, #id)();
  TextColumn get productId => text().references(Products, #id)();
  RealColumn get qty => real()();
  RealColumn get costPrice => real()();
  RealColumn get lineTotal => real()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class StockMovements extends Table {
  TextColumn get id => text()();
  TextColumn get storeId => text().references(Stores, #id)();
  TextColumn get productId => text().references(Products, #id)();
  TextColumn get type => text()();
  RealColumn get quantity => real()();
  RealColumn get previousQty => real()();
  RealColumn get newQty => real()();
  TextColumn get referenceType => text()();
  TextColumn get referenceId => text().nullable()();
  TextColumn get note => text().withDefault(const Constant(''))();
  TextColumn get userId => text().references(Users, #id)();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class AuditLogs extends Table {
  TextColumn get id => text()();
  TextColumn get userId => text().nullable().references(Users, #id)();
  TextColumn get storeId => text().nullable().references(Stores, #id)();
  TextColumn get action => text()();
  TextColumn get entityType => text()();
  TextColumn get entityId => text().nullable()();
  TextColumn get description => text()();
  TextColumn get oldValueJson => text().nullable()();
  TextColumn get newValueJson => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class AppSettings extends Table {
  TextColumn get key => text()();
  TextColumn get storeId => text().nullable().references(Stores, #id)();
  TextColumn get value => text()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {key, storeId};
}

class HeldCarts extends Table {
  TextColumn get id => text()();
  TextColumn get storeId => text().references(Stores, #id)();
  TextColumn get userId => text().references(Users, #id)();
  TextColumn get customerId => text().nullable().references(Customers, #id)();
  TextColumn get label => text()();
  TextColumn get cartJson => text()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class InvoiceSequences extends Table {
  TextColumn get storeId => text().references(Stores, #id)();
  IntColumn get year => integer()();
  IntColumn get lastValue => integer().withDefault(const Constant(0))();

  @override
  Set<Column<Object>> get primaryKey => {storeId, year};
}

class BackupRecords extends Table {
  TextColumn get id => text()();
  TextColumn get filePath => text()();
  TextColumn get sha256 => text()();
  IntColumn get sizeBytes => integer()();
  TextColumn get status => text()();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DriftDatabase(
  tables: [
    Stores,
    Roles,
    Users,
    Categories,
    Products,
    ProductStores,
    Customers,
    Suppliers,
    Sales,
    SaleItems,
    Payments,
    CashSessions,
    CashTransactions,
    Purchases,
    PurchaseItems,
    StockMovements,
    AuditLogs,
    AppSettings,
    HeldCarts,
    InvoiceSequences,
    BackupRecords,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase({QueryExecutor? executor}) : super(executor ?? _openConnection());

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (migrator) async {
      await migrator.createAll();
      await _createIndexes();
      await _createPhaseTwoIndexes();
    },
    onUpgrade: (migrator, from, to) async {
      if (from < 2) {
        await _createPhaseTwoIndexes();
      }
    },
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
      await customStatement('PRAGMA journal_mode = WAL');
      await customStatement('PRAGMA synchronous = NORMAL');
      await customStatement('PRAGMA busy_timeout = 5000');
    },
  );

  Future<void> _createIndexes() async {
    const statements = [
      'CREATE INDEX IF NOT EXISTS idx_products_name ON products(name COLLATE NOCASE)',
      'CREATE INDEX IF NOT EXISTS idx_products_category ON products(category_id)',
      'CREATE INDEX IF NOT EXISTS idx_products_active ON products(is_active)',
      'CREATE INDEX IF NOT EXISTS idx_product_stores_store_available ON product_stores(store_id, is_available)',
      'CREATE INDEX IF NOT EXISTS idx_product_stores_low_stock ON product_stores(store_id, stock_qty, reorder_level)',
      'CREATE INDEX IF NOT EXISTS idx_customers_name ON customers(name COLLATE NOCASE)',
      'CREATE INDEX IF NOT EXISTS idx_customers_phone ON customers(phone)',
      'CREATE INDEX IF NOT EXISTS idx_sales_store_created ON sales(store_id, created_at DESC)',
      'CREATE INDEX IF NOT EXISTS idx_sales_user_created ON sales(user_id, created_at DESC)',
      'CREATE INDEX IF NOT EXISTS idx_sales_customer_created ON sales(customer_id, created_at DESC)',
      'CREATE INDEX IF NOT EXISTS idx_sale_items_sale ON sale_items(sale_id)',
      'CREATE INDEX IF NOT EXISTS idx_payments_sale ON payments(sale_id)',
      'CREATE INDEX IF NOT EXISTS idx_stock_product_store_created ON stock_movements(product_id, store_id, created_at DESC)',
      'CREATE INDEX IF NOT EXISTS idx_cash_store_created ON cash_transactions(store_id, created_at DESC)',
      'CREATE INDEX IF NOT EXISTS idx_audit_store_created ON audit_logs(store_id, created_at DESC)',
      'CREATE INDEX IF NOT EXISTS idx_audit_entity ON audit_logs(entity_type, entity_id)',
    ];
    for (final statement in statements) {
      await customStatement(statement);
    }
  }

  Future<void> _createPhaseTwoIndexes() async {
    const statements = [
      "CREATE UNIQUE INDEX IF NOT EXISTS idx_app_settings_scope ON app_settings(key, COALESCE(store_id, ''))",
      'CREATE INDEX IF NOT EXISTS idx_users_store_active ON users(store_id, is_active)',
      'CREATE INDEX IF NOT EXISTS idx_categories_parent_active_sort ON categories(parent_id, is_active, sort_order)',
      'CREATE INDEX IF NOT EXISTS idx_products_barcode_active ON products(barcode, is_active)',
      'CREATE INDEX IF NOT EXISTS idx_products_sku_active ON products(sku, is_active)',
      'CREATE INDEX IF NOT EXISTS idx_held_carts_store_user_updated ON held_carts(store_id, user_id, updated_at DESC)',
      'CREATE INDEX IF NOT EXISTS idx_payments_method_created ON payments(method, created_at DESC)',
    ];
    for (final statement in statements) {
      await customStatement(statement);
    }
  }

  static Future<File> databaseFile() async {
    final support = await getApplicationSupportDirectory();
    final directory = Directory(p.join(support.path, 'StoreFlow POS'));
    if (!directory.existsSync()) {
      await directory.create(recursive: true);
    }
    return File(p.join(directory.path, 'storeflow.sqlite'));
  }
}

LazyDatabase _openConnection() => LazyDatabase(() async {
  final file = await AppDatabase.databaseFile();
  return NativeDatabase.createInBackground(file);
});
