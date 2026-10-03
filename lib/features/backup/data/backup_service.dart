import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqlite3/sqlite3.dart' as sql;
import 'package:uuid/uuid.dart';

import '../../../app/app_info.dart';
import '../../../core/database/app_database.dart';
import '../../auth/domain/app_session.dart';
import '../../auth/domain/permission_guard.dart';
import '../../auth/domain/permissions.dart';

class BackupException implements Exception {
  const BackupException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Backup file extension (a zip archive with a checksummed manifest).
const backupExtension = 'storeflowbackup';
const _format = 'storeflow-backup';
const _formatVersion = 1;
const _dbEntry = 'database/storeflow.sqlite';
const _prefsEntry = 'settings/preferences.json';
const _manifestEntry = 'manifest.json';

/// Per-PC preferences included in backups (theme, printer, layout).
const _prefPrefixes = ['theme.', 'receipt.', 'shell.'];

/// Only files named like this, in the configured folder, are ever deleted
/// by retention.
final backupFileName = RegExp(
  r'^StoreFlow-[A-Za-z0-9_-]+-\d{8}-\d{6}(-[a-z]+)?(-\d+)?\.storeflowbackup$',
);

enum BackupFrequency {
  off('Disabled', null),
  daily('Daily', Duration(days: 1)),
  weekly('Weekly', Duration(days: 7)),
  monthly('Monthly', Duration(days: 30));

  const BackupFrequency(this.label, this.interval);
  final String label;
  final Duration? interval;
}

class BackupSettings {
  const BackupSettings({
    this.directory,
    this.frequency = BackupFrequency.off,
    this.retention = 10,
    this.beforeRiskyOperations = true,
  });
  final String? directory;
  final BackupFrequency frequency;

  /// Scheduled backups to keep (5, 10 or 20).
  final int retention;

  /// Create a safety backup before restore and bulk imports.
  final bool beforeRiskyOperations;

  BackupSettings copyWith({
    String? directory,
    BackupFrequency? frequency,
    int? retention,
    bool? beforeRiskyOperations,
  }) => BackupSettings(
    directory: directory ?? this.directory,
    frequency: frequency ?? this.frequency,
    retention: retention ?? this.retention,
    beforeRiskyOperations: beforeRiskyOperations ?? this.beforeRiskyOperations,
  );
}

class BackupStoreInfo {
  const BackupStoreInfo(this.code, this.name);
  final String code;
  final String name;
}

class BackupManifest {
  const BackupManifest({
    required this.appVersion,
    required this.schemaVersion,
    required this.createdAt,
    required this.createdBy,
    required this.kind,
    required this.stores,
    required this.databaseSha256,
    required this.databaseSize,
    required this.assetCount,
  });
  final String appVersion;
  final int schemaVersion;
  final DateTime createdAt;
  final String createdBy;
  final String kind;
  final List<BackupStoreInfo> stores;
  final String databaseSha256;
  final int databaseSize;
  final int assetCount;

  static BackupManifest fromJson(Map<String, dynamic> json) => BackupManifest(
    appVersion: json['appVersion'] as String? ?? '?',
    schemaVersion: json['schemaVersion'] as int,
    createdAt: DateTime.parse(json['createdAt'] as String),
    createdBy: json['createdBy'] as String? ?? '',
    kind: json['kind'] as String? ?? 'manual',
    stores: [
      for (final store in (json['stores'] as List? ?? const []))
        BackupStoreInfo(
          (store as Map)['code'] as String,
          store['name'] as String,
        ),
    ],
    databaseSha256: (json['files'] as Map)[_dbEntry]['sha256'] as String,
    databaseSize: (json['files'] as Map)[_dbEntry]['size'] as int,
    assetCount: (json['assets'] as List? ?? const []).length,
  );
}

class BackupResult {
  const BackupResult(this.file, this.sizeBytes, this.sha256, this.manifest);
  final File file;
  final int sizeBytes;

