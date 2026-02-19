import 'dart:io';
import 'dart:typed_data';
import 'package:image/image.dart' as img;

void main() {
  // Load the original logo
  final bytes = File('assets/app_logo.png').readAsBytesSync();
  final original = img.decodeImage(bytes)!;

  // Create 1024x1024 canvas with dark background (#121212)
  final canvas = img.Image(width: 1024, height: 1024);
  img.fill(canvas, color: img.ColorRgb8(0x12, 0x12, 0x12));

  // Resize logo to fit within ~60% of canvas (384px padding total = 192px each side)
  final logoSize = 640; // 1024 * 0.625
  final resized = img.copyResize(original, width: logoSize, height: logoSize, interpolation: img.Interpolation.cubic);

  // Center on canvas
  final offset = (1024 - logoSize) ~/ 2; // 192
  img.compositeImage(canvas, resized, dstX: offset, dstY: offset);

  // Save
  File('assets/app_logo_foreground.png').writeAsBytesSync(img.encodePng(canvas));
  print('Generated app_logo_foreground.png (1024x1024 with padding)');
}
