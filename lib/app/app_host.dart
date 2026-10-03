import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/database/app_database.dart';

/// Owns the live database connection so a restore can close it, swap the
/// file and reopen it. Replacing the database rebuilds the whole provider
/// scope, which also signs the user out (sessions are never persisted).
class DatabaseHost extends ChangeNotifier {
  DatabaseHost(
    this._database, {
    required this.openDatabase,
    required this.databaseFile,
  });

  AppDatabase _database;
  int _generation = 0;

  AppDatabase get database => _database;

  /// Changes whenever the database is replaced.
  int get generation => _generation;

  final AppDatabase Function() openDatabase;
  final Future<File> Function() databaseFile;

  void replace(AppDatabase database) {
    _database = database;
    _generation++;
    notifyListeners();
  }
}

/// Null in tests and tools, where restore is not available.
final databaseHostProvider = Provider<DatabaseHost?>((ref) => null);
