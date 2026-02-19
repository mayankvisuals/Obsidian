import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'encryption_service.dart';

class ThumbnailResult {
  final File file;
  final Uint8List decryptedBytes;
  ThumbnailResult(this.file, this.decryptedBytes);
}

class ThumbnailService {
  static final ThumbnailService _instance = ThumbnailService._internal();
  factory ThumbnailService() => _instance;
  ThumbnailService._internal();

  String? _thumbnailDir;

  Future<void> init() async {
    final appDir = await getApplicationDocumentsDirectory();
    final dir = Directory('${appDir.path}/thumbnails');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    _thumbnailDir = dir.path;
  }

  File getThumbnailFile(String fileId) {
    if (_thumbnailDir == null) throw Exception('ThumbnailService not initialized');
    return File('$_thumbnailDir/$fileId.jpg');
  }

  /// Returns the thumbnail file if it exists, otherwise null.
  Future<File?> getExistingThumbnail(String fileId) async {
    final file = getThumbnailFile(fileId);
    if (await file.exists()) return file;
    return null;
  }


  /// Generates a thumbnail from encrypted bytes and saves it to disk.
  /// Returns the generated file and the full decrypted bytes (for memory caching).
  Future<ThumbnailResult?> generateThumbnail(String fileId, Uint8List encryptedBytes) async {
    try {
      if (_thumbnailDir == null) await init();
      
      final file = getThumbnailFile(fileId);

      // Offload heavy work to isolate
      final keyBytes = EncryptionService().keyBytes;
      final result = await compute(_resizeImageTask, {
        'data': encryptedBytes,
        'key': keyBytes,
      });
      
      if (result != null) {
        final thumbBytes = result['thumb'] as Uint8List;
        final decryptedBytes = result['decrypted'] as Uint8List;
        
        // If file doesn't exist, write it. If it does, we still return decrypted bytes for cache.
        if (!await file.exists()) {
           await file.writeAsBytes(thumbBytes);
        }
        return ThumbnailResult(file, decryptedBytes);
      }
    } catch (e) {
      debugPrint('Thumbnail generation error: $e');
    }
    return null;
  }

  /// Isolate function to decrypt, resize, and encode
  static Future<Map<String, Uint8List>?> _resizeImageTask(Map<String, dynamic> args) async {
    try {
      final encryptedBytes = args['data'] as Uint8List;
      final keyBytes = args['key'] as Uint8List;

      // 1. Decrypt
      final decrypted = EncryptionService.decryptBytes({
        'key': keyBytes,
        'data': encryptedBytes,
      });
      
      if (decrypted.isEmpty) return null;

      // 2. Decode
      final image = img.decodeImage(decrypted);
      if (image == null) return null;

      // 3. Resize
      final resized = img.copyResize(image, width: 200);

      // 4. Encode to JPG
      final thumbBytes = Uint8List.fromList(img.encodeJpg(resized, quality: 70));
      
      return {
        'thumb': thumbBytes,
        'decrypted': decrypted,
      };
    } catch (e) {
      debugPrint('Isolate resize error: $e');
      return null;
    }
  }
}
