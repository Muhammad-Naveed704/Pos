import 'package:flutter/material.dart';

/// The StoreFlow logo tile, drawn in the active theme's primary colours.
class BrandMark extends StatelessWidget {
  const BrandMark({this.size = 40, this.onDark = false, super.key});
  final double size;

  /// Use a translucent white tile on coloured hero panels.
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.28),
        gradient: onDark
            ? null
            : LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [scheme.primary, scheme.tertiary],
              ),
        color: onDark ? Colors.white.withValues(alpha: 0.18) : null,
        border: onDark
            ? Border.all(color: Colors.white.withValues(alpha: 0.35))
            : null,
        boxShadow: onDark
            ? null
            : [
                BoxShadow(
                  color: scheme.primary.withValues(alpha: 0.35),
                  blurRadius: size * 0.35,
                  offset: Offset(0, size * 0.12),
                ),
              ],
      ),
      child: Icon(
        Icons.bolt_rounded,
        color: onDark ? Colors.white : scheme.onPrimary,
        size: size * 0.6,
      ),
    );
  }
}
