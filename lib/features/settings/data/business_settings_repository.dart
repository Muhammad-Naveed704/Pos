import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/database_provider.dart';
import '../../../core/money/money_format.dart';
import '../../auth/domain/app_session.dart';
import '../../auth/domain/permission_guard.dart';
import '../../auth/domain/permissions.dart';
import '../domain/business_settings.dart';

final businessSettingsRepositoryProvider = Provider<BusinessSettingsRepository>(
  (ref) => BusinessSettingsRepository(ref.watch(databaseProvider)),
);

/// Live business settings. Every screen that shows money or tax watches this,
/// so a change on the settings page is reflected everywhere immediately.
final businessSettingsProvider = StreamProvider<BusinessSettings>(
  (ref) => ref.watch(businessSettingsRepositoryProvider).watch(),
);

/// Synchronous access with safe defaults while the first value loads.
final currentBusinessSettingsProvider = Provider<BusinessSettings>(
  (ref) =>
      ref.watch(businessSettingsProvider).value ?? const BusinessSettings(),
);

final moneyFormatterProvider = Provider<MoneyFormatter>(
  (ref) => ref.watch(currentBusinessSettingsProvider).formatter,
);

class BusinessSettingsRepository {
  BusinessSettingsRepository(this._database, {Uuid? uuid})
    : _uuid = uuid ?? const Uuid();

  final AppDatabase _database;
  final Uuid _uuid;

  SimpleSelectStatement<$AppSettingsTable, AppSetting> get _globalRows =>
      _database.select(_database.appSettings)
        ..where((row) => row.storeId.isNull());

  Stream<BusinessSettings> watch() => _globalRows.watch().map(_toSettings);

  Future<BusinessSettings> load() => _globalRows.get().then(_toSettings);

  BusinessSettings _toSettings(List<AppSetting> rows) =>
      BusinessSettings.fromMap({for (final row in rows) row.key: row.value});

  /// Saves every changed business setting in one audited transaction.
  Future<void> save(AppSession session, BusinessSettings value) async {
    PermissionGuard.require(session, Permissions.settingsManage);
    if (value.businessName.trim().isEmpty) {
      throw ArgumentError('Business name is required.');
    }
    await _database.transaction(() async {
      final before = {
        for (final row in await _globalRows.get()) row.key: row.value,
      };
      final after = value.toMap();
      final changed = {
        for (final entry in after.entries)
          if (before[entry.key] != entry.value) entry.key: entry.value,
      };
      if (changed.isEmpty) return;
      final now = DateTime.now();
      for (final entry in changed.entries) {
        final updated =
            await (_database.update(_database.appSettings)..where(
                  (row) => row.key.equals(entry.key) & row.storeId.isNull(),
                ))
                .write(
                  AppSettingsCompanion(
                    value: Value(entry.value),
                    updatedAt: Value(now),
                  ),
                );
        if (updated == 0) {
          await _database
              .into(_database.appSettings)
              .insert(
                AppSettingsCompanion.insert(
                  key: entry.key,
                  value: entry.value,
                  updatedAt: now,
                ),
              );
        }
      }
      await _database
          .into(_database.auditLogs)
          .insert(
            AuditLogsCompanion.insert(
              id: _uuid.v4(),
              userId: Value(session.user.id),
              storeId: Value(session.store.id),
              action: 'settings.updated',
              entityType: 'app_settings',
              description: 'Updated ${changed.keys.join(', ')}.',
              oldValueJson: Value(
                jsonEncode({for (final key in changed.keys) key: before[key]}),
              ),
              newValueJson: Value(jsonEncode(changed)),
              createdAt: now,
            ),
          );
    });
  }
}
