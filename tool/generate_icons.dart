// Generates the StoreFlow POS app icon (orange tile with a white shopping
// bag, matching the in-app BrandMark).
//
//   dart run tool/generate_icons.dart
//
// Writes assets/branding/storeflow_icon.png (1024 px, used for the Microsoft
// Store package) and windows/runner/resources/app_icon.ico (window, taskbar
// and .exe icon).
import 'dart:io';
import 'dart:math' as math;

import 'package:image/image.dart' as img;

const _top = (0xFF, 0x8A, 0x3D);
const _bottom = (0xE0, 0x57, 0x1A);

/// Coverage of the logo at normalised point (u, v): returns (r, g, b, a).
(int, int, int, int) _sample(double u, double v) {
  // Rounded square background.
  const radius = 0.22;
  final dx = math.max(0.0, math.max(radius - u, u - (1 - radius)));
  final dy = math.max(0.0, math.max(radius - v, v - (1 - radius)));
  if (dx * dx + dy * dy > radius * radius) return (0, 0, 0, 0);
  final t = ((u + v) / 2).clamp(0.0, 1.0);
  int mix(int a, int b) => (a + (b - a) * t).round();
  var color = (
    mix(_top.$1, _bottom.$1),
    mix(_top.$2, _bottom.$2),
    mix(_top.$3, _bottom.$3),
  );

  bool inRoundRect(double x1, double y1, double x2, double y2, double r) {
    if (u < x1 || u > x2 || v < y1 || v > y2) return false;
    final cx = u < x1 + r ? x1 + r : (u > x2 - r ? x2 - r : u);
    final cy = v < y1 + r ? y1 + r : (v > y2 - r ? y2 - r : v);
    return (u - cx) * (u - cx) + (v - cy) * (v - cy) <= r * r;
  }

  const white = (255, 255, 255);
  // Handle: upper half ring.
  final hx = u - 0.5, hy = v - 0.40;
  final distance = math.sqrt(hx * hx + hy * hy);
  final handle = v <= 0.42 && distance >= 0.095 && distance <= 0.145;
  // Bag body.
  final body = inRoundRect(0.24, 0.38, 0.76, 0.80, 0.07);
  if (handle || body) color = white;
  // Two eyelets where the handle meets the bag.
  for (final ex in const [0.38, 0.62]) {
    final ox = u - ex, oy = v - 0.47;
    if (ox * ox + oy * oy <= 0.026 * 0.026) {
      color = (
        mix(_top.$1, _bottom.$1),
        mix(_top.$2, _bottom.$2),
        mix(_top.$3, _bottom.$3),
      );
    }
  }
  return (color.$1, color.$2, color.$3, 255);
}

img.Image _render(int size) {
  final image = img.Image(width: size, height: size, numChannels: 4);
  const samples = 4; // 4x4 supersampling for smooth edges.
  for (var y = 0; y < size; y++) {
    for (var x = 0; x < size; x++) {
      var r = 0, g = 0, b = 0, a = 0;
      for (var sy = 0; sy < samples; sy++) {
        for (var sx = 0; sx < samples; sx++) {
          final s = _sample(
            (x + (sx + 0.5) / samples) / size,
            (y + (sy + 0.5) / samples) / size,
          );
          r += s.$1 * s.$4;
          g += s.$2 * s.$4;
          b += s.$3 * s.$4;
          a += s.$4;
        }
      }
      final alpha = a / (samples * samples);
      image.setPixelRgba(
        x,
        y,
        a == 0 ? 0 : (r / a).round(),
        a == 0 ? 0 : (g / a).round(),
        a == 0 ? 0 : (b / a).round(),
        alpha.round(),
      );
    }
  }
  return image;
}

void main() {
  final master = _render(1024);
  final png = File('assets/branding/storeflow_icon.png')
    ..createSync(recursive: true)
    ..writeAsBytesSync(img.encodePng(master));
  stdout.writeln('wrote ${png.path}');

  final icons = [
    for (final size in const [256, 128, 64, 48, 32, 24, 16]) _render(size),
  ];
  final ico = File('windows/runner/resources/app_icon.ico')
    ..writeAsBytesSync(img.IcoEncoder().encodeImages(icons));
  stdout.writeln('wrote ${ico.path}');
}
