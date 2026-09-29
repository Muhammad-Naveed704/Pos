import 'package:flutter/material.dart';

enum AppDensity { compact, comfortable, spacious }

enum AppAnimationLevel { reduced, standard, expressive }

enum AccentPalette {
  ocean('Ocean Blue', 0xFF1473E6),
  indigo('Indigo', 0xFF5B5BD6),
  emerald('Emerald', 0xFF098A6E),
  purple('Purple', 0xFF7C3AED),
  amber('Amber', 0xFFD97706),
  rose('Rose', 0xFFE13C65),
  monochrome('Monochrome', 0xFF525866),
  custom('Custom', 0xFF1473E6);

  const AccentPalette(this.label, this.value);
  final String label;
  final int value;
}

@immutable
class ThemeSettings {
  const ThemeSettings({
    this.mode = ThemeMode.system,
    this.palette = AccentPalette.ocean,
    this.customAccent = 0xFF1473E6,
    this.fontFamily = 'Segoe UI',
    this.fontScale = 1,
    this.density = AppDensity.comfortable,
    this.radius = 12,
    this.animationLevel = AppAnimationLevel.standard,
  });

  final ThemeMode mode;
  final AccentPalette palette;
  final int customAccent;
  final String fontFamily;
  final double fontScale;
  final AppDensity density;
  final double radius;
  final AppAnimationLevel animationLevel;

  Color get accent =>
      Color(palette == AccentPalette.custom ? customAccent : palette.value);

  ThemeSettings copyWith({
    ThemeMode? mode,
    AccentPalette? palette,
    int? customAccent,
    String? fontFamily,
    double? fontScale,
    AppDensity? density,
    double? radius,
    AppAnimationLevel? animationLevel,
  }) => ThemeSettings(
    mode: mode ?? this.mode,
    palette: palette ?? this.palette,
    customAccent: customAccent ?? this.customAccent,
    fontFamily: fontFamily ?? this.fontFamily,
    fontScale: fontScale ?? this.fontScale,
    density: density ?? this.density,
    radius: radius ?? this.radius,
    animationLevel: animationLevel ?? this.animationLevel,
  );
}
