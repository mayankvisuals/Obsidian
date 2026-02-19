import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart' as enc;
import 'package:flutter/foundation.dart';

class EncryptionService {
  static final EncryptionService _instance = EncryptionService._internal();
  factory EncryptionService() => _instance;
  EncryptionService._internal();

  late enc.Key _key;
  bool _isInit = false;

  /// Initialize the service with the Bot Token.
  /// The key is derived from the SHA-256 hash of the token.
  void init(String botToken) {
    if (_isInit) return;
    
    // Derive a 32-byte key from the bot token using SHA-256
    final bytes = utf8.encode(botToken);
    final digest = sha256.convert(bytes);
    
    // Create Key from the hash
    _key = enc.Key(Uint8List.fromList(digest.bytes));
    
    _isInit = true;
    debugPrint('EncryptionService initialized.');
  }

  Uint8List get keyBytes => _key.bytes;

  /// Encrypts raw bytes. Returns the full blob (IV + Ciphertext).
  /// Runs in a separate isolate to avoid UI jank.
  Future<Uint8List> encryptData(Uint8List data) async {
    if (!_isInit) throw Exception('EncryptionService not initialized');
    // Isolate requires primitive/transferable args. Key bytes are transferable.
    return compute(_encryptTask, {'key': _key.bytes, 'data': data});
  }

  /// Decrypts full blob (IV + Ciphertext). Returns raw bytes.
  /// Runs in a separate isolate.
  Future<Uint8List> decryptData(Uint8List data) async {
    if (!_isInit) throw Exception('EncryptionService not initialized');
    return compute(decryptBytes, {'key': _key.bytes, 'data': data});
  }

  // ─── Isolate Tasks ────────────────────────────────────────────────────────
  
  static Uint8List _encryptTask(Map<String, dynamic> args) {
    final keyBytes = args['key'] as Uint8List;
    final data = args['data'] as Uint8List;
    
    final key = enc.Key(keyBytes);
    // AES-GCM is standard for authenticated encryption
    final aes = enc.Encrypter(enc.AES(key, mode: enc.AESMode.gcm));
    
    // Generate a random 12-byte IV (Nonce) for GCM
    final iv = enc.IV.fromLength(12);
    
    // Encrypt
    final encrypted = aes.encryptBytes(data, iv: iv);
    
    // Combine IV (12 bytes) + Ciphertext
    // The encrypted.bytes from the package includes the auth tag for GCM mode
    final combined = Uint8List(iv.bytes.length + encrypted.bytes.length);
    combined.setAll(0, iv.bytes);
    combined.setAll(iv.bytes.length, encrypted.bytes);
    
    return combined;
  }

  static Uint8List decryptBytes(Map<String, dynamic> args) {
    final keyBytes = args['key'] as Uint8List;
    final data = args['data'] as Uint8List;
    
    final key = enc.Key(keyBytes);
    final aes = enc.Encrypter(enc.AES(key, mode: enc.AESMode.gcm));
    
    // Extract IV (first 12 bytes)
    if (data.length < 12) throw Exception('Invalid encrypted data');
    final iv = enc.IV(data.sublist(0, 12));
    
    // Extract Ciphertext (remaining bytes)
    final ciphertextBytes = data.sublist(12);
    final encryptedObj = enc.Encrypted(ciphertextBytes);
    
    // Decrypt
    final decrypted = aes.decryptBytes(encryptedObj, iv: iv);
    return Uint8List.fromList(decrypted);
  }
}
