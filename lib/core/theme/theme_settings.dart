import 'package:flex_color_scheme/flex_color_scheme.dart';
import 'package:flutter/material.dart';

enum AppDensity {
  compact('Compact', 'Most rows per screen; best for busy counters.'),
  comfortable('Comfortable', 'Balanced spacing for everyday use.'),
  spacious('Touch', 'Larger targets for touch screens.');

  const AppDensity(this.label, this.description);
  final String label;
  final String description;
}

enum AppAnimationLevel {
  reduced('Off', 0),
  standard('Standard', 1),
  expressive('Expressive', 1.5);

  const AppAnimationLevel(this.label, this.factor);
  final String label;

  /// Multiplier applied to every motion duration. Zero disables motion.
  final double factor;
}

/// Where the primary/seed colour comes from.
enum ColorSource {
  preset('Theme presets'),
  windows('Windows accent'),
  custom('Custom colour');

  const ColorSource(this.label);
  final String label;
}

/// Curated built-in schemes that look professional on a desktop POS.
enum ThemePreset {
  storeflow('StoreFlow Blue', FlexScheme.blue),
  indigo('Indigo Night', FlexScheme.indigo),
  emerald('Emerald Ledger', FlexScheme.jungle),
  money('Money Green', FlexScheme.money),
  teal('Aqua Teal', FlexScheme.aquaBlue),
  violet('Violet', FlexScheme.shadViolet),
  sakura('Sakura Rose', FlexScheme.sakura),
  red('Crimson', FlexScheme.redWine),
  mango('Mango', FlexScheme.mango),
  amber('Amber Gold', FlexScheme.gold),
  espresso('Espresso', FlexScheme.espresso),
  slate('Slate', FlexScheme.shadSlate),
  zinc('Neutral Zinc', FlexScheme.shadZinc),
  bigStone('Deep Navy', FlexScheme.bigStone);

  const ThemePreset(this.label, this.scheme);
  final String label;
  final FlexScheme scheme;

  Color get swatch => FlexColor.schemes[scheme]!.light.primary;
  Color get swatchSecondary => FlexColor.schemes[scheme]!.light.secondary;
}

/// Windows system fonts only, so the app stays fully offline.
const systemFonts = <String>[
  'Segoe UI',
  'Segoe UI Variable Display',
  'Bahnschrift',
  'Calibri',
  'Tahoma',
  'Verdana',
  'Arial',
];

@immutable
class ThemeSettings {
  const ThemeSettings({
    this.mode = ThemeMode.system,
    this.source = ColorSource.preset,
    this.preset = ThemePreset.storeflow,
    this.customSeed = 0xFF1473E6,
    this.surfaceTint = 8,
    this.pureBlackDark = false,
    this.fontFamily = 'Segoe UI',
    this.fontScale = 1,
    this.density = AppDensity.comfortable,
    this.radius = 12,
    this.animationLevel = AppAnimationLevel.standard,
  });

  final ThemeMode mode;
  final ColorSource source;
  final ThemePreset preset;
  final int customSeed;

  /// Strength (0–30) of the primary colour blended into surfaces.
  final int surfaceTint;
  final bool pureBlackDark;
  final String fontFamily;
  final double fontScale;
  final AppDensity density;
  final double radius;
  final AppAnimationLevel animationLevel;

  ThemeSettings copyWith({
    ThemeMode? mode,
    ColorSource? source,
    ThemePreset? preset,
    int? customSeed,
    int? surfaceTint,
    bool? pureBlackDark,
    String? fontFamily,
    double? fontScale,
    AppDensity? density,
    double? radius,
    AppAnimationLevel? animationLevel,
  }) => ThemeSettings(
    mode: mode ?? this.mode,
    source: source ?? this.source,
    preset: preset ?? this.preset,
    customSeed: customSeed ?? this.customSeed,
    surfaceTint: surfaceTint ?? this.surfaceTint,
    pureBlackDark: pureBlackDark ?? this.pureBlackDark,
    fontFamily: fontFamily ?? this.fontFamily,
    fontScale: fontScale ?? this.fontScale,
    density: density ?? this.density,
    radius: radius ?? this.radius,
    animationLevel: animationLevel ?? this.animationLevel,
  );

  @override
  bool operator ==(Object other) =>
      other is ThemeSettings &&
      other.mode == mode &&
      other.source == source &&
      other.preset == preset &&
      other.customSeed == customSeed &&
      other.surfaceTint == surfaceTint &&
      other.pureBlackDark == pureBlackDark &&
      other.fontFamily == fontFamily &&
      other.fontScale == fontScale &&
      other.density == density &&
      other.radius == radius &&
      other.animationLevel == animationLevel;

  @override
  int get hashCode => Object.hash(
    mode,
    source,
    preset,
    customSeed,
    surfaceTint,
    pureBlackDark,
    fontFamily,
    fontScale,
    density,
    radius,
    animationLevel,
  );
}
