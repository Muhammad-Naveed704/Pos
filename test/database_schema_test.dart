import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:storeflow_pos/core/database/app_database.dart';

void main() {
  late AppDatabase database;

  setUp(() {
    database = AppDatabase(executor: NativeDatabase.memory());
  });

  tearDown(() => database.close());

  test('migration creates the complete version two schema', () async {
    expect(database.schemaVersion, 2);
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
      expect(version.read<int>('user_version'), 2);
    } finally {
      await migrationDatabase?.close();
      if (directory.existsSync()) directory.deleteSync(recursive: true);
    }
  });
}
