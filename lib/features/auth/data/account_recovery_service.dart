import 'dart:math';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/database_provider.dart';
import '../domain/app_session.dart';
import '../domain/permission_guard.dart';
import '../domain/permissions.dart';
import 'password_hasher.dart';

final accountRecoveryServiceProvider = Provider<AccountRecoveryService>(
  (ref) =>
      AccountRecoveryService(ref.watch(databaseProvider), PasswordHasher()),
);

class RecoveryException implements Exception {
  const RecoveryException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Offline password recovery.
///
/// An owner/admin generates a one-time recovery key and keeps it somewhere
/// safe. Only a PBKDF2 hash of the key is stored. Using the key resets one
/// user's password and consumes the key, so a fresh one must be generated.
class AccountRecoveryService {
  AccountRecoveryService(
    this._database,
    this._hasher, {
    Uuid? uuid,
    Random? random,
  }) : _uuid = uuid ?? const Uuid(),
       _random = random ?? Random.secure();

  final AppDatabase _database;
  final PasswordHasher _hasher;
  final Uuid _uuid;
  final Random _random;

  static const settingHash = 'security.recoveryKeyHash';
  static const settingSalt = 'security.recoveryKeySalt';
  static const settingCreatedAt = 'security.recoveryKeyCreatedAt';

  // Crockford-style alphabet without look-alike characters (0/O, 1/I/L).
  static const _alphabet = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';

  String _newKey() {
    final groups = List.generate(
      5,
      (_) => List.generate(
        4,
        (_) => _alphabet[_random.nextInt(_alphabet.length)],
      ).join(),
    );
    return groups.join('-');
  }

  static String normalize(String key) =>
      key.toUpperCase().replaceAll(RegExp('[^A-Z0-9]'), '');

  Future<String?> _get(String key) async {
    final row = await (_database.select(
      _database.appSettings,
    )..where((r) => r.key.equals(key) & r.storeId.isNull())).getSingleOrNull();
    return row?.value;
  }

  Future<void> _put(String key, String value, DateTime now) async {
    final updated =
        await (_database.update(
          _database.appSettings,
        )..where((r) => r.key.equals(key) & r.storeId.isNull())).write(
          AppSettingsCompanion(value: Value(value), updatedAt: Value(now)),
        );
    if (updated == 0) {
      await _database
          .into(_database.appSettings)
          .insert(
            AppSettingsCompanion.insert(key: key, value: value, updatedAt: now),
          );
    }
  }

  Future<void> _clear() =>
      (_database.delete(_database.appSettings)..where(
            (r) =>
                r.key.isIn([settingHash, settingSalt, settingCreatedAt]) &
                r.storeId.isNull(),
          ))
          .go();

  Future<DateTime?> keyCreatedAt() async {
    final value = await _get(settingCreatedAt);
    return value == null ? null : DateTime.tryParse(value);
  }

  /// Stores a new key inside the caller's transaction (used by setup).
  Future<String> storeNewKey({String? userId, String? storeId}) async {
    final key = _newKey();
    final digest = await _hasher.hash(normalize(key));
    final now = DateTime.now();
    await _put(settingHash, digest.hash, now);
    await _put(settingSalt, digest.salt, now);
    await _put(settingCreatedAt, now.toIso8601String(), now);
    await _database
        .into(_database.auditLogs)
        .insert(
          AuditLogsCompanion.insert(
            id: _uuid.v4(),
            userId: Value(userId),
            storeId: Value(storeId),
            action: 'security.recovery_key_generated',
            entityType: 'app_settings',
            description: 'A new account recovery key was generated.',
            createdAt: now,
          ),
        );
    return key;
  }

  /// Generates a new key, replacing any previous one. Returns it once.
  Future<String> generate(AppSession session) async {
    PermissionGuard.require(session, Permissions.usersManage);
    return _database.transaction(
      () => storeNewKey(userId: session.user.id, storeId: session.store.id),
    );
  }

  /// Resets [username]'s password with the recovery key and consumes the key.
  Future<void> resetPassword({
    required String username,
    required String recoveryKey,
    required String newPassword,
  }) async {
    final hash = await _get(settingHash);
    final salt = await _get(settingSalt);
    if (hash == null || salt == null) {
      throw const RecoveryException(
        'No recovery key has been set up. Ask an owner or admin to reset your password.',
      );
    }
    final valid = await _hasher.verify(
      password: normalize(recoveryKey),
      expectedHash: hash,
      salt: salt,
    );
    if (!valid) throw const RecoveryException('The recovery key is not valid.');
    final user =
        await (_database.select(_database.users)..where(
              (row) => row.username.equals(username.trim().toLowerCase()),
            ))
            .getSingleOrNull();
    if (user == null || !user.isActive) {
      throw const RecoveryException('No active user has that username.');
    }
    final digest = await _hasher.hash(newPassword);
    final now = DateTime.now();
    await _database.transaction(() async {
      await (_database.update(
        _database.users,
      )..where((row) => row.id.equals(user.id))).write(
        UsersCompanion(
          passwordHash: Value(digest.hash),
          passwordSalt: Value(digest.salt),
          updatedAt: Value(now),
        ),
      );
      await _clear();
      await _database
          .into(_database.auditLogs)
          .insert(
            AuditLogsCompanion.insert(
              id: _uuid.v4(),
              userId: Value(user.id),
              action: 'security.password_recovered',
              entityType: 'user',
              entityId: Value(user.id),
              description:
                  'Password for ${user.username} was reset with the recovery key.',
              createdAt: now,
            ),
          );
    });
  }

  /// Lets a signed-in user change their own password.
  Future<void> changeOwnPassword({
    required AppSession session,
    required String currentPassword,
    required String newPassword,
  }) async {
    final user = await (_database.select(
      _database.users,
    )..where((row) => row.id.equals(session.user.id))).getSingle();
    final valid = await _hasher.verify(
      password: currentPassword,
      expectedHash: user.passwordHash,
      salt: user.passwordSalt,
    );
    if (!valid) {
      throw const RecoveryException('Your current password is incorrect.');
    }
    final digest = await _hasher.hash(newPassword);
    final now = DateTime.now();
    await _database.transaction(() async {
      await (_database.update(
        _database.users,
      )..where((row) => row.id.equals(session.user.id))).write(
        UsersCompanion(
          passwordHash: Value(digest.hash),
          passwordSalt: Value(digest.salt),
          updatedAt: Value(now),
        ),
      );
      await _database
          .into(_database.auditLogs)
          .insert(
            AuditLogsCompanion.insert(
              id: _uuid.v4(),
              userId: Value(session.user.id),
              storeId: Value(session.store.id),
              action: 'security.password_changed',
              entityType: 'user',
              entityId: Value(session.user.id),
              description: '${session.user.username} changed their password.',
              createdAt: now,
            ),
          );
    });
  }
}