  /// Checksum of the whole backup file.
  final String sha256;
  final BackupManifest manifest;
}

/// A backup file that passed every check, extracted and ready to restore.
class BackupInspection {
  const BackupInspection(this.file, this.manifest, this._workDir);
  final File file;
  final BackupManifest manifest;
  final Directory _workDir;

  File get database => File(p.join(_workDir.path, 'storeflow.sqlite'));
  File get preferences => File(p.join(_workDir.path, 'preferences.json'));
  Directory get assets => Directory(p.join(_workDir.path, 'assets'));
  File get assetMap => File(p.join(_workDir.path, 'assets.json'));

  void dispose() {
    try {
      if (_workDir.existsSync()) _workDir.deleteSync(recursive: true);
    } catch (_) {}
  }
}

class BackupStatus {
  const BackupStatus({
    required this.databasePath,
    required this.databaseSize,
    required this.settings,
    required this.stores,
    this.lastBackup,
    this.recent = const [],
  });
  final String? databasePath;
  final int databaseSize;
  final BackupSettings settings;
  final List<BackupStoreInfo> stores;
  final BackupRecord? lastBackup;
  final List<BackupRecord> recent;
}

/// Creates, verifies and restores backups.
///
/// Backups are taken with `VACUUM INTO`, which copies a consistent snapshot
/// inside a read transaction (WAL-aware, safe while the app keeps writing).
/// The snapshot is integrity-checked, packed with a SHA-256 manifest, and
/// the written file is re-read and verified before it is recorded.
class BackupService {
  BackupService(
    this._database, {
    this._preferences,
    Uuid? uuid,
    this._liveDatabaseFile,
  }) : _uuid = uuid ?? const Uuid();

  final AppDatabase _database;
  final SharedPreferences? _preferences;
  final Uuid _uuid;
  final Future<File> Function()? _liveDatabaseFile;

  static const _keys = (
    directory: 'backup.directory',
    frequency: 'backup.frequency',
    retention: 'backup.retention',
    beforeRisky: 'backup.beforeRiskyOperations',
  );

  // ---------------------------------------------------------------- settings

  Future<BackupSettings> loadSettings() async {
    final rows = await (_database.select(
      _database.appSettings,
    )..where((r) => r.key.like('backup.%') & r.storeId.isNull())).get();
    final values = {for (final row in rows) row.key: row.value};
    final retention = int.tryParse(values[_keys.retention] ?? '') ?? 10;
    return BackupSettings(
      directory: (values[_keys.directory]?.trim().isEmpty ?? true)
          ? null
          : values[_keys.directory],
      frequency:
          BackupFrequency.values
              .where((f) => f.name == values[_keys.frequency])
              .firstOrNull ??
          BackupFrequency.off,
      retention: const [5, 10, 20].contains(retention) ? retention : 10,
      beforeRiskyOperations: values[_keys.beforeRisky] != 'false',
    );
  }

  Future<void> saveSettings(AppSession session, BackupSettings value) async {
    PermissionGuard.require(session, Permissions.backupSettings);
    if (!const [5, 10, 20].contains(value.retention)) {
      throw const BackupException('Keep 5, 10 or 20 backups.');
    }
    final directory = value.directory?.trim();
    if (directory != null && directory.isNotEmpty) {
      final dir = Directory(directory);
      try {
        if (!dir.existsSync()) dir.createSync(recursive: true);
      } catch (_) {
        throw BackupException('The folder $directory cannot be created.');
      }
    }
    final now = DateTime.now();
    await _database.transaction(() async {
      final entries = {
        _keys.directory: directory ?? '',
        _keys.frequency: value.frequency.name,
        _keys.retention: '${value.retention}',
        _keys.beforeRisky: '${value.beforeRiskyOperations}',
      };
      for (final MapEntry(:key, value: text) in entries.entries) {
        final updated =
            await (_database.update(
              _database.appSettings,
            )..where((r) => r.key.equals(key) & r.storeId.isNull())).write(
              AppSettingsCompanion(value: Value(text), updatedAt: Value(now)),
            );
        if (updated == 0) {
          await _database
              .into(_database.appSettings)
              .insert(
                AppSettingsCompanion.insert(
                  key: key,
                  value: text,
                  updatedAt: now,
                ),
              );
        }
      }
      await _audit(
        session.user.id,
        session.store.id,
        'backup.settings_updated',
        'Backup schedule: ${value.frequency.label}, keep ${value.retention}.',
        {
          'directory': directory,
          'frequency': value.frequency.name,
          'retention': value.retention,
          'beforeRiskyOperations': value.beforeRiskyOperations,
        },
      );
    });
  }

