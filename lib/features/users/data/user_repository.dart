import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/database_provider.dart';
import '../../auth/data/password_hasher.dart';
import '../../auth/domain/app_session.dart';
import '../../auth/domain/permission_guard.dart';
import '../../auth/domain/permissions.dart';

final userRepositoryProvider = Provider<UserRepository>(
  (ref) => UserRepository(ref.watch(databaseProvider), PasswordHasher()),
);

class UserWithRole {
  const UserWithRole(this.user, this.role);
  final User user;
  final Role role;
}

class UserRepository {
  UserRepository(this._database, this._hasher, {Uuid? uuid})
    : _uuid = uuid ?? const Uuid();
  final AppDatabase _database;
  final PasswordHasher _hasher;
  final Uuid _uuid;

  Stream<List<UserWithRole>> watchAll(AppSession session) {
    PermissionGuard.require(session, Permissions.usersView);
    final query = _database.select(_database.users).join([
      innerJoin(
        _database.roles,
        _database.roles.id.equalsExp(_database.users.roleId),
      ),
    ])..orderBy([OrderingTerm.asc(_database.users.displayName)]);
    return query.watch().map(
      (rows) => rows
          .map(
            (row) => UserWithRole(
              row.readTable(_database.users),
              row.readTable(_database.roles),
            ),
          )
          .toList(),
    );
  }

  Future<List<Role>> roles() => (_database.select(
    _database.roles,
  )..orderBy([(row) => OrderingTerm.asc(row.name)])).get();

  Future<String> create({
    required AppSession session,
    required String username,
    required String displayName,
    required String password,
    required String roleId,
    String? storeId,
  }) async {
    PermissionGuard.require(session, Permissions.usersManage);
    final digest = await _hasher.hash(password);
    final id = _uuid.v4();
    final now = DateTime.now();
    await _database
        .into(_database.users)
        .insert(
          UsersCompanion.insert(
            id: id,
            username: username.trim().toLowerCase(),
            displayName: displayName.trim(),
            passwordHash: digest.hash,
            passwordSalt: digest.salt,
            roleId: roleId,
            storeId: Value(storeId),
            createdAt: now,
            updatedAt: now,
          ),
        );
    return id;
  }

  Future<void> update({
    required AppSession session,
    required User user,
    required String displayName,
    required String roleId,
    required String? storeId,
    required bool isActive,
    String? newPassword,
  }) async {
    PermissionGuard.require(session, Permissions.usersManage);
    if (user.id == session.user.id && !isActive) {
      throw StateError('You cannot deactivate your own account.');
    }
    PasswordDigest? digest;
    if (newPassword != null && newPassword.isNotEmpty) {
      digest = await _hasher.hash(newPassword);
    }
    await (_database.update(
      _database.users,
    )..where((row) => row.id.equals(user.id))).write(
      UsersCompanion(
        displayName: Value(displayName.trim()),
        roleId: Value(roleId),
        storeId: Value(storeId),
        isActive: Value(isActive),
        passwordHash: digest == null
            ? const Value.absent()
            : Value(digest.hash),
        passwordSalt: digest == null
            ? const Value.absent()
            : Value(digest.salt),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  Future<void> updateRolePermissions(
    AppSession session,
    Role role,
    Set<String> permissions,
  ) async {
    PermissionGuard.require(session, Permissions.usersManage);
    if (role.name == 'Owner') {
      throw StateError('Owner permissions cannot be reduced.');
    }
    await (_database.update(
      _database.roles,
    )..where((row) => row.id.equals(role.id))).write(
      RolesCompanion(
        permissionsJson: Value(jsonEncode(permissions.toList()..sort())),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }
}
