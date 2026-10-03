import 'package:flutter_test/flutter_test.dart';
import 'package:storeflow_pos/features/auth/domain/app_session.dart';
import 'package:storeflow_pos/features/categories/data/category_repository.dart';

import 'support/storeflow_fixture.dart';

void main() {
  late StoreFlowFixture fixture;
  late AppSession owner;
  late CategoryRepository categories;

  setUp(() async {
    fixture = StoreFlowFixture();
    owner = await fixture.initialize();
    categories = CategoryRepository(fixture.database);
  });
  tearDown(() => fixture.close());

  test('main categories and sub-categories, with two levels only', () async {
    final grocery = await categories.save(
      session: owner,
      name: 'Grocery',
      code: 'groc',
    );
    final rice = await categories.save(
      session: owner,
      name: 'Rice',
      code: 'RICE',
      parentId: grocery,
    );
    final all = await categories.watch().first;
    final riceRow = all.firstWhere((c) => c.id == rice);
    expect(riceRow.parentId, grocery);
    expect(all.firstWhere((c) => c.id == grocery).code, 'GROC');
    expect(categoryPath(riceRow, all), 'Grocery › Rice');

    // A sub-category cannot hold sub-categories.
    await expectLater(
      categories.save(
        session: owner,
        name: 'Basmati',
        code: 'BASM',
        parentId: rice,
      ),
      throwsA(isA<CategoryException>()),
    );
    // A main category with children cannot become a sub-category.
    final pharmacy = await categories.save(
      session: owner,
      name: 'Pharmacy',
      code: 'PHAR',
    );
    await expectLater(
      categories.save(
        session: owner,
        id: grocery,
        name: 'Grocery',
        code: 'GROC',
        parentId: pharmacy,
      ),
      throwsA(isA<CategoryException>()),
    );
  });

  test('duplicate names and codes are refused, edits keep createdAt', () async {
    final grocery = await categories.save(
      session: owner,
      name: 'Grocery',
      code: 'GROC',
    );
    await expectLater(
      categories.save(session: owner, name: ' grocery ', code: 'GRO2'),
      throwsA(
        isA<CategoryException>().having(
          (e) => e.message,
          'message',
          contains('already exists'),
        ),
      ),
    );
    await expectLater(
      categories.save(session: owner, name: 'Snacks', code: 'groc'),
      throwsA(isA<CategoryException>()),
    );
    // The same sub-category name is fine under different main categories.
    final pharmacy = await categories.save(
      session: owner,
      name: 'Pharmacy',
      code: 'PHAR',
    );
    await categories.save(
      session: owner,
      name: 'Other',
      code: 'G-OTH',
      parentId: grocery,
    );
    await categories.save(
      session: owner,
      name: 'Other',
      code: 'P-OTH',
      parentId: pharmacy,
    );

    final before = (await categories.watch().first).firstWhere(
      (c) => c.id == grocery,
    );
    await categories.save(
      session: owner,
      id: grocery,
      name: 'Groceries',
      code: 'GROC',
    );
    final after = (await categories.watch().first).firstWhere(
      (c) => c.id == grocery,
    );
    expect(after.name, 'Groceries');
    expect(after.createdAt, before.createdAt);
  });
}
