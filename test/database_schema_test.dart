import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:storeflow_pos/core/database/app_database.dart';

/// Turns a fresh database back into the version 4 layout (before credit
/// accounts and backup metadata) so the v5 upgrade can be exercised.
Future<void> downgradeToV4(AppDatabase db) async {
  for (final index in [
    'idx_sales_credit_due',
    'idx_sales_store_payment_status',
    'idx_backup_records_created',
  ]) {
    await db.customStatement('DROP INDEX IF EXISTS $index');
  }
  await db.customStatement('DROP TABLE payment_allocations');
  await db.customStatement('DROP TABLE customer_ledger_entries');
  await db.customStatement('DROP TABLE customer_payments');
  await db.customStatement('ALTER TABLE sales DROP COLUMN credit_amount');
  await db.customStatement('ALTER TABLE sales DROP COLUMN due_date');
  await db.customStatement(
    'ALTER TABLE sale_refunds DROP COLUMN credit_applied',
  );
  await db.customStatement('ALTER TABLE backup_records DROP COLUMN kind');
  await db.customStatement('ALTER TABLE backup_records DROP COLUMN note');
}

void main() {
  late AppDatabase database;

  setUp(() {
    database = AppDatabase(executor: NativeDatabase.memory());
  });

  tearDown(() => database.close());

  test('migration creates the complete current schema', () async {
    expect(database.schemaVersion, 5);
    final rows = await database
        .customSelect(
          "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%'",
        )
        .get();
    final names = rows.map((row) => row.read<String>('name')).toSet();

    expect(
      names,
      containsAll(<String>{
        'stores',
        'roles',
        'users',
        'categories',
        'products',
        'product_stores',
        'customers',
        'sales',
        'sale_items',
        'payments',
        'stock_movements',
        'audit_logs',
        'app_settings',
        'cash_sessions',
        'backup_records',
        'sale_refunds',
        'sale_refund_items',
        'customer_payments',
        'customer_ledger_entries',
        'payment_allocations',
      }),
    );
  });

  test('migration creates critical lookup indexes', () async {
    final rows = await database
        .customSelect(
          "SELECT name FROM sqlite_master WHERE type = 'index' AND name LIKE 'idx_%'",
        )
        .get();
    final names = rows.map((row) => row.read<String>('name')).toSet();

    expect(names, contains('idx_products_name'));
    expect(names, contains('idx_sales_store_created'));
    expect(names, contains('idx_stock_product_store_created'));
    expect(names, contains('idx_audit_entity'));
    expect(names, contains('idx_app_settings_scope'));
    expect(names, contains('idx_products_barcode_active'));
    expect(names, contains('idx_products_sku_active'));
    expect(names, contains('idx_held_carts_store_user_updated'));
    expect(names, contains('idx_ledger_customer_created'));
    expect(names, contains('idx_allocations_sale'));
    expect(names, contains('idx_sales_credit_due'));
  });

  test('version one database upgrades without data loss', () async {
    await database.close();
    final directory = await Directory.systemTemp.createTemp(
      'storeflow-migration-',
    );
    final file = File('${directory.path}${Platform.pathSeparator}storeflow.db');
    AppDatabase? migrationDatabase;
    try {
      migrationDatabase = AppDatabase(executor: NativeDatabase(file));
      await migrationDatabase.select(migrationDatabase.stores).get();
      await migrationDatabase
          .into(migrationDatabase.stores)
          .insert(
            StoresCompanion.insert(
              id: 'preserved-store',
              name: 'Preserved Store',
              code: 'KEEP',
              createdAt: DateTime(2026),
              updatedAt: DateTime(2026),
            ),
          );
      for (final index in <String>[
        'idx_app_settings_scope',
        'idx_users_store_active',
        'idx_categories_parent_active_sort',
        'idx_products_barcode_active',
        'idx_products_sku_active',
        'idx_held_carts_store_user_updated',
        'idx_payments_method_created',
      ]) {
        await migrationDatabase.customStatement('DROP INDEX IF EXISTS $index');
      }
      await downgradeToV4(migrationDatabase);
      await migrationDatabase.customStatement(
        'ALTER TABLE sale_items DROP COLUMN unit_cost',
      );
      await migrationDatabase.customStatement('DROP TABLE sale_refund_items');
      await migrationDatabase.customStatement('DROP TABLE sale_refunds');
      await migrationDatabase.customStatement('PRAGMA user_version = 1');
      await migrationDatabase.close();
      migrationDatabase = null;

      final upgraded = AppDatabase(executor: NativeDatabase(file));
      migrationDatabase = upgraded;
      final preserved = await upgraded.select(upgraded.stores).getSingle();
      expect(preserved.id, 'preserved-store');
      final index = await upgraded
          .customSelect(
            "SELECT name FROM sqlite_master WHERE type = 'index' AND name = 'idx_products_sku_active'",
          )
          .getSingle();
      expect(index.read<String>('name'), 'idx_products_sku_active');
      final version = await upgraded
          .customSelect('PRAGMA user_version')
          .getSingle();
      expect(version.read<int>('user_version'), 5);
    } finally {
      await migrationDatabase?.close();
      if (directory.existsSync()) directory.deleteSync(recursive: true);
    }
  });

  test(
    'version two database gains sale cost snapshots without data loss',
    () async {
      await database.close();
      final directory = await Directory.systemTemp.createTemp('storeflow-v3-');
      final file = File(
        '${directory.path}${Platform.pathSeparator}storeflow.db',
      );
      AppDatabase? db;
      try {
        db = AppDatabase(executor: NativeDatabase(file));
        final now = DateTime(2026, 5, 1);
        await db
            .into(db.stores)
            .insert(
              StoresCompanion.insert(
                id: 's1',
                name: 'Store',
                code: 'S1',
                createdAt: now,
                updatedAt: now,
              ),
            );
        await db
            .into(db.roles)
            .insert(
              RolesCompanion.insert(
                id: 'r1',
                name: 'Owner',
                createdAt: now,
                updatedAt: now,
              ),
            );
        await db
            .into(db.users)
            .insert(
              UsersCompanion.insert(
                id: 'u1',
                username: 'owner',
                displayName: 'Owner',
                passwordHash: 'x',
                passwordSalt: 'y',
                roleId: 'r1',
                createdAt: now,
                updatedAt: now,
              ),
            );
        await db
            .into(db.products)
            .insert(
              ProductsCompanion.insert(
                id: 'p1',
                sku: 'P1',
                name: 'Kettle',
                salePrice: 900,
                costPrice: const Value(640),
                createdAt: now,
                updatedAt: now,
              ),
            );
        await db
            .into(db.sales)
            .insert(
              SalesCompanion.insert(
                id: 'sale1',
                invoiceNumber: 'S1-2026-000001',
                storeId: 's1',
                userId: 'u1',
                subtotal: 900,
                grandTotal: 900,
                paymentStatus: 'paid',
                saleStatus: 'completed',
                createdAt: now,
                updatedAt: now,
              ),
            );
        await downgradeToV4(db);
        await db.customStatement(
          'ALTER TABLE sale_items DROP COLUMN unit_cost',
        );
        await db.customStatement(
          "INSERT INTO sale_items (id, sale_id, product_id, product_name_snapshot, sku_snapshot, qty, unit_price, discount_amount, tax_amount, line_total) "
          "VALUES ('i1', 'sale1', 'p1', 'Kettle', 'P1', 1, 900, 0, 0, 900)",
        );
        await db.customStatement('DROP TABLE sale_refund_items');
        await db.customStatement('DROP TABLE sale_refunds');
        await db.customStatement('PRAGMA user_version = 2');
        await db.close();
        db = null;

        final upgraded = AppDatabase(executor: NativeDatabase(file));
        db = upgraded;
        final item = await upgraded.select(upgraded.saleItems).getSingle();
        expect(item.productNameSnapshot, 'Kettle');
        expect(item.lineTotal, 900);
        expect(item.unitCost, 640, reason: 'backfilled from the product cost');
        final sale = await upgraded.select(upgraded.sales).getSingle();
        expect(sale.invoiceNumber, 'S1-2026-000001');
        final version = await upgraded
            .customSelect('PRAGMA user_version')
            .getSingle();
        expect(version.read<int>('user_version'), 5);
        final index = await upgraded
            .customSelect(
              "SELECT name FROM sqlite_master WHERE type = 'index' AND name = 'idx_stock_store_created'",
            )
            .get();
        expect(index, hasLength(1));
        // v4: refund tables exist and are usable.
        expect(await upgraded.select(upgraded.saleRefunds).get(), isEmpty);
        // v5: the old sale was fully paid.
        expect(sale.creditAmount, 0);
        expect(sale.dueDate, isNull);
      } finally {
        await db?.close();
        if (directory.existsSync()) directory.deleteSync(recursive: true);
      }
    },
  );

  test('version four database gains customer accounts without data loss', () async {
    await database.close();
    final directory = await Directory.systemTemp.createTemp('storeflow-v5-');
    final file = File('${directory.path}${Platform.pathSeparator}storeflow.db');
    AppDatabase? db;
    try {
      db = AppDatabase(executor: NativeDatabase(file));
      await db.select(db.stores).get();
      await downgradeToV4(db);
      final now = DateTime(2026, 6, 1);
      await db.customStatement(
        "INSERT INTO stores (id, name, code, address, phone, is_active, created_at, updated_at) "
        "VALUES ('s1', 'Store', 'S1', '', '', 1, ${now.millisecondsSinceEpoch ~/ 1000}, ${now.millisecondsSinceEpoch ~/ 1000})",
      );
      await db.customStatement(
        "INSERT INTO roles (id, name, permissions_json, is_system, created_at, updated_at) VALUES ('r1', 'Owner', '[]', 1, 0, 0)",
      );
      await db.customStatement(
        "INSERT INTO users (id, username, display_name, password_hash, password_salt, role_id, is_active, created_at, updated_at) "
        "VALUES ('u1', 'owner', 'Owner', 'x', 'y', 'r1', 1, 0, 0)",
      );
      await db.customStatement(
        "INSERT INTO customers (id, name, address, notes, loyalty_points, credit_limit, opening_balance, is_active, created_at, updated_at) "
        "VALUES ('c1', 'Owes Before', '', '', 0, 5000, 250, 1, 100, 100), "
        "('c2', 'Clean', '', '', 0, 0, 0, 1, 100, 100)",
      );
      await db.customStatement(
        "INSERT INTO sales (id, invoice_number, store_id, user_id, customer_id, subtotal, discount_amount, tax_amount, grand_total, paid_amount, change_amount, payment_status, sale_status, notes, created_at, updated_at) "
        "VALUES ('sale1', 'S1-2026-000001', 's1', 'u1', 'c1', 400, 0, 0, 400, 500, 100, 'paid', 'completed', '', 200, 200)",
      );
      await db.customStatement(
        "INSERT INTO sale_refunds (id, sale_id, store_id, user_id, number, kind, method, amount, reason, created_at) "
        "VALUES ('r1', 'sale1', 's1', 'u1', 'S1-2026-000001-R1', 'refund', 'cash', 100, 'x', 300)",
      );
      await db.customStatement('PRAGMA user_version = 4');
      await db.close();
      db = null;

      final upgraded = AppDatabase(executor: NativeDatabase(file));
      db = upgraded;
      final version = await upgraded
          .customSelect('PRAGMA user_version')
          .getSingle();
      expect(version.read<int>('user_version'), 5);
      final sale = await upgraded.select(upgraded.sales).getSingle();
      expect(sale.grandTotal, 400);
      expect(sale.creditAmount, 0);
      final refund = await upgraded.select(upgraded.saleRefunds).getSingle();
      expect(refund.amount, 100);
      expect(refund.creditApplied, 0);
      final ledger = await upgraded
          .select(upgraded.customerLedgerEntries)
          .get();
      expect(ledger, hasLength(1), reason: 'only the opening balance');
      expect(ledger.single.customerId, 'c1');
      expect(ledger.single.type, 'opening');
      expect(ledger.single.debit, 250);
      expect(await upgraded.select(upgraded.customerPayments).get(), isEmpty);
      expect(await upgraded.select(upgraded.paymentAllocations).get(), isEmpty);
      final backup = await upgraded
          .customSelect(
            "SELECT COUNT(*) AS n FROM pragma_table_info('backup_records') WHERE name = 'kind'",
          )
          .getSingle();
      expect(backup.read<int>('n'), 1);
      final index = await upgraded
          .customSelect(
            "SELECT name FROM sqlite_master WHERE type = 'index' AND name = 'idx_sales_credit_due'",
          )
          .get();
      expect(index, hasLength(1));
    } finally {
      await db?.close();
      if (directory.existsSync()) directory.deleteSync(recursive: true);
    }
  });
}
