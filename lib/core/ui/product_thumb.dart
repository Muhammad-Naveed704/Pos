import 'dart:io';

import 'package:flutter/material.dart';

import '../theme/app_tokens.dart';

/// Product photo, or a coloured initial when there is none. Images are
/// decoded at display size (cacheWidth), so large catalogs stay light.
class ProductThumb extends StatelessWidget {
  const ProductThumb({
    required this.name,
    this.path,
    this.size = 44,
    this.width,
    this.height,
    this.radius,
    this.fit = BoxFit.cover,
    super.key,
  });

  final String name;
  final String? path;
  final double size;

  /// Override [size] for non-square images (e.g. POS cards).
  final double? width;
  final double? height;
  final double? radius;

  double get _w => width ?? size;
  double get _h => height ?? size;
  final BoxFit fit;

  static const _palette = [
    Color(0xFFF26A1B),
    Color(0xFF2563EB),
    Color(0xFF16A34A),
    Color(0xFF9333EA),
    Color(0xFFDB2777),
    Color(0xFF0891B2),
    Color(0xFFCA8A04),
    Color(0xFF4F46E5),
  ];

  @override
  Widget build(BuildContext context) {
    final corner = BorderRadius.circular(radius ?? (_w < _h ? _w : _h) * 0.22);
    final fallback = _initial(context, corner);
    final file = path;
    if (file == null || file.isEmpty) return fallback;
    final pixels =
        ((_w > _h ? _w : _h) * MediaQuery.devicePixelRatioOf(context)).round();
    return ClipRRect(
      borderRadius: corner,
      child: Container(
        width: _w,
        height: _h,
        color: Colors.white,
        child: Image.file(
          File(file),
          width: _w,
          height: _h,
          fit: fit,
          cacheWidth: pixels,
          gaplessPlayback: true,
          filterQuality: FilterQuality.medium,
          errorBuilder: (_, _, _) => fallback,
        ),
      ),
    );
  }

  Widget _initial(BuildContext context, BorderRadius corner) {
    final trimmed = name.trim();
    final color = _palette[trimmed.hashCode.abs() % _palette.length];
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: _w,
      height: _h,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        borderRadius: corner,
        color: color.withValues(alpha: dark ? 0.22 : 0.12),
      ),
      child: Text(
        trimmed.isEmpty ? '?' : trimmed.characters.first.toUpperCase(),
        style: context.text.titleMedium?.copyWith(
          fontSize: (_w < _h ? _w : _h) * 0.4,
          fontWeight: FontWeight.w800,
          color: color,
        ),
      ),
    );
  }
}
