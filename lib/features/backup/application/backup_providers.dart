import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/app_host.dart';
import '../../../core/database/database_provider.dart';
import '../../../core/theme/theme_controller.dart';
import '../data/backup_service.dart';

final backupServiceProvider = Provider<BackupService>((ref) {
  final host = ref.watch(databaseHostProvider);
  return BackupService(
    ref.watch(databaseProvider),
    preferences: ref.watch(sharedPreferencesProvider),
    liveDatabaseFile: host?.databaseFile,
  );
});