  /// Folder used when none is configured: Documents\StoreFlow Backups.
  static Future<Directory> defaultDirectory() async {
    final documents = await getApplicationDocumentsDirectory();
    return Directory(p.join(documents.path, 'StoreFlow Backups'));
  }

  /// Safety backups made before restores and imports.
  static Future<Directory> safetyDirectory() async {
    final support = await getApplicationSupportDirectory();
    return Directory(p.join(support.path, 'StoreFlow POS', 'safety-backups'));
  }

  Future<Directory> resolveDirectory(BackupSettings settings) async =>
      settings.directory == null
      ? await defaultDirectory()
      : Directory(settings.directory!);

  Future<BackupStatus> status(AppSession session) async {
    final settings = await loadSettings();
    File? live;
    try {
      live = await _liveDatabaseFile?.call();
    } catch (_) {}
    var size = 0;
    if (live != null && live.existsSync()) {
      size = live.lengthSync();
      final wal = File('${live.path}-wal');
      if (wal.existsSync()) size += wal.lengthSync();
    }
    final recent =
        await (_database.select(_database.backupRecords)
              ..orderBy([
                (r) => OrderingTerm.desc(r.createdAt),
                (r) => OrderingTerm.desc(r.rowId),
              ])
              ..limit(20))
            .get();
    return BackupStatus(
      databasePath: live?.path,
      databaseSize: size,
      settings: settings,
      stores: await _stores(),
      lastBackup: recent.where((r) => r.status == 'verified').firstOrNull,
      recent: recent,
    );
  }

  Future<List<BackupStoreInfo>> _stores() async => [
    for (final store in await (_database.select(
      _database.stores,
    )..orderBy([(s) => OrderingTerm.asc(s.code)])).get())
      BackupStoreInfo(store.code, store.name),
  ];

  // ------------------------------------------------------------------ create

