import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/database_provider.dart';
import '../../auth/domain/app_session.dart';
import '../../auth/domain/permission_guard.dart';
import '../../auth/domain/permissions.dart';

final roleRepositoryProvider = Provider<RoleRepository>(
  (ref) => RoleRepository(ref.watch(databaseProvider)),
);

class RoleSummary {
  const RoleSummary(this.role, this.permissions, this.userCount);
  final Role role;
  final Set<String> permissions;
  final int userCount;

  bool get isOwner => role.isSystem && role.name == ownerRoleName;
}

const ownerRoleName = 'Owner';

Set<String> decodePermissions(String json) {
  try {
    return (jsonDecode(json) as List<dynamic>).cast<String>().toSet();
  } catch (_) {
    return <String>{};
  }
}

String encodePermissions(Set<String> permissions) =>
    jsonEncode(permissions.where(Permissions.all.contains).toList()..sort());

/// Default permission set of a built-in role, by name.
Set<String>? defaultPermissionsFor(String roleName) => switch (roleName) {
  ownerRoleName => Permissions.all,
  'Admin' => Permissions.admin,
  'Manager' => Permissions.manager,
  'Cashier' => Permissions.cashier,
  'Inventory Staff' => Permissions.inventoryStaff,
  _ => null,
};

class RoleRepository {
  RoleRepository(this._database, {Uuid? uuid}) : _uuid = uuid ?? const Uuid();
  final AppDatabase _database;
  final Uuid _uuid;

  Stream<List<RoleSummary>> watch(AppSession session) {
    PermissionGuard.require(session, Permissions.usersView);
    return _database
        .customSelect(
          '''
          SELECT r.*, (SELECT COUNT(*) FROM users u WHERE u.role_id = r.id) AS user_count
          FROM roles r
          ORDER BY r.is_system DESC, r.name COLLATE NOCASE
          ''',
          readsFrom: {_database.roles, _database.users},
        )
        .watch()
        .map(
          (rows) => [
            for (final row in rows)
              () {
                final role = _database.roles.map(row.data);
                return RoleSummary(
                  role,
                  role.isSystem && role.name == ownerRoleName
                      ? Permissions.all
                      : decodePermissions(role.permissionsJson),
                  row.read<int>('user_count'),
                );
              }(),
          ],
        );
  }

