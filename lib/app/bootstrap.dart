import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:talker_flutter/talker_flutter.dart';
import 'package:window_manager/window_manager.dart';

import '../core/database/app_database.dart';
import '../core/database/database_provider.dart';
import '../core/theme/theme_controller.dart';
import '../features/receipts/data/receipt_service.dart';
import '../features/receipts/presentation/printer_picker.dart';
import 'app_host.dart';
import 'storeflow_app.dart';

Future<void> bootstrap() async {
  WidgetsFlutterBinding.ensureInitialized();
  final preferences = await SharedPreferences.getInstance();
  final host = DatabaseHost(
    AppDatabase(),
    openDatabase: AppDatabase.new,
    databaseFile: AppDatabase.databaseFile,
  );
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

  // A restore replaces the database; the new scope starts signed out.
  runApp(
    ListenableBuilder(
      listenable: host,
      builder: (context, _) => ProviderScope(
        key: ValueKey(host.generation),
        overrides: [
          sharedPreferencesProvider.overrideWithValue(preferences),
          databaseProvider.overrideWithValue(host.database),
          databaseHostProvider.overrideWithValue(host),
          talkerProvider.overrideWithValue(talker),
          printerChooserProvider.overrideWithValue(choosePrinter),
        ],
        child: const StoreFlowApp(),
      ),
    ),
  );
}