  /// Creates and verifies a backup in [destination] (default: the configured
  /// folder). [system] backups (scheduled / safety) skip the permission
  /// check because the user did not start them.
  Future<BackupResult> create(
    AppSession session, {
    Directory? destination,
    String kind = 'manual',
    String note = '',
    bool system = false,
  }) async {
    if (!system) PermissionGuard.require(session, Permissions.backupCreate);
    final settings = await loadSettings();
    final target = destination ?? await resolveDirectory(settings);
    final now = DateTime.now();
    final stamp = DateFormat('yyyyMMdd-HHmmss').format(now);
    final base =
        'StoreFlow-${_safe(session.store.code)}-$stamp${kind == 'manual' ? '' : '-$kind'}';
    var file = File(p.join(target.path, '$base.$backupExtension'));
    // Never overwrite an earlier backup made in the same second.
    for (
      var n = 2;
      file.existsSync() || File('${file.path}.part').existsSync();
      n++
    ) {
      file = File(p.join(target.path, '$base-$n.$backupExtension'));
    }
    final work = Directory(
      p.join(Directory.systemTemp.path, 'storeflow-backup-${_uuid.v4()}'),
    );
    try {
      try {
        target.createSync(recursive: true);
      } catch (_) {
        throw BackupException(
          'The backup folder ${target.path} cannot be created.',
        );
      }
      work.createSync(recursive: true);
      final snapshot = File(p.join(work.path, 'snapshot.sqlite'));
      // Consistent copy of the live database, including WAL content.
      await _database.customStatement('VACUUM INTO ?', [snapshot.path]);

      final assets = await _assetPaths();
      final prefs = <String, Object?>{};
      final preferences = _preferences;
      if (preferences != null) {
        for (final key in preferences.getKeys()) {
          if (_prefPrefixes.any(key.startsWith)) {
            prefs[key] = preferences.get(key);
          }
        }
      }
      final manifest = <String, Object?>{
        'format': _format,
        'formatVersion': _formatVersion,
        'appVersion': AppInfo.appVersion,
        'schemaVersion': _database.schemaVersion,
        'createdAt': now.toIso8601String(),
        'createdBy': session.user.username,
        'kind': kind,
        'note': note,
        'stores': [
          for (final store in await _stores())
            {'code': store.code, 'name': store.name},
        ],
      };
      final partPath = '${file.path}.part';
      final job = _PackJob(
        snapshotPath: snapshot.path,
        outputPath: partPath,
        manifest: manifest,
        preferencesJson: jsonEncode(prefs),
        assets: assets,
        expectedSchema: _database.schemaVersion,
      );
      await _runPack(job);
      // Read the written file back exactly as a restore would.
      final verify = Directory(p.join(work.path, 'verify'));
      final checked = await _runInspect(
        partPath,
        verify.path,
        job.expectedSchema,
      );
      final sha = await _fileSha256(File(partPath));
      File(partPath).renameSync(file.path);
      final size = file.lengthSync();
      await _database.transaction(() async {
        await _database
            .into(_database.backupRecords)
            .insert(
              BackupRecordsCompanion.insert(
                id: _uuid.v4(),
                filePath: file.path,
                sha256: sha,
                sizeBytes: size,
                status: 'verified',
                createdAt: now,
                kind: Value(kind),
                note: Value(note),
              ),
            );
        await _audit(
          session.user.id,
          session.store.id,
          'backup.created',
          'Backup ${p.basename(file.path)} ($kind) created and verified.',
          {'file': file.path, 'sizeBytes': size, 'sha256': sha, 'kind': kind},
        );
      });
      return BackupResult(file, size, sha, BackupManifest.fromJson(checked));
    } catch (error) {
      try {
        final part = File('${file.path}.part');
        if (part.existsSync()) part.deleteSync();
      } catch (_) {}
      try {
        await _database
            .into(_database.backupRecords)
            .insert(
              BackupRecordsCompanion.insert(
                id: _uuid.v4(),
                filePath: file.path,
                sha256: '',
                sizeBytes: 0,
                status: 'failed',
                createdAt: now,
                kind: Value(kind),
                note: Value('$error'),
              ),
            );
      } catch (_) {}
      if (error is BackupException) rethrow;
      throw BackupException('Backup failed: $error');
    } finally {
      try {
        if (work.existsSync()) work.deleteSync(recursive: true);
      } catch (_) {}
    }
  }

  Future<List<String>> _assetPaths() async {
    final paths = <String>{};
    final rows = await _database
        .customSelect(
          "SELECT image_path AS path FROM products WHERE image_path IS NOT NULL AND image_path <> '' "
          "UNION SELECT value AS path FROM app_settings WHERE key = 'receipt.logoPath' AND value <> ''",
        )
        .get();
    for (final row in rows) {
      final path = row.read<String>('path');
      if (File(path).existsSync()) paths.add(path);
    }
    return paths.toList();
  }

  // ------------------------------------------------------------------ verify

  /// Validates a backup file (format, checksums, schema, SQLite integrity)
  /// and extracts it. Call [BackupInspection.dispose] when done.
  Future<BackupInspection> inspect(File file) async {
    if (!file.existsSync()) {
      throw const BackupException('The backup file does not exist.');
    }
    final work = Directory(
      p.join(Directory.systemTemp.path, 'storeflow-restore-${_uuid.v4()}'),
    );
    try {
      final schema = _database.schemaVersion;
      final manifest = await _runInspect(file.path, work.path, schema);
      return BackupInspection(file, BackupManifest.fromJson(manifest), work);
    } catch (error) {
      try {
        if (work.existsSync()) work.deleteSync(recursive: true);
      } catch (_) {}
      if (error is BackupException) rethrow;
      throw BackupException(
        'This file is not a valid StoreFlow backup ($error).',
      );
    }
  }

