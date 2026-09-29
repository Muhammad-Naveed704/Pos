import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:talker_flutter/talker_flutter.dart';
import 'package:window_manager/window_manager.dart';

import '../core/database/app_database.dart';
import '../core/database/database_provider.dart';
import '../core/theme/theme_controller.dart';
import 'storeflow_app.dart';

Future<void> bootstrap() async {
  WidgetsFlutterBinding.ensureInitialized();
  final preferences = await SharedPreferences.getInstance();
  final database = AppDatabase();
  final talker = TalkerFlutter.init();

  await windowManager.ensureInitialized();
  await windowManager.waitUntilReadyToShow(
    const WindowOptions(
      size: Size(1440, 900),
      minimumSize: Size(1100, 700),
      center: true,
      title: 'StoreFlow POS',
      backgroundColor: Colors.transparent,
    ),
    () async {
      await windowManager.show();
      await windowManager.focus();
    },
  );

  FlutterError.onError = (details) {
    talker.handle(details.exception, details.stack);
    FlutterError.presentError(details);
  };

  runApp(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(preferences),
        databaseProvider.overrideWithValue(database),
        talkerProvider.overrideWithValue(talker),
      ],
      child: const StoreFlowApp(),
    ),
  );
}
