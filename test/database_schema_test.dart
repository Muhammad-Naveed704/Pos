import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:storeflow_pos/core/database/app_database.dart';

void main() {
  late AppDatabase database;

  setUp(() {
    database = AppDatabase(executor: NativeDatabase.memory());
  });

  tearDown(() => database.close());

  test('migration creates the complete current schema', () async {
    expect(database.schemaVersion, 4);
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
      expect(version.read<int>('user_version'), 4);
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
        expect(version.read<int>('user_version'), 4);
        final index = await upgraded
            .customSelect(
              "SELECT name FROM sqlite_master WHERE type = 'index' AND name = 'idx_stock_store_created'",
            )
            .get();
        expect(index, hasLength(1));
        // v4: refund tables exist and are usable.
        expect(await upgraded.select(upgraded.saleRefunds).get(), isEmpty);
      } finally {
        await db?.close();
        if (directory.existsSync()) directory.deleteSync(recursive: true);
      }
    },
  );
}