  Future<BackupManifest> verify(AppSession session, File file) async {
    PermissionGuard.require(session, Permissions.backupCreate);
    final inspection = await inspect(file);
    inspection.dispose();
    return inspection.manifest;
  }

  // ----------------------------------------------------------------- restore

  /// Replaces the live database with [inspection].
  ///
  /// 1. safety backup of the current data (must succeed),
  /// 2. [closeDatabase], move the live files aside,
  /// 3. copy the backup in and [openDatabase] (runs migrations),
  /// 4. integrity check; on any failure the previous files are put back and
  ///    reopened, so the shop never ends up without data.
  ///
  /// Returns the newly opened database. The caller must stop using this
  /// service's database afterwards.
  Future<AppDatabase> restore(
    AppSession session, {
    required BackupInspection inspection,
    required File liveFile,
    required Future<void> Function() closeDatabase,
    required AppDatabase Function() openDatabase,
    Directory? safetyDirectory,
  }) async {
    PermissionGuard.require(session, Permissions.backupRestore);
    if (!inspection.database.existsSync()) {
      throw const BackupException('The backup has not been extracted.');
    }
    final safety = await create(
      session,
      destination: safetyDirectory ?? await BackupService.safetyDirectory(),
      kind: 'safety',
      note: 'Before restoring ${p.basename(inspection.file.path)}',
      system: true,
    );
    await _audit(
      session.user.id,
      session.store.id,
      'backup.restore_attempted',
      'Restore of ${p.basename(inspection.file.path)} started.',
      {
        'file': inspection.file.path,
        'backupCreatedAt': inspection.manifest.createdAt.toIso8601String(),
        'safetyBackup': safety.file.path,
      },
    );
    await closeDatabase();

    final suffixes = ['', '-wal', '-shm', '-journal'];
    final moved = <String>[];
    final stamp = DateTime.now().millisecondsSinceEpoch;
    AppDatabase? restored;
    try {
      for (final suffix in suffixes) {
        final source = File('${liveFile.path}$suffix');
        if (source.existsSync()) {
          source.renameSync('${liveFile.path}.rollback-$stamp$suffix');
          moved.add(suffix);
        }
      }
      inspection.database.copySync(liveFile.path);
      restored = openDatabase();
      final check = await restored
          .customSelect('PRAGMA integrity_check')
          .getSingle();
      if (check.data.values.first != 'ok') {
        throw BackupException(
          'Integrity check failed: ${check.data.values.first}',
        );
      }
      final stores = await restored
          .customSelect('SELECT COUNT(*) AS n FROM stores')
          .getSingle();
      if (stores.read<int>('n') == 0) {
        throw const BackupException('The restored data has no stores.');
      }
    } catch (error) {
      try {
        await restored?.close();
      } catch (_) {}
      for (final suffix in suffixes) {
        final current = File('${liveFile.path}$suffix');
        if (current.existsSync()) current.deleteSync();
      }
      for (final suffix in moved) {
        File('${liveFile.path}.rollback-$stamp$suffix')
            .renameSync('${liveFile.path}$suffix');
      }
      final previous = openDatabase();
      await BackupService(previous)._audit(
        session.user.id,
        session.store.id,
        'backup.restore_failed',
        'Restore failed and the previous data was kept: $error',
        {'file': inspection.file.path},
      );
      throw BackupException(
        'Restore failed and your previous data was kept. ($error)\n'
        'Safety backup: ${safety.file.path}',
      )._withDatabase(previous);
    }

    for (final suffix in moved) {
      try {
        File('${liveFile.path}.rollback-$stamp$suffix').deleteSync();
      } catch (_) {}
    }
    await _restoreExtras(inspection);
    final users = await restored
        .customSelect(
          'SELECT COUNT(*) AS n FROM users WHERE id = ?',
          variables: [Variable.withString(session.user.id)],
        )
        .getSingle();
    final stores = await restored
        .customSelect(
          'SELECT COUNT(*) AS n FROM stores WHERE id = ?',
          variables: [Variable.withString(session.store.id)],
        )
        .getSingle();
    await BackupService(restored)._audit(
      users.read<int>('n') > 0 ? session.user.id : null,
      stores.read<int>('n') > 0 ? session.store.id : null,
      'backup.restore_completed',
      'Data restored from ${p.basename(inspection.file.path)} by ${session.user.username}.',
      {
        'file': inspection.file.path,
        'backupCreatedAt': inspection.manifest.createdAt.toIso8601String(),
        'backupSchema': inspection.manifest.schemaVersion,
        'safetyBackup': safety.file.path,
      },
    );
    return restored;
  }

