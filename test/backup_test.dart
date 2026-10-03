import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqlite3/sqlite3.dart' as sql;
import 'package:storeflow_pos/core/database/app_database.dart';
import 'package:storeflow_pos/features/auth/domain/app_session.dart';
import 'package:storeflow_pos/features/auth/domain/permission_guard.dart';
import 'package:storeflow_pos/features/auth/domain/permissions.dart';
import 'package:storeflow_pos/features/backup/data/backup_service.dart';
import 'package:storeflow_pos/features/products/data/product_repository.dart';

import 'support/storeflow_fixture.dart';

void main() {
  // Restore tests deliberately open several connections to the same file.
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late StoreFlowFixture fixture;
  late AppSession owner;
  late Directory temp;
  late SharedPreferences preferences;

  setUp(() async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({
      'theme.mode': 'dark',
      'session.lastStoreId': 'x',
    });
    preferences = await SharedPreferences.getInstance();
    fixture = StoreFlowFixture();
    owner = await fixture.initialize();
    temp = Directory.systemTemp.createTempSync('storeflow-backup-test-');
    await ProductRepository(fixture.database).save(
      session: owner,
      input: const ProductInput(
        sku: 'TEA',
        name: 'Tea',
        salePrice: 100,
        stockQty: 10,
      ),
    );
  });
  tearDown(() async {
    await fixture.close();
    try {
      temp.deleteSync(recursive: true);
    } catch (_) {}
  });

  BackupService service(AppDatabase database) =>
      BackupService(database, preferences: preferences);

  Future<List<String>> productNames(AppDatabase database) async => [
    for (final product in await database.select(database.products).get())
      product.name,
  ];

  test('creates a verified backup with checksums and metadata', () async {
    final backups = service(fixture.database);
    final result = await backups.create(
      owner,
      destination: Directory(p.join(temp.path, 'out')),
    );
    expect(result.file.existsSync(), isTrue);
    expect(p.basename(result.file.path), matches(backupFileName));
    expect(result.manifest.schemaVersion, fixture.database.schemaVersion);
    expect(result.manifest.stores.single.code, owner.store.code);
    expect(result.sha256, hasLength(64));
    final record = await fixture.database
        .select(fixture.database.backupRecords)
        .getSingle();
    expect(record.status, 'verified');
    expect(record.sha256, result.sha256);

    final archive = ZipDecoder().decodeBytes(result.file.readAsBytesSync());
    final manifest = jsonDecode(
      utf8.decode(archive.findFile('manifest.json')!.content),
    ) as Map<String, dynamic>;
    expect(manifest['format'], 'storeflow-backup');
    final prefs = jsonDecode(
      utf8.decode(archive.findFile('settings/preferences.json')!.content),
    ) as Map<String, dynamic>;
    expect(prefs, {'theme.mode': 'dark'});

    final inspection = await backups.inspect(result.file);
    expect(inspection.manifest.databaseSha256, hasLength(64));
    final copy = AppDatabase(executor: NativeDatabase(inspection.database));
    expect(await productNames(copy), ['Tea']);
    await copy.close();
    inspection.dispose();

    final cashier = AppSession(
      user: owner.user,
      role: owner.role,
      store: owner.store,
      permissions: const {Permissions.posView},
    );
    await expectLater(
      backups.create(cashier, destination: temp),
      throwsA(isA<PermissionDeniedException>()),
    );
  });

  test('rejects damaged files and backups from a newer version', () async {
    final backups = service(fixture.database);
    final result = await backups.create(owner, destination: temp);

    final damaged = File(p.join(temp.path, 'damaged.$backupExtension'));
    final bytes = result.file.readAsBytesSync();
    bytes[bytes.length ~/ 2] ^= 0xFF;
    bytes[bytes.length ~/ 3] ^= 0xFF;
    damaged.writeAsBytesSync(bytes);
    await expectLater(
      backups.inspect(damaged),
      throwsA(isA<BackupException>()),
    );

    final notBackup = File(p.join(temp.path, 'notes.$backupExtension'))
      ..writeAsStringSync('hello');
    await expectLater(
      backups.inspect(notBackup),
      throwsA(isA<BackupException>()),
    );

    // Same content, but the manifest claims a future database version.
    final archive = ZipDecoder().decodeBytes(result.file.readAsBytesSync());
    final manifest = jsonDecode(
      utf8.decode(archive.findFile('manifest.json')!.content),
    ) as Map<String, dynamic>;
    manifest['schemaVersion'] = 99;
    final newer = Archive();
    for (final file in archive.files) {
      newer.addFile(
        file.name == 'manifest.json'
            ? ArchiveFile.string('manifest.json', jsonEncode(manifest))
            : ArchiveFile.bytes(file.name, file.content),
      );
    }
    final future = File(p.join(temp.path, 'future.$backupExtension'))
      ..writeAsBytesSync(ZipEncoder().encodeBytes(newer));
    await expectLater(
      backups.inspect(future),
      throwsA(
        isA<BackupException>().having(
          (e) => e.message,
          'message',
          contains('Update StoreFlow'),
        ),
      ),
    );
  });

  /// A file-based copy of the fixture database, opened like production.
  Future<(AppDatabase, File)> liveCopy() async {
    final file = File(p.join(temp.path, 'live', 'storeflow.sqlite'));
    file.parent.createSync(recursive: true);
    await fixture.database.customStatement('VACUUM INTO ?', [file.path]);
    final database = AppDatabase(executor: NativeDatabase(file));
    await database.customSelect('SELECT 1').get();
    return (database, file);
  }

  test('restores a backup after a safety backup of the current data', () async {
    final backup = await service(fixture.database)
        .create(owner, destination: temp);
    var (live, liveFile) = await liveCopy();
    await ProductRepository(live).save(
      session: owner,
      input: const ProductInput(sku: 'COF', name: 'Coffee', salePrice: 50),
    );
    expect(await productNames(live), containsAll(['Tea', 'Coffee']));
    await preferences.setString('theme.mode', 'light');

    final backups = service(live);
    final inspection = await backups.inspect(backup.file);
    final safetyDir = Directory(p.join(temp.path, 'safety'));
    final restored = await backups.restore(
      owner,
      inspection: inspection,
      liveFile: liveFile,
      closeDatabase: live.close,
      openDatabase: () => AppDatabase(executor: NativeDatabase(liveFile)),
      safetyDirectory: safetyDir,
    );
    inspection.dispose();
    expect(await productNames(restored), ['Tea']);
    expect(preferences.getString('theme.mode'), 'dark');
    final audit = await restored
        .customSelect(
          "SELECT COUNT(*) AS n FROM audit_logs WHERE action = 'backup.restore_completed'",
        )
        .getSingle();
    expect(audit.read<int>('n'), 1);

    // The safety backup holds the data that was replaced.
    final safety = safetyDir.listSync().whereType<File>().single;
    final check = await service(restored).inspect(safety);
    final old = AppDatabase(executor: NativeDatabase(check.database));
    expect(await productNames(old), containsAll(['Tea', 'Coffee']));
    await old.close();
    check.dispose();
    await restored.close();
  });

  test('a failed restore puts the previous data back', () async {
    final backup = await service(fixture.database)
        .create(owner, destination: temp);
    final (live, liveFile) = await liveCopy();
    await ProductRepository(live).save(
      session: owner,
      input: const ProductInput(sku: 'COF', name: 'Coffee', salePrice: 50),
    );
    final backups = service(live);
    final inspection = await backups.inspect(backup.file);
    var opens = 0;
    AppDatabase? reopened;
    try {
      await backups.restore(
        owner,
        inspection: inspection,
        liveFile: liveFile,
        closeDatabase: live.close,
        openDatabase: () {
          opens++;
          if (opens == 1) throw StateError('cannot open');
          return AppDatabase(executor: NativeDatabase(liveFile));
        },
        safetyDirectory: Directory(p.join(temp.path, 'safety')),
      );
      fail('restore should fail');
    } on RestoreFailedException catch (error) {
      reopened = error.database;
      expect(error.message, contains('previous data was kept'));
    }
    inspection.dispose();
    expect(await productNames(reopened), containsAll(['Tea', 'Coffee']));
    expect(
      Directory(p.join(temp.path, 'live'))
          .listSync()
          .map((f) => p.basename(f.path))
          .where((n) => n.contains('rollback')),
      isEmpty,
    );
    await reopened.close();
  });

  test('backups include uncheckpointed WAL writes', () async {
    final (live, liveFile) = await liveCopy();
    final mode = await live.customSelect('PRAGMA journal_mode').getSingle();
    expect(mode.data.values.first, 'wal');
    await ProductRepository(live).save(
      session: owner,
      input: const ProductInput(sku: 'WAL', name: 'Fresh', salePrice: 5),
    );
    expect(File('${liveFile.path}-wal').existsSync(), isTrue);
    final result = await service(live).create(owner, destination: temp);
    final inspection = await service(live).inspect(result.file);
    final copy = sql.sqlite3.open(inspection.database.path);
    final names = copy
        .select('SELECT name FROM products ORDER BY name')
        .map((r) => r['name'])
        .toList();
    copy.close();
    expect(names, ['Fresh', 'Tea']);
    inspection.dispose();
    await live.close();
  });

  test('scheduled backups run when due and keep only the newest', () async {
    final backups = service(fixture.database);
    final folder = Directory(p.join(temp.path, 'scheduled'))..createSync();
    final userFile = File(p.join(folder.path, 'my-notes.txt'))
      ..writeAsStringSync('keep me');
    final lookalike = File(
      p.join(folder.path, 'StoreFlow-MAIN-20200101-000000.storeflowbackup'),
    )..writeAsStringSync('not recorded');
    final settings = BackupSettings(
      directory: folder.path,
      frequency: BackupFrequency.daily,
      retention: 5,
    );
    await backups.saveSettings(owner, settings);
    expect((await backups.loadSettings()).frequency, BackupFrequency.daily);

    expect(await backups.runScheduled(owner), isNotNull);
    expect(await backups.runScheduled(owner), isNull);
    for (var i = 0; i < 6; i++) {
      await backups.create(owner, kind: 'scheduled', system: true);
    }
    expect(await backups.applyRetention(settings), 2);
    final remaining = folder
        .listSync()
        .whereType<File>()
        .where(
          (f) =>
              f.path.endsWith('-scheduled.$backupExtension') ||
              RegExp(r'-scheduled-\d+\.storeflowbackup$').hasMatch(f.path),
        )
        .length;
    expect(remaining, 5);
    expect(userFile.existsSync(), isTrue);
    expect(lookalike.existsSync(), isTrue);

    final cashier = AppSession(
      user: owner.user,
      role: owner.role,
      store: owner.store,
      permissions: const {Permissions.backupCreate},
    );
    await expectLater(
      backups.saveSettings(cashier, settings),
      throwsA(isA<PermissionDeniedException>()),
    );
  });
}
