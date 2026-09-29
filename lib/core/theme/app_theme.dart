import 'package:flex_color_scheme/flex_color_scheme.dart';
import 'package:flutter/material.dart';

import 'app_tokens.dart';
import 'theme_settings.dart';

abstract final class AppTheme {
  /// [seed] is the resolved custom or Windows accent colour; it is ignored for
  /// [ColorSource.preset].
  static ThemeData light(ThemeSettings settings, {Color? seed}) =>
      _build(settings, Brightness.light, seed);

  static ThemeData dark(ThemeSettings settings, {Color? seed}) =>
      _build(settings, Brightness.dark, seed);

  static ThemeData _build(
    ThemeSettings settings,
    Brightness brightness,
    Color? seed,
  ) {
    final dark = brightness == Brightness.dark;
    final radius = settings.radius;
    final density = switch (settings.density) {
      AppDensity.compact => const VisualDensity(horizontal: -1, vertical: -2),
      AppDensity.comfortable => VisualDensity.standard,
      AppDensity.spacious => VisualDensity.comfortable,
    };
    final gap = switch (settings.density) {
      AppDensity.compact => 6.0,
      AppDensity.comfortable => 8.0,
      AppDensity.spacious => 10.0,
    };
    final inputPadding = switch (settings.density) {
      AppDensity.compact => const EdgeInsets.symmetric(
        horizontal: 12,
        vertical: 10,
      ),
      AppDensity.comfortable => const EdgeInsets.symmetric(
        horizontal: 14,
        vertical: 13,
      ),
      AppDensity.spacious => const EdgeInsets.symmetric(
        horizontal: 16,
        vertical: 17,
      ),
    };

    final useSeed = settings.source != ColorSource.preset && seed != null;
    final subThemes = FlexSubThemesData(
      interactionEffects: true,
      tintedDisabledControls: true,
      blendOnLevel: dark ? 16 : 8,
      useM2StyleDividerInM3: true,
      defaultRadius: radius,
      thinBorderWidth: 1,
      inputDecoratorIsFilled: true,
      inputDecoratorIsDense: settings.density == AppDensity.compact,
      inputDecoratorContentPadding: inputPadding,
      inputDecoratorBorderType: FlexInputBorderType.outline,
      inputDecoratorUnfocusedBorderIsColored: false,
      inputDecoratorBackgroundAlpha: dark ? 0x26 : 0x0D,
      inputDecoratorRadius: radius,
      cardRadius: radius + 2,
      cardElevation: 0,
      dialogRadius: radius + 8,
      filledButtonRadius: radius,
      outlinedButtonRadius: radius,
      elevatedButtonRadius: radius,
      textButtonRadius: radius,
      segmentedButtonRadius: radius,
      chipRadius: radius,
      menuRadius: radius,
      popupMenuRadius: radius,
      tooltipRadius: 6,
      snackBarRadius: radius,
      alignedDropdown: true,
      navigationRailUseIndicator: true,
      navigationRailIndicatorRadius: radius,
    );
    final base = dark
        ? FlexThemeData.dark(
            scheme: useSeed ? null : settings.preset.scheme,
            colors: useSeed ? FlexSchemeColor.from(primary: seed) : null,
            keyColors: useSeed
                ? const FlexKeyColors(useSecondary: true, useTertiary: true)
                : null,
            variant: useSeed ? FlexSchemeVariant.tonalSpot : null,
            surfaceMode: FlexSurfaceMode.levelSurfacesLowScaffold,
            blendLevel: settings.surfaceTint + 4,
            darkIsTrueBlack: settings.pureBlackDark,
            subThemesData: subThemes,
            visualDensity: density,
            fontFamily: settings.fontFamily,
          )
        : FlexThemeData.light(
            scheme: useSeed ? null : settings.preset.scheme,
            colors: useSeed ? FlexSchemeColor.from(primary: seed) : null,
            keyColors: useSeed
                ? const FlexKeyColors(useSecondary: true, useTertiary: true)
                : null,
            variant: useSeed ? FlexSchemeVariant.tonalSpot : null,
            surfaceMode: FlexSurfaceMode.levelSurfacesLowScaffold,
            blendLevel: settings.surfaceTint,
            subThemesData: subThemes,
            visualDensity: density,
            fontFamily: settings.fontFamily,
          );
    final scheme = base.colorScheme;
    final tokens = AppTokens(
      success: dark ? const Color(0xFF4ADE80) : const Color(0xFF15803D),
      onSuccess: dark ? const Color(0xFF052E16) : Colors.white,
      successContainer: dark
          ? const Color(0xFF14532D)
          : const Color(0xFFDCFCE7),
      warning: dark ? const Color(0xFFFBBF24) : const Color(0xFFB45309),
      warningContainer: dark
          ? const Color(0xFF451A03)
          : const Color(0xFFFEF3C7),
      info: dark ? const Color(0xFF60A5FA) : const Color(0xFF1D4ED8),
      infoContainer: dark ? const Color(0xFF172554) : const Color(0xFFDBEAFE),
      radius: radius,
      gap: gap,
      motionFactor: settings.animationLevel.factor,
      sidebar: Color.alphaBlend(
        scheme.primary.withValues(alpha: dark ? 0.06 : 0.035),
        scheme.surfaceContainerLow,
      ),
      chartPalette: [
        scheme.primary,
        scheme.tertiary,
        dark ? const Color(0xFF4ADE80) : const Color(0xFF16A34A),
        dark ? const Color(0xFFFBBF24) : const Color(0xFFD97706),
        scheme.secondary,
        scheme.error,
      ],
    );
    final motion = settings.animationLevel == AppAnimationLevel.reduced;
    return base.copyWith(
      extensions: [tokens],
      pageTransitionsTheme: PageTransitionsTheme(
        builders: {
          for (final platform in TargetPlatform.values)
            platform: motion
                ? const _NoTransitionBuilder()
                : const FadeForwardsPageTransitionsBuilder(),
        },
      ),
      snackBarTheme: base.snackBarTheme.copyWith(
        behavior: SnackBarBehavior.floating,
        width: 440,
      ),
      tooltipTheme: base.tooltipTheme.copyWith(
        waitDuration: const Duration(milliseconds: 450),
      ),
      dataTableTheme: DataTableThemeData(
        headingRowColor: WidgetStatePropertyAll(scheme.surfaceContainerHigh),
        headingTextStyle: base.textTheme.labelLarge?.copyWith(
          fontWeight: FontWeight.w700,
          color: scheme.onSurfaceVariant,
        ),
        dataRowMinHeight: settings.density == AppDensity.compact ? 40 : 52,
        dataRowMaxHeight: settings.density == AppDensity.compact ? 52 : 64,
        dividerThickness: 0.6,
        headingRowHeight: 44,
      ),
      scrollbarTheme: ScrollbarThemeData(
        thickness: const WidgetStatePropertyAll(8),
        radius: const Radius.circular(8),
        thumbColor: WidgetStatePropertyAll(
          scheme.onSurface.withValues(alpha: 0.24),
        ),
      ),
    );
  }
}

class _NoTransitionBuilder extends PageTransitionsBuilder {
  const _NoTransitionBuilder();
  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => child;
}