  Future<void> _restoreExtras(BackupInspection inspection) async {
    final preferences = _preferences;
    if (preferences != null && inspection.preferences.existsSync()) {
      final values = jsonDecode(
        inspection.preferences.readAsStringSync(),
      ) as Map<String, dynamic>;
      for (final MapEntry(:key, :value) in values.entries) {
        if (!_prefPrefixes.any(key.startsWith)) continue;
        switch (value) {
          case bool v:
            await preferences.setBool(key, v);
          case int v:
            await preferences.setInt(key, v);
          case double v:
            await preferences.setDouble(key, v);
          case String v:
            await preferences.setString(key, v);
          case List v:
            await preferences.setStringList(key, v.cast<String>());
        }
      }
    }
    // Logos and product images go back to their original paths when those
    // are free; existing files are never overwritten.
    if (inspection.assetMap.existsSync()) {
      final map = jsonDecode(
        inspection.assetMap.readAsStringSync(),
      ) as Map<String, dynamic>;
      for (final MapEntry(:key, :value) in map.entries) {
        final source = File(p.join(inspection.assets.path, key));
        final target = File(value as String);
        try {
          if (source.existsSync() && !target.existsSync()) {
            target.parent.createSync(recursive: true);
            source.copySync(target.path);
          }
        } catch (_) {}
      }
    }
  }

  // -------------------------------------------------------------- scheduling

  /// Runs a scheduled backup when one is due, then applies retention.
  /// Returns the new backup, or null when nothing was due.
  Future<BackupResult?> runScheduled(
    AppSession session, {
    DateTime? now,
  }) async {
    final settings = await loadSettings();
    final interval = settings.frequency.interval;
    if (interval == null) return null;
    final last =
        await (_database.select(_database.backupRecords)
              ..where(
                (r) => r.status.equals('verified') & r.kind.equals('scheduled'),
              )
              ..orderBy([(r) => OrderingTerm.desc(r.createdAt)])
              ..limit(1))
            .getSingleOrNull();
    final at = now ?? DateTime.now();
    // A little slack so "daily" does not drift later every day.
    if (last != null &&
        at.difference(last.createdAt) < interval - const Duration(hours: 1)) {
      return null;
    }
    final result = await create(session, kind: 'scheduled', system: true);
    await applyRetention(settings);
    return result;
  }

  /// Deletes scheduled backups beyond the retention count. Only files that
  /// StoreFlow created (recorded, named like a backup, in the backup folder)
  /// are ever deleted.
  Future<int> applyRetention(BackupSettings settings) async {
    final folder = p.normalize(
      (await resolveDirectory(settings)).absolute.path,
    );
    final records =
        await (_database.select(_database.backupRecords)
              ..where(
                (r) => r.status.equals('verified') & r.kind.equals('scheduled'),
              )
              ..orderBy([
                (r) => OrderingTerm.desc(r.createdAt),
                (r) => OrderingTerm.desc(r.rowId),
              ]))
            .get();
    var deleted = 0;
    for (final record in records.skip(settings.retention)) {
      final file = File(record.filePath);
      final inFolder = p.equals(p.normalize(file.parent.absolute.path), folder);
      if (inFolder &&
          backupFileName.hasMatch(p.basename(file.path)) &&
          file.existsSync()) {
        try {
          file.deleteSync();
          deleted++;
        } catch (_) {
          continue;
        }
      }
      await (_database.update(_database.backupRecords)
            ..where((r) => r.id.equals(record.id)))
          .write(const BackupRecordsCompanion(status: Value('pruned')));
    }
    return deleted;
  }

