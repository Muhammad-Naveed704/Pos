import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:storeflow_pos/core/database/app_database.dart';
import 'package:storeflow_pos/features/auth/data/auth_repository.dart';
import 'package:storeflow_pos/features/auth/data/password_hasher.dart';
import 'package:storeflow_pos/features/auth/domain/permission_guard.dart';
import 'package:storeflow_pos/features/stores/data/store_repository.dart';
import 'package:storeflow_pos/features/users/data/user_repository.dart';

import 'support/storeflow_fixture.dart';

void main() {
  late StoreFlowFixture fixture;

  setUp(() => fixture = StoreFlowFixture());
  tearDown(() => fixture.close());

  test(
    'first-run setup creates store, default roles, owner and settings',
    () async {
      await fixture.initialize();

      expect(
        await fixture.database.select(fixture.database.stores).get(),
        hasLength(1),
      );
      expect(
        await fixture.database.select(fixture.database.roles).get(),
        hasLength(5),
      );
      expect(
        await fixture.database.select(fixture.database.users).get(),
        hasLength(1),
      );
      expect(
        await fixture.database.select(fixture.database.appSettings).get(),
        isNotEmpty,
      );
      expect(
        await fixture.database.select(fixture.database.invoiceSequences).get(),
        hasLength(1),
      );
    },
  );

  test('authentication accepts valid password and rejects invalid or inactive users', () async {
    final session = await fixture.initialize();
    final auth = AuthRepository(fixture.database, PasswordHasher());

    expect(
      (await auth.authenticate('OWNER', 'test-password')).user.id,
      session.user.id,
    );
    expect(
      () => auth.authenticate('owner', 'wrong-password'),
      throwsA(isA<AuthenticationException>()),
    );
    await (fixture.database.update(fixture.database.users)
          ..where((row) => row.id.equals(session.user.id)))
        .write(const UsersCompanion(isActive: Value(false)));
    expect(
      () => auth.authenticate('owner', 'test-password'),
      throwsA(isA<AuthenticationException>()),
    );
  });

  test('repositories enforce permissions, not only UI visibility', () async {
    final owner = await fixture.initialize();
    final roles = await UserRepository(
      fixture.database,
      PasswordHasher(),
    ).roles();
    final cashierRole = roles.firstWhere((role) => role.name == 'Cashier');
    await UserRepository(fixture.database, PasswordHasher()).create(
      session: owner,
      username: 'cashier',
      displayName: 'Cashier',
      password: 'cashier-password',
      roleId: cashierRole.id,
      storeId: owner.store.id,
    );
    final cashier = await AuthRepository(
      fixture.database,
      PasswordHasher(),
    ).authenticate('cashier', 'cashier-password');

    expect(
      () =>
          StoreRepository(fixture.database)
              .create(session: cashier, name: 'Denied Store', code: 'DENIED'),
      throwsA(isA<PermissionDeniedException>()),
    );
    expect(
      await StoreRepository(fixture.database)
          .create(session: owner, name: 'Allowed Store', code: 'OK'),
      isNotEmpty,
    );
  });
}
