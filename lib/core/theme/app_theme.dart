import 'package:flutter/material.dart';

import 'theme_settings.dart';

abstract final class AppTheme {
  static ThemeData light(ThemeSettings settings) => _build(
    settings,
    Brightness.light,
    const Color(0xFFF5F7FA),
    const Color(0xFFFFFFFF),
  );

  static ThemeData dark(ThemeSettings settings) => _build(
    settings,
    Brightness.dark,
    const Color(0xFF0E1116),
    const Color(0xFF171B22),
  );

  static ThemeData _build(
    ThemeSettings settings,
    Brightness brightness,
    Color scaffold,
    Color surface,
  ) {
    final scheme = ColorScheme.fromSeed(
      seedColor: settings.accent,
      brightness: brightness,
      surface: surface,
    );
    final compact = settings.density == AppDensity.compact;
    final radius = BorderRadius.circular(settings.radius);
    final base = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: scaffold,
      fontFamily: settings.fontFamily,
      visualDensity: compact ? VisualDensity.compact : VisualDensity.standard,
    );
    return base.copyWith(
      textTheme: base.textTheme.apply(fontSizeFactor: settings.fontScale),
      cardTheme: CardThemeData(
        elevation: 0,
        color: surface,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: BorderSide(
            color: scheme.outlineVariant.withValues(alpha: 0.55),
          ),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant.withValues(alpha: 0.6),
        thickness: 1,
        space: 1,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        isDense: true,
        border: OutlineInputBorder(
          borderRadius: radius,
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: radius,
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        contentPadding: EdgeInsets.symmetric(
          horizontal: 14,
          vertical: compact ? 10 : 13,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: Size(0, compact ? 36 : 42),
          shape: RoundedRectangleBorder(borderRadius: radius),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: Size(0, compact ? 36 : 42),
          shape: RoundedRectangleBorder(borderRadius: radius),
        ),
      ),
      dataTableTheme: DataTableThemeData(
        headingRowColor: WidgetStatePropertyAll(
          scheme.surfaceContainerHighest.withValues(alpha: 0.55),
        ),
        headingTextStyle: base.textTheme.labelLarge?.copyWith(
          fontWeight: FontWeight.w700,
        ),
        dividerThickness: 0.5,
      ),
      tooltipTheme: TooltipThemeData(
        waitDuration: const Duration(milliseconds: 500),
        decoration: BoxDecoration(
          color: scheme.inverseSurface,
          borderRadius: BorderRadius.circular(6),
        ),
        textStyle: TextStyle(color: scheme.onInverseSurface, fontSize: 12),
      ),
    );
  }
}
