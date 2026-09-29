import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/database_provider.dart';
import '../../auth/domain/app_session.dart';
import '../../auth/domain/permission_guard.dart';
import '../../auth/domain/permissions.dart';

final categoryRepositoryProvider = Provider<CategoryRepository>(
  (ref) => CategoryRepository(ref.watch(databaseProvider)),
);

class CategoryRepository {
  CategoryRepository(this._database, {Uuid? uuid})
    : _uuid = uuid ?? const Uuid();
  final AppDatabase _database;
  final Uuid _uuid;

  Stream<List<Category>> watch({String search = '', bool? active}) {
    final query = _database.select(_database.categories)
      ..where((row) {
        Expression<bool> condition = const Constant(true);
        if (search.trim().isNotEmpty) {
          condition = condition & row.name.like('%${search.trim()}%');
        }
        if (active != null) condition = condition & row.isActive.equals(active);
        return condition;
      })
      ..orderBy([
        (row) => OrderingTerm.asc(row.sortOrder),
        (row) => OrderingTerm.asc(row.name),
      ]);
    return query.watch();
  }

  Future<String> save({
    required AppSession session,
    String? id,
    required String name,
    required String code,
    String? parentId,
    bool isActive = true,
    int sortOrder = 0,
  }) async {
    PermissionGuard.require(
      session,
      id == null ? Permissions.productsCreate : Permissions.productsEdit,
    );
    if (parentId == id) {
      throw ArgumentError('A category cannot be its own parent.');
    }
    final categoryId = id ?? _uuid.v4();
    final now = DateTime.now();
    await _database
        .into(_database.categories)
        .insertOnConflictUpdate(
          CategoriesCompanion.insert(
            id: categoryId,
            name: name.trim(),
            code: code.trim().toUpperCase(),
            parentId: Value(parentId),
            isActive: Value(isActive),
            sortOrder: Value(sortOrder),
            createdAt: now,
            updatedAt: now,
          ),
        );
    return categoryId;
  }

  Future<void> setActive(AppSession session, String id, bool active) async {
    PermissionGuard.require(session, Permissions.productsDeactivate);
    await (_database.update(
      _database.categories,
    )..where((row) => row.id.equals(id))).write(
      CategoriesCompanion(
        isActive: Value(active),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }
}