  void _checkName(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) throw ArgumentError('Role name is required.');
    if (trimmed.length > 80) {
      throw ArgumentError('Role name must be 80 characters or fewer.');
    }
  }

  Future<Set<String>> _existingNames() async =>
      (await _database.select(_database.roles).get())
          .map((role) => role.name.toLowerCase())
          .toSet();

  /// Creates several roles at once, each starting with [permissions].
  Future<List<String>> createRoles(
    AppSession session, {
    required List<String> names,
    required Set<String> permissions,
  }) async {
    PermissionGuard.require(session, Permissions.usersManage);
    final cleaned = names.map((name) => name.trim()).where((n) => n.isNotEmpty);
    final unique = <String>[];
    for (final name in cleaned) {
      _checkName(name);
      if (!unique.any((n) => n.toLowerCase() == name.toLowerCase())) {
        unique.add(name);
      }
    }
    if (unique.isEmpty) throw ArgumentError('Enter at least one role name.');
    final ids = <String>[];
    await _database.transaction(() async {
      final existing = await _existingNames();
      final clash = unique.where((n) => existing.contains(n.toLowerCase()));
      if (clash.isNotEmpty) {
        throw StateError('Role already exists: ${clash.join(', ')}');
      }
      final now = DateTime.now();
      for (final name in unique) {
        final id = _uuid.v4();
        ids.add(id);
        await _database
            .into(_database.roles)
            .insert(
              RolesCompanion.insert(
                id: id,
                name: name,
                permissionsJson: Value(encodePermissions(permissions)),
                createdAt: now,
                updatedAt: now,
              ),
            );
      }
      await _audit(
        session,
        'roles.created',
        'Created role(s): ${unique.join(', ')}.',
      );
    });
    return ids;
  }

  Future<void> rename(AppSession session, Role role, String name) async {
    PermissionGuard.require(session, Permissions.usersManage);
    _checkName(name);
    if (role.isSystem) throw StateError('Built-in roles cannot be renamed.');
    await _database.transaction(() async {
      final existing = await _existingNames();
      if (name.trim().toLowerCase() != role.name.toLowerCase() &&
          existing.contains(name.trim().toLowerCase())) {
        throw StateError('Role already exists: ${name.trim()}');
      }
      await (_database.update(
        _database.roles,
      )..where((r) => r.id.equals(role.id))).write(
        RolesCompanion(
          name: Value(name.trim()),
          updatedAt: Value(DateTime.now()),
        ),
      );
      await _audit(
        session,
        'roles.renamed',
        'Renamed ${role.name} to ${name.trim()}.',
      );
    });
  }

  Future<void> delete(AppSession session, Role role) async {
    PermissionGuard.require(session, Permissions.usersManage);
    if (role.isSystem) throw StateError('Built-in roles cannot be deleted.');
    await _database.transaction(() async {
      final users = await (_database.select(
        _database.users,
      )..where((u) => u.roleId.equals(role.id))).get();
      if (users.isNotEmpty) {
        throw StateError(
          'Move the ${users.length} user(s) with this role to another role first.',
        );
      }
      await (_database.delete(
        _database.roles,
      )..where((r) => r.id.equals(role.id))).go();
      await _audit(session, 'roles.deleted', 'Deleted role ${role.name}.');
    });
  }

  /// Saves permission changes for many roles in one transaction.
  Future<void> savePermissions(
    AppSession session,
    Map<String, Set<String>> byRoleId,
  ) async {
    PermissionGuard.require(session, Permissions.usersManage);
    if (byRoleId.isEmpty) return;
    await _database.transaction(() async {
      final roles = await (_database.select(
        _database.roles,
      )..where((r) => r.id.isIn(byRoleId.keys))).get();
      final now = DateTime.now();
      final changes = <String, Object>{};
      for (final role in roles) {
        if (role.isSystem && role.name == ownerRoleName) {
          throw StateError('Owner permissions cannot be reduced.');
        }
        final next = byRoleId[role.id]!;
        // Nobody may grant permissions they do not hold themselves.
        final escalation = next
            .difference(decodePermissions(role.permissionsJson))
            .difference(session.permissions);
        if (escalation.isNotEmpty) {
          throw PermissionDeniedException(escalation.first);
        }
        await (_database.update(
          _database.roles,
        )..where((r) => r.id.equals(role.id))).write(
          RolesCompanion(
            permissionsJson: Value(encodePermissions(next)),
            updatedAt: Value(now),
          ),
        );
        changes[role.name] = (next.toList()..sort());
      }
      await _audit(
        session,
        'roles.permissions_updated',
        'Updated permissions for ${changes.keys.join(', ')}.',
        json: jsonEncode(changes),
      );
    });
  }

  Future<void> _audit(
    AppSession session,
    String action,
    String description, {
    String? json,
  }) => _database
      .into(_database.auditLogs)
      .insert(
        AuditLogsCompanion.insert(
          id: _uuid.v4(),
          userId: Value(session.user.id),
          storeId: Value(session.store.id),
          action: action,
          entityType: 'role',
          description: description,
          newValueJson: Value(json),
          createdAt: DateTime.now(),
        ),
      );
}

/// Grants permissions introduced in newer versions to built-in roles whose
/// default set includes them. Runs once per permission version; changes an
/// admin made to existing permissions are preserved.
abstract final class PermissionUpgrade {
  static const _key = 'permissions.version';

  static Future<void> run(AppDatabase database) async {
    final row = await (database.select(
      database.appSettings,
    )..where((r) => r.key.equals(_key) & r.storeId.isNull())).getSingleOrNull();
    final current = int.tryParse(row?.value ?? '') ?? 1;
    if (current >= Permissions.version) return;
    final roles = await database.select(database.roles).get();
    if (roles.isEmpty) return; // Not set up yet; setup writes full sets.
    await database.transaction(() async {
      final now = DateTime.now();
      final added = <String>{
        for (var v = current + 1; v <= Permissions.version; v++)
          ...?Permissions.introduced[v],
      };
      for (final role in roles.where((r) => r.isSystem)) {
        final defaults = defaultPermissionsFor(role.name);
        if (defaults == null) continue;
        final grant = added.intersection(defaults);
        if (grant.isEmpty) continue;
        final next = decodePermissions(role.permissionsJson)..addAll(grant);
        await (database.update(
          database.roles,
        )..where((r) => r.id.equals(role.id))).write(
          RolesCompanion(
            permissionsJson: Value(encodePermissions(next)),
            updatedAt: Value(now),
          ),
        );
      }
      final updated =
          await (database.update(
            database.appSettings,
          )..where((r) => r.key.equals(_key) & r.storeId.isNull())).write(
            AppSettingsCompanion(
              value: Value('${Permissions.version}'),
              updatedAt: Value(now),
            ),
          );
      if (updated == 0) {
        await database
            .into(database.appSettings)
            .insert(
              AppSettingsCompanion.insert(
                key: _key,
                value: '${Permissions.version}',
                updatedAt: now,
              ),
            );
      }
    });
  }
}
