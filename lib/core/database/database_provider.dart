import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:talker_flutter/talker_flutter.dart';

import 'app_database.dart';

final databaseProvider = Provider<AppDatabase>(
  (ref) => throw StateError('AppDatabase must be overridden at startup.'),
);

final talkerProvider = Provider<Talker>(
  (ref) => throw StateError('Talker must be overridden at startup.'),
);
