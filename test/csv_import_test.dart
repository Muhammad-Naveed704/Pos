import 'package:flutter_test/flutter_test.dart';
import 'package:storeflow_pos/core/csv/csv_table.dart';
import 'package:storeflow_pos/core/csv/import_models.dart';
import 'package:storeflow_pos/features/auth/domain/app_session.dart';
import 'package:storeflow_pos/features/auth/domain/permission_guard.dart';
import 'package:storeflow_pos/features/auth/domain/permissions.dart';
import 'package:storeflow_pos/features/customers/data/customer_import_service.dart';
import 'package:storeflow_pos/features/products/data/product_import_service.dart';

import 'support/storeflow_fixture.dart';

void main() {
  late StoreFlowFixture fixture;
  late ProductImportService products;

  setUp(() {
    fixture = StoreFlowFixture();
    products = ProductImportService(fixture.database);
  });
  tearDown(() => fixture.close());

  CsvTable table(String csv, Map<String, String> aliases) =>
      parseCsvTable(csv, aliases: aliases);

  test('csv parsing normalises headers, aliases and delimiters', () {
    final parsed = parseCsvTable(
      '﻿Product Name;Code;Price\r\n"Tea, green";T-1;12,5\r\n;;\r\n',
      aliases: ProductImportService.aliases,
    );
    expect(parsed.headers, ['name', 'sku', 'sale_price']);
    expect(parsed.rows, hasLength(1), reason: 'blank rows are skipped');
    expect(parsed.rows.single.text('name'), 'Tea, green');
    expect(parsed.rows.single.number('sale_price'), 12.5);
  });

  test(
    'product import creates missing categories, products and stock',
    () async {
      final owner = await fixture.initialize();
      final plan = await products.prepare(
        owner,
        table(
          'sku,name,sale_price,category,stock,barcode,unit\n'
          'tea-1,Green Tea,120,Grocery > Tea,10,111,each\n'
          'SUG-1,Sugar,160,Grocery,5.5,,kg\n'
          'BAD,,abc,,,,\n'
          'TEA-1,Dup,1,,,,\n'
          'X-2,Other,5,,,111,\n',
          ProductImportService.aliases,
        ),
      );
      final preview = plan.preview;
      expect(preview.count(ImportAction.create), 2);
      expect(preview.count(ImportAction.error), 3);
      final errors = preview.rows
          .where((row) => row.action == ImportAction.error)
          .map((row) => row.messages.join(' '))
          .join('\n');
      expect(errors, contains('Name is required'));
      expect(errors, contains('not a valid sale_price'));
      expect(errors, contains('Duplicate SKU'));
      expect(errors, contains('Barcode 111 is repeated'));
      expect(preview.notes.first, contains('2 new categories'));

      final outcome = await products.apply(owner, plan);
      expect(outcome.created, 2);

      final db = fixture.database;
      final categories = await db.select(db.categories).get();
      final grocery = categories.singleWhere((c) => c.name == 'Grocery');
      final tea = categories.singleWhere((c) => c.name == 'Tea');
      expect(tea.parentId, grocery.id);
      expect(grocery.parentId, isNull);

      final product = await (db.select(
        db.products,
      )..where((p) => p.sku.equals('TEA-1'))).getSingle();
      expect(product.categoryId, tea.id);
      expect(product.barcode, '111');
      final stock = await (db.select(
        db.productStores,
      )..where((s) => s.productId.equals(product.id))).getSingle();
      expect(stock.stockQty, 10);
      final movements = await db.select(db.stockMovements).get();
      expect(movements, hasLength(2));
      expect(movements.every((m) => m.referenceType == 'import'), isTrue);

      // Re-import updates in place, keeps unspecified fields and records
      // only the stock difference.
      final second = await products.prepare(
        owner,
        table(
          'sku,name,sale_price,stock\nTEA-1,Green Tea Large,150,12\n',
          ProductImportService.aliases,
        ),
      );
      expect(second.preview.count(ImportAction.update), 1);
      await products.apply(owner, second);
      final updated = await (db.select(
        db.products,
      )..where((p) => p.sku.equals('TEA-1'))).getSingle();
      expect(updated.name, 'Green Tea Large');
      expect(updated.salePrice, 150);
      expect(updated.barcode, '111');
      expect(updated.categoryId, tea.id);
      final latest = await db.select(db.stockMovements).get();
      expect(latest, hasLength(3));
      expect(latest.where((m) => m.quantity == 2), hasLength(1));

      // With updates disabled, existing SKUs are skipped.
      final skip = await products.prepare(
        owner,
        table('sku,name,sale_price\nTEA-1,X,1\n', ProductImportService.aliases),
        updateExisting: false,
      );
      expect(skip.preview.count(ImportAction.skip), 1);
      expect(skip.preview.hasWork, isFalse);
    },
  );

  test('missing required columns and permission are rejected', () async {
    final owner = await fixture.initialize();
    await expectLater(
      products.prepare(owner, table('name,price\nTea,1\n', const {})),
      throwsA(isA<ImportFormatException>()),
    );
    final cashier = AppSession(
      user: owner.user,
      role: owner.role,
      store: owner.store,
      permissions: const {Permissions.posView, Permissions.productsView},
    );
    await expectLater(
      products.prepare(
        cashier,
        table('sku,name,sale_price\nA,B,1\n', const {}),
      ),
      throwsA(isA<PermissionDeniedException>()),
    );
  });

  test('customer import matches existing customers by phone digits', () async {
    final owner = await fixture.initialize();
    final service = CustomerImportService(fixture.database);
    final first = await service.prepare(
      owner,
      table(
        'Customer Name,Mobile,Email,Points\n'
        'Ali,0300-1234567,ali@example.com,10\n'
        'Sara,,bad-email,\n'
        'Ali Again,03001234567,,\n',
        CustomerImportService.aliases,
      ),
    );
    expect(first.preview.count(ImportAction.create), 1);
    expect(first.preview.count(ImportAction.error), 2);
    await service.apply(owner, first);

    final second = await service.prepare(
      owner,
      table(
        'name,phone,notes\nAli Khan,0300 123 4567,VIP\n',
        CustomerImportService.aliases,
      ),
    );
    expect(second.preview.count(ImportAction.update), 1);
    await service.apply(owner, second);
    final customers = await fixture.database
        .select(fixture.database.customers)
        .get();
    expect(customers, hasLength(1));
    expect(customers.single.name, 'Ali Khan');
    expect(customers.single.notes, 'VIP');
    expect(customers.single.email, 'ali@example.com');
    expect(customers.single.loyaltyPoints, 10);
  });
}
