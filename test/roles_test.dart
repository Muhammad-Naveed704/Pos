import 'dart:convert';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:storeflow_pos/core/database/app_database.dart';
import 'package:storeflow_pos/features/auth/data/auth_repository.dart';
import 'package:storeflow_pos/features/auth/data/password_hasher.dart';
import 'package:storeflow_pos/features/auth/domain/app_session.dart';
import 'package:storeflow_pos/features/auth/domain/permission_guard.dart';
import 'package:storeflow_pos/features/auth/domain/permissions.dart';
import 'package:storeflow_pos/features/users/data/role_repository.dart';
import 'package:storeflow_pos/features/users/data/user_repository.dart';

import 'support/storeflow_fixture.dart';

void main() {
  late StoreFlowFixture fixture;
  late RoleRepository roles;

  setUp(() {
    fixture = StoreFlowFixture();
    roles = RoleRepository(fixture.database);
  });
  tearDown(() => fixture.close());

  Future<List<RoleSummary>> all(AppSession session) =>
      roles.watch(session).first;

  test('bulk create, rename, duplicate names and delete guards', () async {
    final owner = await fixture.initialize();
    await roles.createRoles(
      owner,
      names: ['Senior Cashier', 'Stock Keeper', 'senior cashier', ' '],
      permissions: Permissions.cashier,
    );
    var list = await all(owner);
    expect(
      list.map((r) => r.role.name),
      containsAll(['Senior Cashier', 'Stock Keeper']),
    );
    expect(
      list.where((r) => r.role.name.toLowerCase() == 'senior cashier'),
      hasLength(1),
    );
    final senior = list.singleWhere((r) => r.role.name == 'Senior Cashier');
    expect(senior.permissions, Permissions.cashier);

    await expectLater(
      roles.createRoles(owner, names: ['Manager'], permissions: const {}),
      throwsA(isA<StateError>()),
    );

    await roles.rename(owner, senior.role, 'Head Cashier');
    list = await all(owner);
    final head = list.singleWhere((r) => r.role.name == 'Head Cashier');

    final manager = list.singleWhere((r) => r.role.name == 'Manager');
    await expectLater(
      roles.delete(owner, manager.role),
      throwsA(isA<StateError>()),
      reason: 'built-in roles cannot be deleted',
    );

    await UserRepository(fixture.database, PasswordHasher()).create(
      session: owner,
      username: 'sam',
      displayName: 'Sam',
      password: 'sam-password',
      roleId: head.role.id,
      storeId: owner.store.id,
    );
    await expectLater(
      roles.delete(owner, head.role),
      throwsA(isA<StateError>()),
      reason: 'roles in use cannot be deleted',
    );
    final keeper = list.singleWhere((r) => r.role.name == 'Stock Keeper');
    await roles.delete(owner, keeper.role);
    expect(
      (await all(owner)).where((r) => r.role.name == 'Stock Keeper'),
      isEmpty,
    );
  });

  test('bulk permission save guards owner and privilege escalation', () async {
    final owner = await fixture.initialize();
    var list = await all(owner);
    final cashier = list.singleWhere((r) => r.role.name == 'Cashier');
    final inventory = list.singleWhere((r) => r.role.name == 'Inventory Staff');
    final ownerRole = list.singleWhere((r) => r.isOwner);

    await roles.savePermissions(owner, {
      cashier.role.id: {...cashier.permissions, Permissions.posApplyDiscount},
      inventory.role.id: {Permissions.inventoryView},
    });
    list = await all(owner);
    expect(
      list.singleWhere((r) => r.role.name == 'Cashier').permissions,
      contains(Permissions.posApplyDiscount),
    );
    expect(
      list.singleWhere((r) => r.role.name == 'Inventory Staff').permissions,
      {Permissions.inventoryView},
    );

    await expectLater(
      roles.savePermissions(owner, {ownerRole.role.id: const {}}),
      throwsA(isA<StateError>()),
    );

    final limitedAdmin = AppSession(
      user: owner.user,
      role: owner.role,
      store: owner.store,
      permissions: const {Permissions.usersManage, Permissions.usersView},
    );
    await expectLater(
      roles.savePermissions(limitedAdmin, {
        cashier.role.id: {Permissions.settingsManage},
      }),
      throwsA(isA<PermissionDeniedException>()),
    );
  });

  test('upgrade grants new permissions to built-in roles once', () async {
    final owner = await fixture.initialize();
    final db = fixture.database;
    // Simulate a version-1 install: remove v2 permissions and the marker.
    final v2 = Permissions.introduced[2]!;
    for (final role in await db.select(db.roles).get()) {
      final reduced = decodePermissions(role.permissionsJson)..removeAll(v2);
      await (db.update(db.roles)..where((r) => r.id.equals(role.id))).write(
        RolesCompanion(permissionsJson: Value(jsonEncode(reduced.toList()))),
      );
    }
    await (db.delete(
      db.appSettings,
    )..where((r) => r.key.equals('permissions.version'))).go();
    // An admin had removed a v1 permission from Manager; it must stay removed.
    final manager = await (db.select(
      db.roles,
    )..where((r) => r.name.equals('Manager'))).getSingle();
    final customised = decodePermissions(manager.permissionsJson)
      ..remove(Permissions.posVoidSale);
    await (db.update(db.roles)..where((r) => r.id.equals(manager.id))).write(
      RolesCompanion(permissionsJson: Value(jsonEncode(customised.toList()))),
    );

    await PermissionUpgrade.run(db);

    final upgraded = decodePermissions(
      (await (db.select(
        db.roles,
      )..where((r) => r.id.equals(manager.id))).getSingle()).permissionsJson,
    );
    expect(upgraded, contains(Permissions.purchasesManage));
    expect(upgraded, contains(Permissions.cashbookManage));
    expect(upgraded, isNot(contains(Permissions.posVoidSale)));
    final cashier = decodePermissions(
      (await (db.select(
        db.roles,
      )..where((r) => r.name.equals('Cashier'))).getSingle()).permissionsJson,
    );
    expect(cashier, contains(Permissions.cashbookManage));
    expect(cashier, isNot(contains(Permissions.purchasesManage)));

    // Owner always gets every permission at sign-in.
    final session = await AuthRepository(
      db,
      PasswordHasher(),
    ).authenticate('owner', 'test-password');
    expect(session.permissions, Permissions.all);
    expect(owner.permissions, Permissions.all);
  });
}
