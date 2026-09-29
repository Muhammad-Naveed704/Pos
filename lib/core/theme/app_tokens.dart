import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

/// Design tokens that Material's [ColorScheme] does not cover.
@immutable
class AppTokens extends ThemeExtension<AppTokens> {
  const AppTokens({
    required this.success,
    required this.onSuccess,
    required this.successContainer,
    required this.warning,
    required this.warningContainer,
    required this.info,
    required this.infoContainer,
    required this.radius,
    required this.gap,
    required this.motionFactor,
    required this.sidebar,
    required this.chartPalette,
  });

  final Color success;
  final Color onSuccess;
  final Color successContainer;
  final Color warning;
  final Color warningContainer;
  final Color info;
  final Color infoContainer;
  final double radius;

  /// Base spacing unit scaled by the density setting.
  final double gap;

  /// Multiplier for motion durations; zero disables animations.
  final double motionFactor;
  final Color sidebar;
  final List<Color> chartPalette;

  bool get animate => motionFactor > 0;

  Duration motion(int milliseconds) =>
      Duration(milliseconds: (milliseconds * motionFactor).round());

  BorderRadius get borderRadius => BorderRadius.circular(radius);

  static AppTokens of(BuildContext context) =>
      Theme.of(context).extension<AppTokens>()!;

  @override
  AppTokens copyWith({
    Color? success,
    Color? onSuccess,
    Color? successContainer,
    Color? warning,
    Color? warningContainer,
    Color? info,
    Color? infoContainer,
    double? radius,
    double? gap,
    double? motionFactor,
    Color? sidebar,
    List<Color>? chartPalette,
  }) => AppTokens(
    success: success ?? this.success,
    onSuccess: onSuccess ?? this.onSuccess,
    successContainer: successContainer ?? this.successContainer,
    warning: warning ?? this.warning,
    warningContainer: warningContainer ?? this.warningContainer,
    info: info ?? this.info,
    infoContainer: infoContainer ?? this.infoContainer,
    radius: radius ?? this.radius,
    gap: gap ?? this.gap,
    motionFactor: motionFactor ?? this.motionFactor,
    sidebar: sidebar ?? this.sidebar,
    chartPalette: chartPalette ?? this.chartPalette,
  );

  @override
  AppTokens lerp(covariant AppTokens? other, double t) {
    if (other == null) return this;
    return AppTokens(
      success: Color.lerp(success, other.success, t)!,
      onSuccess: Color.lerp(onSuccess, other.onSuccess, t)!,
      successContainer: Color.lerp(
        successContainer,
        other.successContainer,
        t,
      )!,
      warning: Color.lerp(warning, other.warning, t)!,
      warningContainer: Color.lerp(
        warningContainer,
        other.warningContainer,
        t,
      )!,
      info: Color.lerp(info, other.info, t)!,
      infoContainer: Color.lerp(infoContainer, other.infoContainer, t)!,
      radius: lerpDouble(radius, other.radius, t)!,
      gap: lerpDouble(gap, other.gap, t)!,
      motionFactor: t < 0.5 ? motionFactor : other.motionFactor,
      sidebar: Color.lerp(sidebar, other.sidebar, t)!,
      chartPalette: t < 0.5 ? chartPalette : other.chartPalette,
    );
  }
}

extension AppThemeContext on BuildContext {
  ThemeData get theme => Theme.of(this);
  ColorScheme get colors => Theme.of(this).colorScheme;
  TextTheme get text => Theme.of(this).textTheme;
  AppTokens get tokens => AppTokens.of(this);
}
