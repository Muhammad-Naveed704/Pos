import 'dart:async';

import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'theme_settings.dart';

final sharedPreferencesProvider = Provider<SharedPreferences>(
  (ref) => throw StateError('SharedPreferences must be overridden at startup.'),
);

final themeControllerProvider =
    NotifierProvider<ThemeController, ThemeSettings>(ThemeController.new);

/// The current Windows accent colour, or null when unavailable (tests, older
/// Windows builds). Only read when the user selects [ColorSource.windows].
final windowsAccentProvider = FutureProvider<Color?>((ref) async {
  try {
    return await DynamicColorPlugin.getAccentColor();
  } catch (_) {
    return null;
  }
});

class ThemeController extends Notifier<ThemeSettings> {
  static const _mode = 'theme.mode';
  static const _source = 'theme.source';
  static const _preset = 'theme.preset';
  static const _seed = 'theme.customSeed';
  static const _tint = 'theme.surfaceTint';
  static const _pureBlack = 'theme.pureBlackDark';
  static const _font = 'theme.font';
  static const _scale = 'theme.scale';
  static const _density = 'theme.density';
  static const _radius = 'theme.radius';
  static const _animation = 'theme.animation';

  // Keys written by the first theme version; read once for migration.
  static const _legacyPalette = 'theme.palette';
  static const _legacyAccent = 'theme.customAccent';

  SharedPreferences get _prefs => ref.read(sharedPreferencesProvider);
  Timer? _persistDebounce;

  @override
  ThemeSettings build() {
    ref.onDispose(() => _persistDebounce?.cancel());
    const defaults = ThemeSettings();
    final legacyPalette = _prefs.getString(_legacyPalette);
    final legacyCustom = legacyPalette == 'custom';
    final font = _prefs.getString(_font);
    return ThemeSettings(
      mode: _enum(ThemeMode.values, _prefs.getString(_mode), defaults.mode),
      source: _enum(
        ColorSource.values,
        _prefs.getString(_source),
        legacyCustom ? ColorSource.custom : defaults.source,
      ),
      preset: _enum(
        ThemePreset.values,
        _prefs.getString(_preset),
        _legacyPreset(legacyPalette),
      ),
      customSeed:
          _prefs.getInt(_seed) ??
          _prefs.getInt(_legacyAccent) ??
          defaults.customSeed,
      surfaceTint: (_prefs.getInt(_tint) ?? defaults.surfaceTint).clamp(0, 30),
      pureBlackDark: _prefs.getBool(_pureBlack) ?? defaults.pureBlackDark,
      fontFamily: systemFonts.contains(font) ? font! : defaults.fontFamily,
      fontScale: (_prefs.getDouble(_scale) ?? defaults.fontScale).clamp(
        0.85,
        1.3,
      ),
      density: _enum(
        AppDensity.values,
        _prefs.getString(_density),
        defaults.density,
      ),
      radius: (_prefs.getDouble(_radius) ?? defaults.radius).clamp(0, 24),
      animationLevel: _enum(
        AppAnimationLevel.values,
        _prefs.getString(_animation),
        defaults.animationLevel,
      ),
    );
  }

  /// Applies [value] immediately. Persistence is debounced so dragging a
  /// slider does not write preferences on every frame.
  void update(ThemeSettings value) {
    if (value == state) return;
    state = value;
    _persistDebounce?.cancel();
    _persistDebounce = Timer(const Duration(milliseconds: 300), _persist);
  }

  void reset() => update(const ThemeSettings());

  Future<void> _persist() async {
    final value = state;
    await Future.wait([
      _prefs.setString(_mode, value.mode.name),
      _prefs.setString(_source, value.source.name),
      _prefs.setString(_preset, value.preset.name),
      _prefs.setInt(_seed, value.customSeed),
      _prefs.setInt(_tint, value.surfaceTint),
      _prefs.setBool(_pureBlack, value.pureBlackDark),
      _prefs.setString(_font, value.fontFamily),
      _prefs.setDouble(_scale, value.fontScale),
      _prefs.setString(_density, value.density.name),
      _prefs.setDouble(_radius, value.radius),
      _prefs.setString(_animation, value.animationLevel.name),
    ]);
  }

  static T _enum<T extends Enum>(List<T> values, String? name, T fallback) =>
      values.where((value) => value.name == name).firstOrNull ?? fallback;

  static ThemePreset _legacyPreset(String? palette) => switch (palette) {
    'indigo' => ThemePreset.indigo,
    'emerald' => ThemePreset.emerald,
    'purple' => ThemePreset.violet,
    'amber' => ThemePreset.amber,
    'rose' => ThemePreset.sakura,
    'monochrome' => ThemePreset.slate,
    _ => ThemePreset.storeflow,
  };
}
