import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/database_provider.dart';
import '../../auth/domain/app_session.dart';
import '../../auth/domain/permission_guard.dart';
import '../../auth/domain/permissions.dart';

/// "Parent › Child" label for a category (two-level tree).
String categoryPath(Category category, Iterable<Category> all) {
  final parent = category.parentId == null
      ? null
      : all.where((c) => c.id == category.parentId).firstOrNull;
  return parent == null ? category.name : '${parent.name} › ${category.name}';
}

class CategoryException implements Exception {
  const CategoryException(this.message);
  final String message;
  @override
  String toString() => message;
}

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
    final cleanName = name.trim();
    final cleanCode = code.trim().toUpperCase();
    if (cleanName.isEmpty) {
      throw const CategoryException('Enter a category name.');
    }
    if (cleanCode.isEmpty) {
      throw const CategoryException('Enter a short code.');
    }
    if (id != null && parentId == id) {
      throw const CategoryException('A category cannot be its own parent.');
    }
    final categoryId = id ?? _uuid.v4();
    final now = DateTime.now();
    await _database.transaction(() async {
      final all = await _database.select(_database.categories).get();
      final current = all.where((c) => c.id == id).firstOrNull;
      // Two levels: categories, and sub-categories inside them.
      if (parentId != null) {
        final parent = all.where((c) => c.id == parentId).firstOrNull;
        if (parent == null) {
          throw const CategoryException(
            'The chosen category no longer exists.',
          );
        }
        if (parent.parentId != null) {
          throw const CategoryException(
            'Choose a main category; sub-categories cannot have their own '
            'sub-categories.',
          );
        }
        if (id != null && all.any((c) => c.parentId == id)) {
          throw const CategoryException(
            'This category has sub-categories, so it must stay a main category.',
          );
        }
      }
      final sameName = all.where(
        (c) =>
            c.id != id &&
            c.parentId == parentId &&
            c.name.toLowerCase() == cleanName.toLowerCase(),
      );
      if (sameName.isNotEmpty) {
        throw CategoryException(
          parentId == null
              ? 'A category named "$cleanName" already exists.'
              : 'This category already has a sub-category named "$cleanName".',
        );
      }
      if (all.any((c) => c.id != id && c.code.toUpperCase() == cleanCode)) {
        throw CategoryException(
          'The code $cleanCode is already used by another category.',
        );
      }
      await _database
          .into(_database.categories)
          .insertOnConflictUpdate(
            CategoriesCompanion.insert(
              id: categoryId,
              name: cleanName,
              code: cleanCode,
              parentId: Value(parentId),
              isActive: Value(isActive),
              sortOrder: Value(sortOrder),
              createdAt: current?.createdAt ?? now,
              updatedAt: now,
            ),
          );
    });
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
