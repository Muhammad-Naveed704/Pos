import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/database_provider.dart';
import '../domain/app_session.dart';
import '../../users/data/role_repository.dart';
import '../domain/permissions.dart';
import 'password_hasher.dart';

class AuthenticationException implements Exception {
  const AuthenticationException(this.message);
  final String message;
  @override
  String toString() => message;
}

final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => AuthRepository(ref.watch(databaseProvider), PasswordHasher()),
);

class AuthRepository {
  AuthRepository(this._database, this._hasher);

  final AppDatabase _database;
  final PasswordHasher _hasher;

  Future<AppSession> authenticate(String username, String password) async {
    final normalized = username.trim().toLowerCase();
    final user =
        await (_database.select(_database.users)
              ..where((row) => row.username.equals(normalized))
              ..limit(1))
            .getSingleOrNull();
    if (user == null) {
      throw const AuthenticationException('Invalid username or password.');
    }
    if (!user.isActive) {
      throw const AuthenticationException('This account is inactive.');
    }
    final valid = await _hasher.verify(
      password: password,
      expectedHash: user.passwordHash,
      salt: user.passwordSalt,
    );
    if (!valid) {
      throw const AuthenticationException('Invalid username or password.');
    }
    await PermissionUpgrade.run(_database);
    final role = await (_database.select(
      _database.roles,
    )..where((row) => row.id.equals(user.roleId))).getSingle();
    final stores = await availableStores(user);
    if (stores.isEmpty) {
      throw const AuthenticationException(
        'No active store is available for this user.',
      );
    }
    await (_database.update(_database.users)
          ..where((row) => row.id.equals(user.id)))
        .write(UsersCompanion(lastLoginAt: Value(DateTime.now())));
    // The Owner always holds every permission, including ones added later.
    final permissions = role.isSystem && role.name == ownerRoleName
        ? Permissions.all
        : decodePermissions(role.permissionsJson);
    return AppSession(
      user: user.copyWith(lastLoginAt: Value(DateTime.now())),
      role: role,
      store: stores.first,
      permissions: permissions,
    );
  }

  Future<List<Store>> availableStores(User user) {
    final query = _database.select(_database.stores)
      ..where((store) {
        final active = store.isActive.equals(true);
        return user.storeId == null
            ? active
            : active & store.id.equals(user.storeId!);
      })
      ..orderBy([(store) => OrderingTerm.asc(store.name)]);
    return query.get();
  }

  Future<Store> requireStoreForUser(User user, String storeId) async {
    final stores = await availableStores(user);
    return stores.firstWhere(
      (store) => store.id == storeId,
      orElse: () => throw const AuthenticationException(
        'This user cannot access the selected store.',
      ),
    );
  }
}
