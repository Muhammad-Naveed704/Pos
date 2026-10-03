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
      // VisualDensity.comfortable is denser than standard; touch needs more.
      AppDensity.spacious => const VisualDensity(horizontal: 0, vertical: 1),
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

    // Buttons match text-field height so toolbars line up.
    final buttonHeight = switch (settings.density) {
      AppDensity.compact => 42.0,
      AppDensity.comfortable => 48.0,
      AppDensity.spacious => 54.0,
    };
    final useSeed = settings.source != ColorSource.preset && seed != null;
    final brand = useSeed ? null : settings.preset.brandColors(dark);
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
            scheme: useSeed || brand != null ? null : settings.preset.scheme,
            colors: useSeed ? FlexSchemeColor.from(primary: seed) : brand,
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
            scheme: useSeed || brand != null ? null : settings.preset.scheme,
            colors: useSeed ? FlexSchemeColor.from(primary: seed) : brand,
            keyColors: useSeed
                ? const FlexKeyColors(useSecondary: true, useTertiary: true)
                : null,
            variant: useSeed ? FlexSchemeVariant.tonalSpot : null,
            surfaceMode: FlexSurfaceMode.levelSurfacesLowScaffold,
            // The orange brand tints strongly; keep light surfaces near white.
            blendLevel: brand != null
                ? (settings.surfaceTint / 3).round()
                : settings.surfaceTint,
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
      sidebar: dark
          ? Color.alphaBlend(
              scheme.primary.withValues(alpha: 0.06),
              scheme.surfaceContainerLow,
            )
          : Color.alphaBlend(
              scheme.primary.withValues(alpha: 0.025),
              Colors.white,
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
      inputDecorationTheme: _inputs(scheme, radius, inputPadding, dark),
      dropdownMenuTheme: DropdownMenuThemeData(
        inputDecorationTheme: _inputs(scheme, radius, inputPadding, dark),
        menuStyle: _menuStyle(scheme, radius),
      ),
      menuTheme: MenuThemeData(style: _menuStyle(scheme, radius)),
      popupMenuTheme: PopupMenuThemeData(
        color: scheme.surfaceContainerLowest,
        surfaceTintColor: Colors.transparent,
        elevation: 8,
        shadowColor: Colors.black.withValues(alpha: 0.25),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radius),
          side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.6)),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: Size(0, buttonHeight),
          padding: const EdgeInsets.symmetric(horizontal: 18),
          textStyle: base.textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w700,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radius),
          ),
          elevation: 0,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: Size(0, buttonHeight),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          foregroundColor: scheme.onSurface,
          textStyle: base.textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w600,
          ),
          side: BorderSide(color: scheme.outlineVariant),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radius),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: Size(0, buttonHeight - 4),
          textStyle: base.textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w600,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radius),
          ),
        ),
      ),
      chipTheme: ChipThemeData(
        shape: const StadiumBorder(),
        side: BorderSide(color: scheme.outlineVariant),
        backgroundColor: scheme.surface,
        selectedColor: scheme.primaryContainer,
        secondarySelectedColor: scheme.primaryContainer,
        showCheckmark: false,
        labelStyle: base.textTheme.labelLarge?.copyWith(
          color: scheme.onSurface,
          fontWeight: FontWeight.w600,
        ),
        secondaryLabelStyle: base.textTheme.labelLarge?.copyWith(
          color: scheme.onPrimaryContainer,
          fontWeight: FontWeight.w700,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(
          selectedBackgroundColor: scheme.primaryContainer,
          selectedForegroundColor: scheme.onPrimaryContainer,
          side: BorderSide(color: scheme.outlineVariant),
          textStyle: base.textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      datePickerTheme: DatePickerThemeData(
        backgroundColor: scheme.surfaceContainerLowest,
        surfaceTintColor: Colors.transparent,
        headerBackgroundColor: scheme.primary,
        headerForegroundColor: scheme.onPrimary,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radius + 8),
        ),
        dayShape: WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
        rangeSelectionBackgroundColor: scheme.primaryContainer,
      ),
      dialogTheme: base.dialogTheme.copyWith(
        backgroundColor: scheme.surfaceContainerLowest,
        surfaceTintColor: Colors.transparent,
        elevation: 12,
        shadowColor: Colors.black.withValues(alpha: 0.3),
        titleTextStyle: base.textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.w800,
          color: scheme.onSurface,
        ),
      ),
      cardTheme: base.cardTheme.copyWith(
        color: dark ? scheme.surfaceContainerLow : Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radius + 4),
          side: BorderSide(
            color: scheme.outlineVariant.withValues(alpha: dark ? 0.35 : 0.55),
          ),
        ),
      ),
      // Pill tabs: the selected tab gets a soft brand background instead of
      // an underline; no divider under the bar.
      tabBarTheme: TabBarThemeData(
        indicatorSize: TabBarIndicatorSize.tab,
        indicator: BoxDecoration(
          color: scheme.primaryContainer.withValues(alpha: dark ? 0.5 : 0.75),
          borderRadius: BorderRadius.circular(radius + 2),
        ),
        dividerColor: Colors.transparent,
        dividerHeight: 0,
        labelColor: dark ? scheme.primary : scheme.onPrimaryContainer,
        unselectedLabelColor: scheme.onSurfaceVariant,
        labelStyle: base.textTheme.labelLarge?.copyWith(
          fontWeight: FontWeight.w700,
          fontSize: 14,
        ),
        unselectedLabelStyle: base.textTheme.labelLarge?.copyWith(
          fontWeight: FontWeight.w500,
          fontSize: 14,
        ),
        labelPadding: const EdgeInsets.symmetric(horizontal: 16),
        splashBorderRadius: BorderRadius.circular(radius + 2),
        overlayColor: WidgetStatePropertyAll(
          scheme.primary.withValues(alpha: 0.05),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbIcon: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? const Icon(Icons.check_rounded, size: 14)
              : null,
        ),
      ),
      listTileTheme: base.listTileTheme.copyWith(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radius),
        ),
        selectedTileColor: scheme.primaryContainer.withValues(alpha: 0.6),
      ),
      checkboxTheme: CheckboxThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
      ),
    );
  }

  static InputDecorationTheme _inputs(
    ColorScheme scheme,
    double radius,
    EdgeInsets padding,
    bool dark,
  ) {
    OutlineInputBorder border(Color color, [double width = 1]) =>
        OutlineInputBorder(
          borderRadius: BorderRadius.circular(radius),
          borderSide: BorderSide(color: color, width: width),
        );
    return InputDecorationTheme(
      filled: true,
      fillColor: dark
          ? scheme.surfaceContainerHigh.withValues(alpha: 0.6)
          : scheme.surfaceContainerLowest,
      hoverColor: scheme.primary.withValues(alpha: 0.04),
      contentPadding: padding,
      isDense: true,
      border: border(scheme.outlineVariant),
      enabledBorder: border(scheme.outlineVariant),
      focusedBorder: border(scheme.primary, 1.8),
      errorBorder: border(scheme.error),
      focusedErrorBorder: border(scheme.error, 1.8),
      disabledBorder: border(scheme.outlineVariant.withValues(alpha: 0.4)),
      labelStyle: TextStyle(color: scheme.onSurfaceVariant),
      floatingLabelStyle: TextStyle(
        color: scheme.primary,
        fontWeight: FontWeight.w600,
      ),
      hintStyle: TextStyle(
        color: scheme.onSurfaceVariant.withValues(alpha: 0.7),
      ),
      prefixIconColor: scheme.onSurfaceVariant,
      suffixIconColor: scheme.onSurfaceVariant,
      helperMaxLines: 2,
      errorMaxLines: 2,
    );
  }

  static MenuStyle _menuStyle(ColorScheme scheme, double radius) => MenuStyle(
    backgroundColor: WidgetStatePropertyAll(scheme.surfaceContainerLowest),
    surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
    elevation: const WidgetStatePropertyAll(6),
    shadowColor: WidgetStatePropertyAll(Colors.black.withValues(alpha: 0.16)),
    padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(vertical: 6)),
    shape: WidgetStatePropertyAll(
      RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radius),
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.6)),
      ),
    ),
  );
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
