import 'package:flutter_test/flutter_test.dart';
import 'package:storeflow_pos/core/money/currency.dart';
import 'package:storeflow_pos/features/auth/domain/app_session.dart';
import 'package:storeflow_pos/features/auth/domain/permission_guard.dart';
import 'package:storeflow_pos/features/auth/domain/permissions.dart';
import 'package:storeflow_pos/features/pos/domain/pos_cart.dart';
import 'package:storeflow_pos/features/settings/data/business_settings_repository.dart';
import 'package:storeflow_pos/features/settings/domain/business_settings.dart';

import 'support/storeflow_fixture.dart';

void main() {
  late StoreFlowFixture fixture;
  late BusinessSettingsRepository repository;

  setUp(() {
    fixture = StoreFlowFixture();
    repository = BusinessSettingsRepository(fixture.database);
  });
  tearDown(() => fixture.close());

  test('first-run values are loaded as typed business settings', () async {
    await fixture.initialize();
    final settings = await repository.load();
    expect(settings.businessName, 'Test Business');
    expect(settings.currencyCode, 'PKR');
    expect(settings.taxMode, TaxMode.exclusive);
    expect(settings.receiptFooter, 'Thanks');
    expect(settings.allowNegativeStock, isFalse);
    expect(settings.maxDiscountPercent, 100);
  });

  test('saving requires settings.manage', () async {
    final owner = await fixture.initialize();
    final cashier = AppSession(
      user: owner.user,
      role: owner.role,
      store: owner.store,
      permissions: const {Permissions.posView},
    );
    final settings = await repository.load();
    expect(
      () => repository.save(cashier, settings.copyWith(currencyCode: 'USD')),
      throwsA(isA<PermissionDeniedException>()),
    );
    expect((await repository.load()).currencyCode, 'PKR');
  });

  test(
    'save persists changes, inserts new keys and writes one audit row',
    () async {
      final owner = await fixture.initialize();
      final updated = (await repository.load()).copyWith(
        currencyCode: 'AED',
        numberStyle: NumberStyle.european,
        symbolPosition: SymbolPosition.after,
        taxMode: TaxMode.inclusive,
        taxLabel: 'VAT',
        receiptFooter: 'Shukran',
        maxDiscountPercent: 15,
        quickCashDenominations: const [10, 50, 100],
      );
      await repository.save(owner, updated);

      final reloaded = await repository.load();
      expect(reloaded.currencyCode, 'AED');
      expect(reloaded.numberStyle, NumberStyle.european);
      expect(reloaded.symbolPosition, SymbolPosition.after);
      expect(reloaded.taxMode, TaxMode.inclusive);
      expect(reloaded.taxLabel, 'VAT');
      expect(reloaded.receiptFooter, 'Shukran');
      expect(reloaded.maxDiscountPercent, 15);
      expect(reloaded.quickCashDenominations, [10, 50, 100]);
      expect(reloaded.formatter.major(1234.5), '1.234,50 AED');

      final audits = await (fixture.database.select(
        fixture.database.auditLogs,
      )..where((row) => row.action.equals('settings.updated'))).get();
      expect(audits, hasLength(1));

      // Saving identical values is a no-op and adds no audit noise.
      await repository.save(owner, reloaded);
      final after = await (fixture.database.select(
        fixture.database.auditLogs,
      )..where((row) => row.action.equals('settings.updated'))).get();
      expect(after, hasLength(1));

      // The checkout service reads the same keys.
      final taxRow = await fixture.database
          .customSelect(
            "SELECT value FROM app_settings WHERE key = 'tax.mode' AND store_id IS NULL",
          )
          .getSingle();
      expect(taxRow.read<String>('value'), 'inclusive');
      final rows = await fixture.database
          .customSelect(
            "SELECT COUNT(*) AS n FROM app_settings WHERE key = 'tax.mode'",
            readsFrom: {fixture.database.appSettings},
          )
          .getSingle();
      expect(rows.read<int>('n'), 1, reason: 'no duplicate global rows');
    },
  );

  test('blank business name is rejected', () async {
    final owner = await fixture.initialize();
    final settings = await repository.load();
    expect(
      () => repository.save(owner, settings.copyWith(businessName: '  ')),
      throwsArgumentError,
    );
  });

  test('corrupt stored values fall back to safe defaults', () {
    final settings = BusinessSettings.fromMap({
      BusinessSettings.keyTaxMode: 'bogus',
      BusinessSettings.keyMaxDiscount: '250',
      BusinessSettings.keyNumberStyle: 'nope',
      BusinessSettings.keyQuickCash: 'a, -5, 0',
    });
    expect(settings.taxMode, TaxMode.exclusive);
    expect(settings.maxDiscountPercent, 100);
    expect(settings.numberStyle, NumberStyle.international);
    expect(settings.quickCashDenominations, const [100, 500, 1000, 5000]);
  });
}
