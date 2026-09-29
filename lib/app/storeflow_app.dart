import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme/app_theme.dart';
import '../core/theme/theme_controller.dart';
import 'application_gate.dart';
import 'router.dart';

class StoreFlowApp extends ConsumerWidget {
  const StoreFlowApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(themeControllerProvider);
    return MaterialApp.router(
      title: 'StoreFlow POS',
      debugShowCheckedModeBanner: false,
      routerConfig: appRouter,
      themeMode: settings.mode,
      theme: AppTheme.light(settings),
      darkTheme: AppTheme.dark(settings),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(settings.fontScale)),
        child: ApplicationGate(child: child ?? const SizedBox.shrink()),
      ),
    );
  }
}
