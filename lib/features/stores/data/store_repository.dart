import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/database_provider.dart';
import '../../auth/domain/app_session.dart';
import '../../auth/domain/permission_guard.dart';
import '../../auth/domain/permissions.dart';

final storeRepositoryProvider = Provider<StoreRepository>(
  (ref) => StoreRepository(ref.watch(databaseProvider)),
);

class StoreRepository {
  StoreRepository(this._database, {Uuid? uuid}) : _uuid = uuid ?? const Uuid();
  final AppDatabase _database;
  final Uuid _uuid;

  Stream<List<Store>> watchAll() => (_database.select(
    _database.stores,
  )..orderBy([(store) => OrderingTerm.asc(store.name)])).watch();

  Future<String> create({
    required AppSession session,
    required String name,
    required String code,
    String address = '',
    String phone = '',
  }) async {
    PermissionGuard.require(session, Permissions.settingsManage);
    final id = _uuid.v4();
    final now = DateTime.now();
    await _database.transaction(() async {
      await _database
          .into(_database.stores)
          .insert(
            StoresCompanion.insert(
              id: id,
              name: name.trim(),
              code: code.trim().toUpperCase(),
              address: Value(address.trim()),
              phone: Value(phone.trim()),
              createdAt: now,
              updatedAt: now,
            ),
          );
      await _database
          .into(_database.invoiceSequences)
          .insert(
            InvoiceSequencesCompanion.insert(storeId: id, year: now.year),
          );
    });
    return id;
  }

  Future<void> updateStore({
    required AppSession session,
    required Store store,
    required String name,
    required String code,
    required String address,
    required String phone,
    required bool isActive,
  }) async {
    PermissionGuard.require(session, Permissions.settingsManage);
    if (store.id == session.store.id && !isActive) {
      throw StateError('Switch to another store before deactivating this one.');
    }
    await (_database.update(
      _database.stores,
    )..where((row) => row.id.equals(store.id))).write(
      StoresCompanion(
        name: Value(name.trim()),
        code: Value(code.trim().toUpperCase()),
        address: Value(address.trim()),
        phone: Value(phone.trim()),
        isActive: Value(isActive),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }
}