  /// Safety backup before a risky operation (bulk import), if enabled.
  Future<BackupResult?> beforeRiskyOperation(
    AppSession session,
    String operation,
  ) async {
    final settings = await loadSettings();
    if (!settings.beforeRiskyOperations) return null;
    return create(
      session,
      destination: await BackupService.safetyDirectory(),
      kind: 'safety',
      note: 'Before $operation',
      system: true,
    );
  }

  // ----------------------------------------------------------------- helpers

  static String _safe(String value) =>
      value.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');

  static Future<String> _fileSha256(File file) async =>
      (await sha256.bind(file.openRead()).first).toString();

  Future<void> _audit(
    String? userId,
    String? storeId,
    String action,
    String description,
    Map<String, Object?> data,
  ) => _database
      .into(_database.auditLogs)
      .insert(
        AuditLogsCompanion.insert(
          id: _uuid.v4(),
          userId: Value(userId),
          storeId: Value(storeId),
          action: action,
          entityType: 'backup',
          description: description,
          newValueJson: Value(jsonEncode(data)),
          createdAt: DateTime.now(),
        ),
      );
}

extension on BackupException {
  BackupException _withDatabase(AppDatabase database) =>
      RestoreFailedException(message, database);
}

/// Restore failed and the previous data was reopened as [database].
class RestoreFailedException extends BackupException {
  const RestoreFailedException(super.message, this.database);
  final AppDatabase database;
}

class _PackJob {
  const _PackJob({
    required this.snapshotPath,
    required this.outputPath,
    required this.manifest,
    required this.preferencesJson,
    required this.assets,
    required this.expectedSchema,
  });
  final String snapshotPath;
  final String outputPath;
  final Map<String, Object?> manifest;
  final String preferencesJson;
  final List<String> assets;
  final int expectedSchema;
}

// Isolate entry points live at top level so their closures capture only
// their arguments (never the database connection).
Future<void> _runPack(_PackJob job) => Isolate.run(() => _pack(job));

Future<Map<String, dynamic>> _runInspect(String path, String dir, int schema) =>
    Isolate.run(() => _inspect(path, dir, schema));

String _sha(List<int> bytes) => sha256.convert(bytes).toString();

/// Runs off the UI isolate: checks the snapshot and writes the archive.
void _pack(_PackJob job) {
  final check = _checkSqlite(job.snapshotPath);
  if (check.schema != job.expectedSchema) {
    throw BackupException(
      'Snapshot schema ${check.schema} does not match ${job.expectedSchema}.',
    );
  }
  final db = File(job.snapshotPath).readAsBytesSync();
  final prefs = utf8.encode(job.preferencesJson);
  final archive = Archive()
    ..addFile(ArchiveFile.bytes(_dbEntry, db))
    ..addFile(ArchiveFile.bytes(_prefsEntry, prefs));
  final files = <String, Object?>{
    _dbEntry: {'sha256': _sha(db), 'size': db.length},
    _prefsEntry: {'sha256': _sha(prefs), 'size': prefs.length},
  };
  final assets = <Map<String, Object?>>[];
  for (var i = 0; i < job.assets.length; i++) {
    final source = File(job.assets[i]);
    final bytes = source.readAsBytesSync();
    final entry = 'assets/$i-${p.basename(source.path)}';
    archive.addFile(ArchiveFile.bytes(entry, bytes));
    files[entry] = {'sha256': _sha(bytes), 'size': bytes.length};
    assets.add({'entry': entry, 'path': source.path});
  }
  final manifest = {
    ...job.manifest,
    'files': files,
    'assets': assets,
    'integrity': check.integrity,
  };
  archive.addFile(
    ArchiveFile.string(
      _manifestEntry,
      const JsonEncoder.withIndent('  ').convert(manifest),
    ),
  );
  final out = File(job.outputPath);
  out.writeAsBytesSync(ZipEncoder().encodeBytes(archive), flush: true);
}

/// Runs off the UI isolate: validates an archive and extracts it to [dir].
Map<String, dynamic> _inspect(String path, String dir, int currentSchema) {
  final Archive archive;
  try {
    archive = ZipDecoder().decodeBytes(
      File(path).readAsBytesSync(),
      verify: true,
    );
  } catch (_) {
    throw const BackupException(
      'The file is damaged or is not a StoreFlow backup.',
    );
  }
  final manifestFile = archive.findFile(_manifestEntry);
  if (manifestFile == null) {
    throw const BackupException(
      'The backup has no manifest; it is not a StoreFlow backup.',
    );
  }
  final Map<String, dynamic> manifest;
  try {
    manifest =
        jsonDecode(utf8.decode(manifestFile.content)) as Map<String, dynamic>;
  } catch (_) {
    throw const BackupException('The backup manifest is damaged.');
  }
  if (manifest['format'] != _format) {
    throw const BackupException('This file is not a StoreFlow backup.');
  }
  if ((manifest['formatVersion'] as int? ?? 99) > _formatVersion) {
    throw const BackupException(
      'This backup was made by a newer StoreFlow version. Update the app first.',
    );
  }
  final schema = manifest['schemaVersion'] as int? ?? 0;
  if (schema > currentSchema) {
    throw BackupException(
      'This backup uses database version $schema, but this app supports up to '
      '$currentSchema. Update StoreFlow before restoring it.',
    );
  }
  if (schema < 1) throw const BackupException('Unknown database version.');
  final files = manifest['files'] as Map<String, dynamic>? ?? const {};
  if (!files.containsKey(_dbEntry)) {
    throw const BackupException('The backup does not contain a database.');
  }
  final work = Directory(dir)..createSync(recursive: true);
  final assetMap = <String, String>{};
  for (final MapEntry(:key, :value) in files.entries) {
    final entry = archive.findFile(key);
    if (entry == null) {
      throw BackupException('The backup is incomplete ($key is missing).');
    }
    final bytes = entry.content;
    final info = value as Map<String, dynamic>;
    if (bytes.length != info['size'] || _sha(bytes) != info['sha256']) {
      throw BackupException(
        'Checksum mismatch for $key: the backup is damaged.',
      );
    }
    if (key == _dbEntry) {
      File(p.join(work.path, 'storeflow.sqlite')).writeAsBytesSync(bytes);
    } else if (key == _prefsEntry) {
      File(p.join(work.path, 'preferences.json')).writeAsBytesSync(bytes);
    } else if (key.startsWith('assets/')) {
      final name = key.substring('assets/'.length);
      if (name.contains('/') || name.contains('\\') || name.contains('..')) {
        continue;
      }
      File(p.join(work.path, 'assets', name))
        ..createSync(recursive: true)
        ..writeAsBytesSync(bytes);
      final original = (manifest['assets'] as List? ?? const [])
          .cast<Map<String, dynamic>>()
          .where((a) => a['entry'] == key)
          .firstOrNull;
      if (original != null) assetMap[name] = original['path'] as String;
    }
  }
  File(p.join(work.path, 'assets.json'))
      .writeAsStringSync(jsonEncode(assetMap));
  final check = _checkSqlite(p.join(work.path, 'storeflow.sqlite'));
  if (check.integrity != 'ok') {
    throw BackupException('The backed-up database failed its integrity check.');
  }
  if (check.schema != schema) {
    throw const BackupException(
      'The backup manifest does not match its database.',
    );
  }
  return manifest;
}

({String integrity, int schema}) _checkSqlite(String path) {
  final db = sql.sqlite3.open(path, mode: sql.OpenMode.readOnly);
  try {
    final integrity = db.select('PRAGMA integrity_check').first.values.first;
    final schema = db.select('PRAGMA user_version').first.values.first as int;
    db.select('SELECT COUNT(*) FROM stores');
    return (integrity: '$integrity', schema: schema);
  } on sql.SqliteException catch (error) {
    throw BackupException('The database could not be read: ${error.message}');
  } finally {
    db.close();
  }
}
