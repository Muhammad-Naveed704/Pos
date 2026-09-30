import 'package:flutter_test/flutter_test.dart';
import 'package:storeflow_pos/features/auth/data/account_recovery_service.dart';
import 'package:storeflow_pos/features/auth/data/auth_repository.dart';
import 'package:storeflow_pos/features/auth/data/password_hasher.dart';
import 'package:storeflow_pos/features/auth/domain/app_session.dart';
import 'package:storeflow_pos/features/auth/domain/permission_guard.dart';
import 'package:storeflow_pos/features/auth/domain/permissions.dart';
import 'package:storeflow_pos/features/setup/data/first_run_service.dart';

import 'support/storeflow_fixture.dart';

void main() {
  late StoreFlowFixture fixture;
  late AccountRecoveryService recovery;
  late AuthRepository auth;

  setUp(() {
    fixture = StoreFlowFixture();
    recovery = AccountRecoveryService(fixture.database, PasswordHasher());
    auth = AuthRepository(fixture.database, PasswordHasher());
  });
  tearDown(() => fixture.close());

  test('setup key resets the owner password exactly once', () async {
    final key = await FirstRunService(fixture.database, PasswordHasher())
        .complete(
          const FirstRunInput(
            businessName: 'B',
            storeName: 'S',
            storeCode: 'MAIN',
            address: '',
            phone: '',
            currency: 'PKR',
            timezone: 'UTC',
            ownerName: 'Owner',
            username: 'owner',
            password: 'old-password',
            taxMode: 'exclusive',
            receiptFooter: '',
          ),
        );
    expect(key, matches(RegExp(r'^[A-Z0-9]{4}(-[A-Z0-9]{4}){4}$')));
    expect(await recovery.keyCreatedAt(), isNotNull);

    await expectLater(
      recovery.resetPassword(
        username: 'owner',
        recoveryKey: 'WRONG-WRONG-WRONG-WRONG-WRONG',
        newPassword: 'new-password',
      ),
      throwsA(isA<RecoveryException>()),
    );

    // Dashes, spaces and case are ignored.
    await recovery.resetPassword(
      username: 'OWNER',
      recoveryKey: key.toLowerCase().replaceAll('-', ' '),
      newPassword: 'new-password',
    );
    expect(await auth.authenticate('owner', 'new-password'), isA<AppSession>());
    await expectLater(
      auth.authenticate('owner', 'old-password'),
      throwsA(isA<AuthenticationException>()),
    );

    // Single use.
    expect(await recovery.keyCreatedAt(), isNull);
    await expectLater(
      recovery.resetPassword(
        username: 'owner',
        recoveryKey: key,
        newPassword: 'another-password',
      ),
      throwsA(isA<RecoveryException>()),
    );
  });

  test(
    'generating a key requires users.manage and replaces the old one',
    () async {
      final owner = await fixture.initialize();
      final cashier = AppSession(
        user: owner.user,
        role: owner.role,
        store: owner.store,
        permissions: const {Permissions.posView},
      );
      expect(
        () => recovery.generate(cashier),
        throwsA(isA<PermissionDeniedException>()),
      );
      final first = await recovery.generate(owner);
      final second = await recovery.generate(owner);
      expect(second, isNot(first));
      await expectLater(
        recovery.resetPassword(
          username: 'owner',
          recoveryKey: first,
          newPassword: 'new-password',
        ),
        throwsA(isA<RecoveryException>()),
        reason: 'a replaced key must stop working',
      );
    },
  );

  test('users can change their own password with the current one', () async {
    final owner = await fixture.initialize();
    await expectLater(
      recovery.changeOwnPassword(
        session: owner,
        currentPassword: 'wrong-password',
        newPassword: 'changed-password',
      ),
      throwsA(isA<RecoveryException>()),
    );
    await recovery.changeOwnPassword(
      session: owner,
      currentPassword: 'test-password',
      newPassword: 'changed-password',
    );
    expect(
      await auth.authenticate('owner', 'changed-password'),
      isA<AppSession>(),
    );
  });
}
