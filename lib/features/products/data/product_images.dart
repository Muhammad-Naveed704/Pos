import 'dart:io';
import 'dart:isolate';

import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

/// Product photos are copied into the app data folder (so they survive the
/// original file being moved and are included in backups) and scaled down
/// to keep lists and the POS grid fast.
abstract final class ProductImages {
  static const extensions = ['jpg', 'jpeg', 'png', 'webp', 'bmp', 'gif'];
  static const maxSourceBytes = 15 * 1024 * 1024;
  static const maxSide = 800;

  static Future<Directory> directory() async {
    final support = await getApplicationSupportDirectory();
    final dir = Directory(p.join(support.path, 'StoreFlow POS', 'images'));
    if (!dir.existsSync()) await dir.create(recursive: true);
    return dir;
  }

  /// Copies [sourcePath] into the image folder and returns the new path.
  static Future<String> import(String sourcePath) async {
    final source = File(sourcePath);
    if (!source.existsSync()) {
      throw const FileSystemException('The image file was not found.');
    }
    final extension = p.extension(sourcePath).replaceFirst('.', '');
    if (!extensions.contains(extension.toLowerCase())) {
      throw const FormatException('Choose a JPG, PNG, WEBP, BMP or GIF image.');
    }
    if (source.lengthSync() > maxSourceBytes) {
      throw const FormatException('The image is larger than 15 MB.');
    }
    final dir = await directory();
    final target = p.join(dir.path, '${const Uuid().v4()}.png');
    final written = await Isolate.run(() => _shrink(sourcePath, target));
    return written;
  }
}

/// Decodes, scales to [ProductImages.maxSide] and re-encodes off the UI
/// isolate. Photos become JPEG; images with transparency stay PNG.
String _shrink(String sourcePath, String targetPng) {
  final decoded = img.decodeImage(File(sourcePath).readAsBytesSync());
  if (decoded == null) {
    throw const FormatException('This file is not a readable image.');
  }
  var image = decoded;
  final longest = image.width > image.height ? image.width : image.height;
  if (longest > ProductImages.maxSide) {
    image = image.width >= image.height
        ? img.copyResize(image, width: ProductImages.maxSide)
        : img.copyResize(image, height: ProductImages.maxSide);
  }
  if (image.hasAlpha) {
    File(targetPng).writeAsBytesSync(img.encodePng(image));
    return targetPng;
  }
  final jpg = '${targetPng.substring(0, targetPng.length - 4)}.jpg';
  File(jpg).writeAsBytesSync(img.encodeJpg(image, quality: 86));
  return jpg;
}
