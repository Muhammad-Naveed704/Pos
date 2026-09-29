import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme/app_theme.dart';
import '../core/theme/theme_controller.dart';
import '../core/theme/theme_settings.dart';
import 'application_gate.dart';
import 'router.dart';

class StoreFlowApp extends ConsumerWidget {
  const StoreFlowApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(themeControllerProvider);
    final seed = switch (settings.source) {
      ColorSource.preset => null,
      ColorSource.custom => Color(settings.customSeed),
      ColorSource.windows =>
        ref.watch(windowsAccentProvider).value ?? Color(settings.customSeed),
    };
    return MaterialApp.router(
      title: 'StoreFlow POS',
      debugShowCheckedModeBanner: false,
      routerConfig: appRouter,
      themeMode: settings.mode,
      theme: AppTheme.light(settings, seed: seed),
      darkTheme: AppTheme.dark(settings, seed: seed),
      themeAnimationDuration: Duration(
        milliseconds: (220 * settings.animationLevel.factor).round(),
      ),
      // Font scale is applied once here, through the text scaler, so it also
      // affects widgets that set explicit font sizes.
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(settings.fontScale)),
        child: ApplicationGate(child: child ?? const SizedBox.shrink()),
      ),
    );
  }
}
