import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'theme_settings.dart';

final sharedPreferencesProvider = Provider<SharedPreferences>(
  (ref) => throw StateError('SharedPreferences must be overridden at startup.'),
);

final themeControllerProvider =
    NotifierProvider<ThemeController, ThemeSettings>(ThemeController.new);

class ThemeController extends Notifier<ThemeSettings> {
  static const _mode = 'theme.mode';
  static const _palette = 'theme.palette';
  static const _accent = 'theme.customAccent';
  static const _font = 'theme.font';
  static const _scale = 'theme.scale';
  static const _density = 'theme.density';
  static const _radius = 'theme.radius';
  static const _animation = 'theme.animation';

  SharedPreferences get _prefs => ref.read(sharedPreferencesProvider);

  @override
  ThemeSettings build() => ThemeSettings(
    mode: ThemeMode.values.byName(_prefs.getString(_mode) ?? 'system'),
    palette: AccentPalette.values.byName(_prefs.getString(_palette) ?? 'ocean'),
    customAccent: _prefs.getInt(_accent) ?? 0xFF1473E6,
    fontFamily: _prefs.getString(_font) ?? 'Segoe UI',
    fontScale: _prefs.getDouble(_scale) ?? 1,
    density: AppDensity.values.byName(
      _prefs.getString(_density) ?? 'comfortable',
    ),
    radius: _prefs.getDouble(_radius) ?? 12,
    animationLevel: AppAnimationLevel.values.byName(
      _prefs.getString(_animation) ?? 'standard',
    ),
  );

  Future<void> update(ThemeSettings value) async {
    state = value;
    await Future.wait([
      _prefs.setString(_mode, value.mode.name),
      _prefs.setString(_palette, value.palette.name),
      _prefs.setInt(_accent, value.customAccent),
      _prefs.setString(_font, value.fontFamily),
      _prefs.setDouble(_scale, value.fontScale),
      _prefs.setString(_density, value.density.name),
      _prefs.setDouble(_radius, value.radius),
      _prefs.setString(_animation, value.animationLevel.name),
    ]);
  }
}
