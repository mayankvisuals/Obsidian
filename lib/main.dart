import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image_gallery_saver_plus/image_gallery_saver_plus.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:image/image.dart' as img;import 'services/encryption_service.dart';
import 'services/thumbnail_service.dart';

// ─── Constants ──────────────────────────────────────────────────────────────

const Color kBackground = Color(0xFF121212);
const Color kSurface = Color(0xFF1E1E1E);
const Color kCardDark = Color(0xFF2A2A2A);
const Color kPrimary = Color(0xFFBB86FC);
const Color kTeal = Color(0xFF03DAC6);
const Color kError = Color(0xFFCF6679);
const Color kTextPrimary = Color(0xFFFFFFFF);
const Color kTextSecondary = Color(0xFFB3B3B3);
const double kRadius = 16.0;

const String _prefToken = 'bot_token';
const String _prefChatId = 'chat_id';
const String _prefUserName = 'user_name';
const String _prefFiles = 'uploaded_files';

// ─── Cloud File Model ───────────────────────────────────────────────────────

class CloudFile {
  final String fileName;
  final String fileId;
  final int messageId;
  final DateTime uploadedAt;
  final int fileSize;
  final String? thumbnailFileId;
  String? localPath;
  final DateTime? deletedAt;

  CloudFile({
    required this.fileName,
    required this.fileId,
    required this.messageId,
    required this.uploadedAt,
    required this.fileSize,
    this.thumbnailFileId,
    this.localPath,
    this.deletedAt,
  });

  bool get isImage {
    var name = fileName.toLowerCase();
    if (name.endsWith('.enc')) {
      name = name.substring(0, name.length - 4);
    }
    final ext = p.extension(name);
    return ['.jpg', '.jpeg', '.png', '.gif', '.webp', '.bmp'].contains(ext);
  }

  String get formattedSize {
    if (fileSize < 1024) return '$fileSize B';
    if (fileSize < 1024 * 1024) {
      return '${(fileSize / 1024).toStringAsFixed(1)} KB';
    }
    return '${(fileSize / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  IconData get icon {
    var name = fileName.toLowerCase();
    if (name.endsWith('.enc')) {
      name = name.substring(0, name.length - 4);
    }
    final ext = p.extension(name).toLowerCase();
    return switch (ext) {
      '.jpg' || '.jpeg' || '.png' || '.gif' || '.webp' || '.bmp' =>
        Icons.image_rounded,
      '.mp4' || '.mov' || '.avi' || '.mkv' => Icons.videocam_rounded,
      '.mp3' || '.wav' || '.flac' || '.aac' => Icons.audiotrack_rounded,
      '.pdf' => Icons.picture_as_pdf_rounded,
      '.zip' || '.rar' || '.7z' => Icons.folder_zip_rounded,
      '.doc' || '.docx' || '.txt' => Icons.description_rounded,
      _ => Icons.insert_drive_file_rounded,
    };
  }

  Color get iconColor {
    var name = fileName.toLowerCase();
    if (name.endsWith('.enc')) {
      name = name.substring(0, name.length - 4);
    }
    final ext = p.extension(name).toLowerCase();
    return switch (ext) {
      '.jpg' || '.jpeg' || '.png' || '.gif' || '.webp' || '.bmp' =>
        const Color(0xFF4CAF50),
      '.mp4' || '.mov' || '.avi' || '.mkv' => const Color(0xFFE91E63),
      '.mp3' || '.wav' || '.flac' || '.aac' => const Color(0xFFFF9800),
      '.pdf' => const Color(0xFFF44336),
      '.zip' || '.rar' || '.7z' => const Color(0xFF9C27B0),
      _ => kPrimary,
    };
  }

  Map<String, dynamic> toJson() => {
        'fileName': fileName,
        'fileId': fileId,
        'messageId': messageId,
        'uploadedAt': uploadedAt.toIso8601String(),
        'fileSize': fileSize,
        'thumbnailFileId': thumbnailFileId,
        'localPath': localPath,
        'deletedAt': deletedAt?.toIso8601String(),
      };

  factory CloudFile.fromJson(Map<String, dynamic> json) => CloudFile(
        fileName: json['fileName'] ?? '',
        fileId: json['fileId'] ?? '',
        messageId: json['messageId'] ?? 0,
        uploadedAt:
            DateTime.tryParse(json['uploadedAt'] ?? '') ?? DateTime.now(),
        fileSize: json['fileSize'] ?? 0,
        thumbnailFileId: json['thumbnailFileId'],
        localPath: json['localPath'],
        deletedAt: json['deletedAt'] != null
            ? DateTime.tryParse(json['deletedAt'])
            : null,
      );
}

class FileState {
  final String path;
  final String fileName;
  final int fileSize;
  double progress;
  bool isUploaded;
  bool isFailed;
  bool isProcessing;
  String status;

  FileState({
    required this.path,
    required this.fileName,
    required this.fileSize,
    this.progress = 0.0,
    this.isUploaded = false,
    this.isFailed = false,
    this.isProcessing = false,
    this.status = 'Waiting',
  });
}


// ─── File Storage ───────────────────────────────────────────────────────────

class FileStorage {
  static const _prefTrash = 'trash_files';

  static Future<List<CloudFile>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefFiles);
    if (raw == null) return [];
    try {
      final list = jsonDecode(raw) as List;
      return list
          .map((e) => CloudFile.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> save(List<CloudFile> files) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _prefFiles, jsonEncode(files.map((e) => e.toJson()).toList()));
  }

  static Future<List<CloudFile>> loadTrash() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefTrash);
    if (raw == null) return [];
    try {
      final list = jsonDecode(raw) as List;
      return list
          .map((e) => CloudFile.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> saveTrash(List<CloudFile> files) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _prefTrash, jsonEncode(files.map((e) => e.toJson()).toList()));
  }
}

// ─── Telegram Service ───────────────────────────────────────────────────────

class TelegramService {
  final String token;
  String get _base => 'https://api.telegram.org/bot$token';

  TelegramService(this.token);

  Future<Map<String, dynamic>?> getMe() async {
    try {
      final res = await http.get(Uri.parse('$_base/getMe'));
      final body = jsonDecode(res.body);
      if (body['ok'] == true) return body['result'];
    } catch (_) {}
    return null;
  }

  Future<Map<String, dynamic>?> getUpdates({int? offset}) async {
    try {
      final uri = Uri.parse('$_base/getUpdates').replace(
        queryParameters: {
          'timeout': '0',
          if (offset != null) 'offset': offset.toString(),
        },
      );
      final res = await http.get(uri);
      final body = jsonDecode(res.body);
      if (body['ok'] == true) return body;
    } catch (_) {}
    return null;
  }

  final Dio _dio = Dio();

  /// Sends a document and returns the full message result or null.
  Future<Map<String, dynamic>?> sendDocument({
    required String chatId,
    required String filePath,
    required String fileName,
    void Function(int, int)? onSendProgress,
  }) async {
    try {
      final formData = FormData.fromMap({
        'chat_id': chatId,
        'document': await MultipartFile.fromFile(filePath, filename: fileName),
      });

      final response = await _dio.post(
        '$_base/sendDocument',
        data: formData,
        onSendProgress: onSendProgress,
      );

      if (response.statusCode == 200) {
        final json = response.data;
        if (json['ok'] == true) return json['result'];
      }
    } catch (_) {}
    return null;
  }

  /// Sends a document from bytes.
  Future<Map<String, dynamic>?> sendDocumentBytes({
    required String chatId,
    required List<int> bytes,
    required String fileName,
    void Function(int, int)? onSendProgress,
  }) async {
    try {
      final formData = FormData.fromMap({
        'chat_id': chatId,
        'document': MultipartFile.fromBytes(bytes, filename: fileName),
      });

      final response = await _dio.post(
        '$_base/sendDocument',
        data: formData,
        onSendProgress: onSendProgress,
      );

      if (response.statusCode == 200) {
        final json = response.data;
        if (json['ok'] == true) return json['result'];
      }
    } catch (e) {
      debugPrint('sendDocumentBytes error: $e');
    }
    return null;
  }

  /// Resolves a file_id to a download URL.
  Future<String?> getFileUrl(String fileId) async {
    try {
      final res =
          await http.get(Uri.parse('$_base/getFile?file_id=$fileId'));
      final body = jsonDecode(res.body);
      if (body['ok'] == true) {
        final fp = body['result']['file_path'];
        return 'https://api.telegram.org/file/bot$token/$fp';
      }
    } catch (_) {}
    return null;
  }

  /// Deletes a message (and its attached file) from the chat.
  Future<bool> deleteMessage(String chatId, int messageId) async {
    try {
      final res = await http.post(
        Uri.parse('$_base/deleteMessage'),
        body: {'chat_id': chatId, 'message_id': messageId.toString()},
      );
      final body = jsonDecode(res.body);
      return body['ok'] == true;
    } catch (_) {
      return false;
    }
  }

  /// Gets chat info including pinned message.
  Future<Map<String, dynamic>?> getChat(String chatId) async {
    try {
      final res =
          await http.get(Uri.parse('$_base/getChat?chat_id=$chatId'));
      final body = jsonDecode(res.body);
      if (body['ok'] == true) return body['result'];
    } catch (_) {}
    return null;
  }

  /// Pins a message in the chat (silently).
  Future<bool> pinChatMessage(String chatId, int messageId) async {
    try {
      final res = await http.post(
        Uri.parse('$_base/pinChatMessage'),
        body: {
          'chat_id': chatId,
          'message_id': messageId.toString(),
          'disable_notification': 'true',
        },
      );
      final body = jsonDecode(res.body);
      return body['ok'] == true;
    } catch (_) {
      return false;
    }
  }
}

// ─── Entry Point ────────────────────────────────────────────────────────────

void main() {
  runApp(const ObsidianApp());
}

class ObsidianApp extends StatelessWidget {
  const ObsidianApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Obsidian',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: kBackground,
        colorScheme: const ColorScheme.dark(
          surface: kSurface,
          primary: kPrimary,
          secondary: kTeal,
          error: kError,
        ),
        textTheme: GoogleFonts.poppinsTextTheme(ThemeData.dark().textTheme),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: kSurface,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(kRadius),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(kRadius),
            borderSide: const BorderSide(color: kPrimary, width: 2),
          ),
          hintStyle: GoogleFonts.poppins(color: kTextSecondary),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: kPrimary,
            foregroundColor: kBackground,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(kRadius),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
            textStyle:
                GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w600),
          ),
        ),
      ),
      home: const SplashScreen(),
    );
  }
}

// ─── Splash / Auto-Login ────────────────────────────────────────────────────

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1200));
    _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeIn);
    _ctrl.forward();
    _checkAutoLogin();
  }

  Future<void> _checkAutoLogin() async {
    await Future.delayed(const Duration(milliseconds: 1500));
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString(_prefToken);
    final chatId = prefs.getString(_prefChatId);
    final userName = prefs.getString(_prefUserName);
    if (!mounted) return;
    if (token != null && chatId != null) {
      _go(DashboardScreen(
          token: token, chatId: chatId, userName: userName ?? 'User'));
      EncryptionService().init(token);
    } else {
      _go(const LoginScreen());
    }
  }

  void _go(Widget page) {
    Navigator.of(context).pushReplacement(PageRouteBuilder(
      transitionDuration: const Duration(milliseconds: 500),
      pageBuilder: (_, a, b) => page,
      transitionsBuilder: (_, anim, c, child) => FadeTransition(
        opacity: anim,
        child: SlideTransition(
          position: Tween(begin: const Offset(0, 0.05), end: Offset.zero)
              .animate(CurvedAnimation(parent: anim, curve: Curves.easeOut)),
          child: child,
        ),
      ),
    ));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: FadeTransition(
          opacity: _fade,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: Image.asset('assets/app_logo.png',
                  width: 100, height: 100),
            ),
            const SizedBox(height: 24),
            Text('Obsidian',
                style: GoogleFonts.poppins(
                    fontSize: 28,
                    fontWeight: FontWeight.w700,
                    color: kTextPrimary)),
            const SizedBox(height: 8),
            Text('Unlimited Storage',
                style:
                    GoogleFonts.poppins(fontSize: 14, color: kTextSecondary)),
            const SizedBox(height: 40),
            const SizedBox(
                width: 28,
                height: 28,
                child:
                    CircularProgressIndicator(strokeWidth: 2.5, color: kPrimary)),
          ]),
        ),
      ),
    );
  }
}

// ─── Screen 1: Login & Setup ────────────────────────────────────────────────

enum _LoginState { input, verifying, polling, error }

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _tokenCtrl = TextEditingController();
  _LoginState _state = _LoginState.input;
  String _error = '';
  String _botName = '';
  Timer? _pollTimer;

  @override
  void dispose() {
    _tokenCtrl.dispose();
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _onConnect() async {
    final token = _tokenCtrl.text.trim();
    if (token.isEmpty) {
      setState(() {
        _state = _LoginState.error;
        _error = 'Please enter a bot token';
      });
      return;
    }
    setState(() => _state = _LoginState.verifying);

    final svc = TelegramService(token);
    final me = await svc.getMe();
    if (!mounted) return;
    if (me == null) {
      setState(() {
        _state = _LoginState.error;
        _error = 'Invalid token. Please check and try again.';
      });
      return;
    }

    _botName = me['first_name'] ?? 'Bot';
    setState(() => _state = _LoginState.polling);

    final flush = await svc.getUpdates();
    int? lastUpdateId;
    if (flush != null && (flush['result'] as List).isNotEmpty) {
      lastUpdateId = (flush['result'] as List).last['update_id'] + 1;
    }

    _pollTimer = Timer.periodic(const Duration(seconds: 3), (_) async {
      final data = await svc.getUpdates(offset: lastUpdateId);
      if (data == null) return;
      final results = data['result'] as List;
      if (results.isEmpty) return;

      for (final update in results) {
        final msg = update['message'];
        if (msg != null) {
          final chatId = msg['chat']['id'].toString();
          final name = msg['from']?['first_name'] ?? 'User';
          _pollTimer?.cancel();

          final prefs = await SharedPreferences.getInstance();
          await prefs.setString(_prefToken, token);
          await prefs.setString(_prefChatId, chatId);
          await prefs.setString(_prefUserName, name);
          EncryptionService().init(token);
          if (!mounted) return;

          Navigator.of(context).pushReplacement(PageRouteBuilder(
            transitionDuration: const Duration(milliseconds: 500),
            pageBuilder: (_, a, b) =>
                DashboardScreen(token: token, chatId: chatId, userName: name),
            transitionsBuilder: (_, anim, c, child) => FadeTransition(
              opacity: anim,
              child: SlideTransition(
                position:
                    Tween(begin: const Offset(0, 0.05), end: Offset.zero)
                        .animate(CurvedAnimation(
                            parent: anim, curve: Curves.easeOut)),
                child: child,
              ),
            ),
          ));
          return;
        }
      }
      lastUpdateId = results.last['update_id'] + 1;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 400),
              child: _buildContent(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildContent() {
    if (_state == _LoginState.verifying) {
      return _loading('Verifying Token...', 'Connecting to Telegram Bot API');
    }
    if (_state == _LoginState.polling) {
      return _loading('Connected to $_botName!',
          'Now open Telegram and send any message\nto your bot to link your account.');
    }
    return _inputForm();
  }

  Widget _inputForm() {
    return Column(
        key: const ValueKey('input'),
        mainAxisSize: MainAxisSize.min,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child:
                Image.asset('assets/app_logo.png', width: 88, height: 88),
          ),
          const SizedBox(height: 28),
          Text('Obsidian',
              style: GoogleFonts.poppins(
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                  color: kTextPrimary)),
          const SizedBox(height: 6),
          Text('Powered by Telegram',
              style:
                  GoogleFonts.poppins(fontSize: 14, color: kTextSecondary)),
          const SizedBox(height: 40),
          TextField(
            controller: _tokenCtrl,
            style: GoogleFonts.poppins(color: kTextPrimary),
            decoration: InputDecoration(
              hintText: 'Enter your Bot Token',
              prefixIcon:
                  const Icon(Icons.key_rounded, color: kTextSecondary),
              suffixIcon: _tokenCtrl.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, color: kTextSecondary),
                      onPressed: () {
                        _tokenCtrl.clear();
                        setState(() {});
                      })
                  : null,
            ),
            onChanged: (_) => setState(() {}),
          ),
          if (_state == _LoginState.error) ...[
            const SizedBox(height: 12),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: kError.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(children: [
                const Icon(Icons.error_outline, color: kError, size: 20),
                const SizedBox(width: 10),
                Expanded(
                    child: Text(_error,
                        style: GoogleFonts.poppins(
                            fontSize: 13, color: kError))),
              ]),
            ),
          ],
          const SizedBox(height: 28),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _onConnect,
              icon: const Icon(Icons.link_rounded),
              label: const Text('Connect'),
            ),
          ),
          const SizedBox(height: 20),
          Text('Get a token from @BotFather on Telegram',
              style: GoogleFonts.poppins(
                  fontSize: 12,
                  color: kTextSecondary.withValues(alpha: 0.6)),
              textAlign: TextAlign.center),
        ]);
  }

  Widget _loading(String title, String sub) {
    return Column(
        key: ValueKey(title),
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: kTeal.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.chat_bubble_outline_rounded,
                size: 52, color: kTeal),
          ),
          const SizedBox(height: 28),
          Text(title,
              style: GoogleFonts.poppins(
                  fontSize: 22,
                  fontWeight: FontWeight.w600,
                  color: kTextPrimary),
              textAlign: TextAlign.center),
          const SizedBox(height: 10),
          Text(sub,
              style: GoogleFonts.poppins(
                  fontSize: 14, color: kTextSecondary, height: 1.5),
              textAlign: TextAlign.center),
          const SizedBox(height: 36),
          const SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(strokeWidth: 2.5, color: kTeal)),
        ]);
  }
}

// ─── Screen 2: Dashboard (Gallery) ──────────────────────────────────────────

class DashboardScreen extends StatefulWidget {
  final String token, chatId, userName;
  const DashboardScreen(
      {super.key,
      required this.token,
      required this.chatId,
      required this.userName});
  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  late final TelegramService _svc;
  List<CloudFile> _files = [];
  List<CloudFile> _trashFiles = [];
  bool _isLoading = true;
  bool _isUploading = false;
  String _uploadingName = '';
  final Map<String, String> _urlCache = {};
  final Map<String, String> _fullUrlCache = {};
  final Map<String, Uint8List> _decryptedCache = {};
  int? _indexMessageId;

  // Thumbnail Queue
  final List<CloudFile> _thumbnailQueue = [];
  bool _isGeneratingThumbnail = false;
  bool _isViewerOpen = false; // To pause background work

  // URL cache persistence keys
  static const String _prefUrlCache = 'url_cache';
  static const String _prefFullUrlCache = 'full_url_cache';
  static const String _prefUrlCacheTime = 'url_cache_time';

  // Selection Mode State
  bool _isSelectionMode = false;
  final Set<String> _selectedFileIds = {};

  @override
  void initState() {
    super.initState();
    _svc = TelegramService(widget.token);
    _init();
  }

  Future<void> _init() async {
    await ThumbnailService().init();
    
    // Load index message ID from local prefs
    final prefs = await SharedPreferences.getInstance();
    _indexMessageId = prefs.getInt('index_message_id');

    // Load persisted URL caches for instant thumbnail display
    await _loadUrlCache();

    // Try loading from local storage first
    _files = await FileStorage.load();
    _trashFiles = await FileStorage.loadTrash();

    // Auto-purge trash items older than 15 days
    final now = DateTime.now();
    final expired = _trashFiles.where((f) {
      if (f.deletedAt == null) return false;
      return now.difference(f.deletedAt!).inDays >= 15;
    }).toList();

    if (expired.isNotEmpty) {
      for (final f in expired) {
        await _svc.deleteMessage(widget.chatId, f.messageId); // Permanent delete
        _trashFiles.remove(f);
      }
      await FileStorage.saveTrash(_trashFiles);
    }

    // If empty (fresh install), try fetching from Telegram pinned message
    if (_files.isEmpty) {
      final cloudFiles = await _fetchIndexFromCloud();
      if (cloudFiles.isNotEmpty) {
        _files = cloudFiles;
        await FileStorage.save(_files);
      }
    }

    if (mounted) setState(() => _isLoading = false);
    _resolveUrls();
  }

  /// Load persisted URL cache from SharedPreferences
  Future<void> _loadUrlCache() async {
    final prefs = await SharedPreferences.getInstance();
    final urlRaw = prefs.getString(_prefUrlCache);
    final fullUrlRaw = prefs.getString(_prefFullUrlCache);

    if (urlRaw != null) {
      try {
        final map = jsonDecode(urlRaw) as Map<String, dynamic>;
        _urlCache.addAll(map.map((k, v) => MapEntry(k, v.toString())));
      } catch (_) {}
    }
    if (fullUrlRaw != null) {
      try {
        final map = jsonDecode(fullUrlRaw) as Map<String, dynamic>;
        _fullUrlCache.addAll(map.map((k, v) => MapEntry(k, v.toString())));
      } catch (_) {}
    }
  }

  /// Save URL caches to SharedPreferences
  Future<void> _saveUrlCache() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefUrlCache, jsonEncode(_urlCache));
    await prefs.setString(_prefFullUrlCache, jsonEncode(_fullUrlCache));
    await prefs.setString(_prefUrlCacheTime, DateTime.now().toIso8601String());
  }

  /// Fetches the file index from the pinned message in the Telegram chat.
  Future<List<CloudFile>> _fetchIndexFromCloud() async {
    try {
      final chat = await _svc.getChat(widget.chatId);
      if (chat == null) return [];

      final pinned = chat['pinned_message'] as Map<String, dynamic>?;
      if (pinned == null) return [];

      final doc = pinned['document'] as Map<String, dynamic>?;
      if (doc == null || doc['file_name'] != 'obsidian_index.json') return [];

      // Download the index file
      final url = await _svc.getFileUrl(doc['file_id']);
      if (url == null) return [];

      final response = await http.get(Uri.parse(url));
      final list = jsonDecode(response.body) as List;

      // Save the pinned message ID so we can delete it later when updating
      _indexMessageId = pinned['message_id'];
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('index_message_id', _indexMessageId!);

      return list
          .map((e) => CloudFile.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// Syncs the current file list to Telegram as a pinned JSON document.
  Future<void> _syncIndexToCloud() async {
    try {
      final jsonStr = jsonEncode(_files.map((f) => f.toJson()).toList());

      // Write to temp file
      final dir = await getTemporaryDirectory();
      final indexFile = File('${dir.path}/obsidian_index.json');
      await indexFile.writeAsString(jsonStr);

      // Delete old index message
      if (_indexMessageId != null) {
        await _svc.deleteMessage(widget.chatId, _indexMessageId!);
      }

      // Upload new index
      final result = await _svc.sendDocument(
        chatId: widget.chatId,
        filePath: indexFile.path,
        fileName: 'obsidian_index.json',
      );

      if (result != null) {
        _indexMessageId = result['message_id'];
        // Pin it silently
        await _svc.pinChatMessage(widget.chatId, _indexMessageId!);
        // Save locally
        final prefs = await SharedPreferences.getInstance();
        await prefs.setInt('index_message_id', _indexMessageId!);
      }

      // Cleanup temp file
      // Cleanup temp file
      if (await indexFile.exists()) await indexFile.delete();
    } catch (e) {
      debugPrint('Sync Index Error: $e');
      if (mounted) {
         ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Sync failed: $e', style: GoogleFonts.poppins(fontSize: 12)),
            backgroundColor: kError,
         ));
      }
    }
  }

  Future<void> _resolveUrls() async {
    final imageFiles = _files.where((f) => f.isImage).toList();
    if (imageFiles.isEmpty) return;

    bool cacheUpdated = false;
    const batchSize = 10;

    for (int i = 0; i < imageFiles.length; i += batchSize) {
      final batch = imageFiles.sublist(i, min(i + batchSize, imageFiles.length));

      await Future.wait(batch.map((f) async {
        final id = f.thumbnailFileId ?? f.fileId;

        // Resolve thumbnail URL
        if (!_urlCache.containsKey(id)) {
          final url = await _svc.getFileUrl(id);
          if (url != null && mounted) {
            _urlCache[id] = url;
            cacheUpdated = true;
          }
        }

        // Pre-resolve full-size URL for instant viewing
        if (!_fullUrlCache.containsKey(f.fileId)) {
          final fullUrl = await _svc.getFileUrl(f.fileId);
          if (fullUrl != null && mounted) {
            _fullUrlCache[f.fileId] = fullUrl;
            cacheUpdated = true;
          }
        }
      }));

      // Update UI after each batch so thumbnails appear progressively
      if (mounted) setState(() {});
    }

    // Persist the resolved URLs for next app launch
    if (cacheUpdated) {
      _saveUrlCache();
    }
  }

  String _dateHeader(DateTime dt) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final date = DateTime(dt.year, dt.month, dt.day);
    if (date == today) return 'Today';
    if (date == today.subtract(const Duration(days: 1))) return 'Yesterday';
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${months[dt.month - 1]} ${dt.day}';
  }

  // Parallel Upload State
  final List<FileState> _uploadQueue = [];
  bool _isProcessingQueue = false;

  Future<void> _pickAndUpload() async {
    final picker = ImagePicker();
    List<String> pathsToUpload = [];

    try {
      final List<XFile> images = await picker.pickMultiImage();
      if (images.isNotEmpty) {
        pathsToUpload = images.map((e) => e.path).toList();
      } else {
        final result = await FilePicker.platform.pickFiles(allowMultiple: true);
        if (result != null && result.files.isNotEmpty) {
          pathsToUpload = result.files
              .where((f) => f.path != null)
              .map((f) => f.path!)
              .toList();
        }
      }
    } catch (_) {
      final result = await FilePicker.platform.pickFiles(allowMultiple: true);
      if (result != null && result.files.isNotEmpty) {
        pathsToUpload = result.files
            .where((f) => f.path != null)
            .map((f) => f.path!)
            .toList();
      }
    }

    if (pathsToUpload.isEmpty) return;

    // Add to queue
    for (final path in pathsToUpload) {
      final fileName = p.basename(path);
      final fileSize = await File(path).length();
      _uploadQueue.add(FileState(
        path: path,
        fileName: fileName,
        fileSize: fileSize,
      ));
    }

    if (mounted) setState(() => _isUploading = true);
    _processQueue();
  }

  // Worker Pool System
  final List<bool> _workerActive = [false, false, false]; // Track 3 workers

  void _processQueue() {
     // Start 3 workers if not running
     for (int i = 0; i < 3; i++) {
        if (!_workerActive[i]) {
           _workerActive[i] = true;
           _uploadWorker(i);
        }
     }
  }

  Future<void> _uploadWorker(int id) async {
     debugPrint('Worker $id started');
     while (true) {
        if (!mounted) break;
        
        // 1. Pick a job safely
        
        FileState? job;
        try {
           final pending = _uploadQueue.where((f) => !f.isUploaded && !f.isFailed && !f.isProcessing).toList();
           if (pending.isEmpty) {
              _checkUploadStatus(); // Check if all done
              break;
           }
           
           job = pending.first;
           job.isProcessing = true; // Mark as taken
        } catch (_) {
           break; 
        }
        
        // 2. Process
        try {
           await _uploadSingleFile(job);
        } catch (e) {
           debugPrint('Worker $id error: $e');
        }
        
        // 3. Update UI
        if (mounted) setState(() {});
        await Future.delayed(const Duration(milliseconds: 50));
     }
     
     _workerActive[id] = false;
     debugPrint('Worker $id finished');
     
     _checkUploadStatus();
  }

  void _checkUploadStatus() {
     // Failsafe: If no files are pending, stop spinner
     final pending = _uploadQueue.any((f) => !f.isUploaded && !f.isFailed);
     if (!pending && _isUploading) {
        if (mounted) {
           setState(() {
              _isUploading = false;
              _uploadQueue.clear();
              _uploadingName = '';
           });
           
           FileStorage.save(_files);
           _saveUrlCache();
           _syncIndexToCloud();
           _isProcessingQueue = false;

           ScaffoldMessenger.of(context).showSnackBar(SnackBar(
             content: Text('✓ Uploads completed', style: GoogleFonts.poppins()),
             backgroundColor: kTeal.withValues(alpha: 0.9),
             behavior: SnackBarBehavior.floating,
             shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
             margin: const EdgeInsets.all(16),
           ));
        }
     }
  }

  // Thumbnail Worker Pool
  final List<bool> _thumbWorkerActive = List.filled(6, false); // 6 concurrent thumbnail workers

  void _processThumbnailQueue() {
    for (int i = 0; i < 6; i++) {
       if (!_thumbWorkerActive[i]) {
          _thumbWorkerActive[i] = true;
          _thumbnailWorker(i);
       }
    }
  }

  Future<void> _thumbnailWorker(int id) async {
     while (true) {
        if (!mounted) break;

        // Priority Check: If viewer is open, pause background work
        if (_isViewerOpen) {
           await Future.delayed(const Duration(milliseconds: 500));
           continue;
        }

        CloudFile? job;
        try {
           if (_thumbnailQueue.isEmpty) break;
           job = _thumbnailQueue.removeAt(0); // FIFO: Take from top
        } catch (_) {
           break;
        }

        try {
          // Check existing
          if (await ThumbnailService().getExistingThumbnail(job.fileId) != null) {
             continue;
          }

          final url = await _svc.getFileUrl(job.fileId);
          if (url != null) {
            final res = await http.get(Uri.parse(url));
            if (res.statusCode == 200) {
               await ThumbnailService().generateThumbnail(job.fileId, res.bodyBytes);
               // Update UI occasionally or relies on periodic rebuilds? 
               // For now, let's just setState throttled or let the user scroll to trigger build
               if (mounted && _thumbnailQueue.length % 3 == 0) {
                  setState(() {});
               }
            }
          }
        } catch (e) {
           debugPrint('Thumbnail worker $id error: $e');
        }
     }
     _thumbWorkerActive[id] = false;
  }

  Future<void> _uploadSingleFile(FileState file) async {
    try {
      // 1. Encrypt File (In Memory - Optimized)
      if (mounted) setState(() => file.status = 'Encrypting...');
      final rawBytes = await File(file.path).readAsBytes();
      final encryptedBytes = await EncryptionService().encryptData(rawBytes);

      // 2. Upload Encrypted Bytes directly
      if (mounted) setState(() => file.status = 'Uploading...');
      final res = await _svc.sendDocumentBytes(
        chatId: widget.chatId,
        bytes: encryptedBytes,
        fileName: '${file.fileName}.enc',
        onSendProgress: (sent, total) {
          if (mounted) {
            setState(() {
              file.progress = sent / total;
            });
          }
        },
      );
      
      if (res != null) {
        final doc = res['document'] as Map<String, dynamic>?;
        final cf = CloudFile(
          fileName: '${file.fileName}.enc', // Store with .enc extension
          fileId: doc?['file_id'] ?? '',
          messageId: res['message_id'] ?? 0,
          uploadedAt: DateTime.now(),
          fileSize: file.fileSize, 
          thumbnailFileId: (doc?['thumbnail'] as Map<String, dynamic>?)?['file_id'],
        );

        // IMMEDIATE THUMBNAIL GENERATION
        // We use the encrypted bytes we just created to generate the thumbnail locally
        // This removes the need to download it later -> "No Spinner"
        try {
           final thumbResult = await ThumbnailService().generateThumbnail(cf.fileId, encryptedBytes);
           if (thumbResult != null) {
              // Also cache the raw bytes we have in memory for instant viewing
              _decryptedCache[cf.fileId] = rawBytes; 
           }
        } catch (e) {
           debugPrint('Immediate thumb gen known error (if not image): $e');
        }

        if (mounted) {
          setState(() {
            _files.insert(0, cf); // Uploaded files go to top
            file.isUploaded = true;
          });
        }
        
        // Pre-cache if image logic...
        // Note: Encrypted files don't have Telegram-generated thumbnails accessible easily 
        // because Telegram doesn't know it's an image.
        // So we might rely on the local file hash or just load on demand.
        // The previous logic for pre-caching thumbnails works only if Telegram generated them,
        // which it WON'T for .enc files.
        // So we should probably remove the thumbnail pre-fetch for .enc files to avoid 404s/errors.
        
      } else {
        file.isFailed = true;
      }
    } catch (e) {
      debugPrint('Upload error: $e');
      file.isFailed = true;
    }
  }

  Future<void> _refreshData() async {
    final newFiles = await _fetchIndexFromCloud();
    if (newFiles.isNotEmpty) {
      if (mounted) {
        setState(() {
          _files = newFiles;
        });
        await FileStorage.save(_files);
      }
    }
  }

  Future<void> _openFile(CloudFile file) async {
    if (file.isImage) {
      // Create a list of just images for the viewer to swipe through
      final images = _files.where((f) => f.isImage).toList();
      final initialIndex = images.indexWhere((f) => f.fileId == file.fileId);
      
      if (initialIndex == -1) return;

      // Pause background thumbnail generation
      _isViewerOpen = true;

      final result = await Navigator.push<String>(
        context,
        PageRouteBuilder(
          transitionDuration: const Duration(milliseconds: 300),
          pageBuilder: (_, a, b) => ImageViewerScreen(
            files: images,
            initialIndex: initialIndex,
            svc: _svc,
            chatId: widget.chatId,
            fullUrlCache: _fullUrlCache,
            thumbnailUrlCache: _urlCache,
            decryptedCache: _decryptedCache,
          ),
          transitionsBuilder: (_, anim, c, child) =>
              FadeTransition(opacity: anim, child: child),
        ),
      );

      // Resume background work
      _isViewerOpen = false;
      _processThumbnailQueue();

      if (result == 'deleted') {
         // Move to trash
         final now = DateTime.now();
         final fileToTrash = _files.firstWhere((f) => f.fileId == file.fileId);
         
         setState(() {
           _files.remove(fileToTrash);
            _trashFiles.add(CloudFile(
              fileName: fileToTrash.fileName,
              fileId: fileToTrash.fileId,
              messageId: fileToTrash.messageId,
              uploadedAt: fileToTrash.uploadedAt,
              fileSize: fileToTrash.fileSize,
              thumbnailFileId: fileToTrash.thumbnailFileId,
              localPath: fileToTrash.localPath,
              deletedAt: now,
            ));
         });
         await FileStorage.save(_files);
         await FileStorage.saveTrash(_trashFiles);
         _syncIndexToCloud();
      } else if (result == 'downloaded') {
         if (mounted) setState(() {});
      }
    } else {
      final result = await Navigator.push<String>(
        context,
        PageRouteBuilder(
          transitionDuration: const Duration(milliseconds: 300),
          pageBuilder: (_, a, b) =>
              FileViewerScreen(file: file, svc: _svc, chatId: widget.chatId),
          transitionsBuilder: (_, anim, c, child) =>
              FadeTransition(opacity: anim, child: child),
        ),
      );
      if (result == 'deleted') {
         // Move to trash
         final now = DateTime.now();
         
         setState(() {
           _files.remove(file);
            _trashFiles.add(CloudFile(
              fileName: file.fileName,
              fileId: file.fileId,
              messageId: file.messageId,
              uploadedAt: file.uploadedAt,
              fileSize: file.fileSize,
              thumbnailFileId: file.thumbnailFileId,
              localPath: file.localPath,
              deletedAt: now,
            ));
         });
         await FileStorage.save(_files);
         await FileStorage.saveTrash(_trashFiles);
         _syncIndexToCloud();
      } else if (result == 'downloaded') {
        await FileStorage.save(_files);
        if (mounted) setState(() {});
      }
    }
  }

  Future<void> _logout() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: kSurface,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(kRadius)),
        title: Text('Logout',
            style: GoogleFonts.poppins(
                fontWeight: FontWeight.w600, color: kTextPrimary)),
        content: Text('Disconnect from Telegram?',
            style: GoogleFonts.poppins(color: kTextSecondary)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('Cancel',
                  style: GoogleFonts.poppins(color: kTextSecondary))),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child:
                  Text('Logout', style: GoogleFonts.poppins(color: kError))),
        ],
      ),
    );
    if (ok != true) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefToken);
    await prefs.remove(_prefChatId);
    await prefs.remove(_prefUserName);
    if (!mounted) return;
    Navigator.of(context).pushReplacement(PageRouteBuilder(
      transitionDuration: const Duration(milliseconds: 500),
      pageBuilder: (_, a, b) => const LoginScreen(),
      transitionsBuilder: (_, anim, c, child) =>
          FadeTransition(opacity: anim, child: child),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: _isSelectionMode
          ? AppBar(
              backgroundColor: kSurface,
              leading: IconButton(
                icon: const Icon(Icons.close, color: kTextPrimary),
                onPressed: _exitSelectionMode,
              ),
              title: Text('${_selectedFileIds.length} Selected',
                  style: GoogleFonts.poppins(
                      color: kTextPrimary, fontWeight: FontWeight.w600)),
              actions: [
                IconButton(
                  icon: const Icon(Icons.delete_outline, color: kError),
                  onPressed: _moveToTrash,
                ),
                const SizedBox(width: 8),
              ],
            )
          : AppBar(
              backgroundColor: Colors.black,
              elevation: 0,
              centerTitle: false,
              title: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Obsidian',
                        style: GoogleFonts.poppins(
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                            color: kTextPrimary)),
                    Text('${_files.length} files · ${widget.userName}',
                        style: GoogleFonts.poppins(
                            fontSize: 12, color: kTextSecondary)),
                  ]),
              actions: [
                IconButton(
                    icon: const Icon(Icons.delete_sweep_outlined,
                        color: kTextSecondary),
                    tooltip: 'Trash',
                    onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => TrashScreen(
                                  trashFiles: _trashFiles,
                                  svc: _svc,
                                  chatId: widget.chatId,
                                  onRestore: _restoreFromTrash,
                                  onDeleteForever: _deleteForever,
                                )))),
                IconButton(
                    icon:
                        const Icon(Icons.logout_rounded, color: kTextSecondary),
                    tooltip: 'Logout',
                    onPressed: _logout),
                const SizedBox(width: 4),
              ],
            ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: kPrimary))
          : _files.isEmpty
              ? _buildEmpty()
              : _buildGallery(),
      floatingActionButton: FloatingActionButton(
        onPressed: _isUploading ? null : _pickAndUpload,
        backgroundColor: _isUploading ? kSurface : kPrimary,
        foregroundColor: _isUploading ? kTextSecondary : Colors.black,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(kRadius)),
        child: _isUploading
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                    strokeWidth: 2.5, color: kPrimary))
            : const Icon(Icons.add_rounded, size: 28),
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.cloud_off_rounded,
            size: 64, color: kTextSecondary.withValues(alpha: 0.4)),
        const SizedBox(height: 24),
        Text('No files yet',
            style: GoogleFonts.poppins(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: kTextPrimary)),
        const SizedBox(height: 8),
        Text('Tap + to upload your first file',
            style: GoogleFonts.poppins(fontSize: 14, color: kTextSecondary),
            textAlign: TextAlign.center),
      ]),
    );
  }

  Widget _buildGallery() {
    // Group by date
    final grouped = <String, List<CloudFile>>{};
    for (final f in _files) {
      final key = _dateHeader(f.uploadedAt);
      grouped.putIfAbsent(key, () => []).add(f);
    }

    return Stack(children: [
      RefreshIndicator(
        onRefresh: _refreshData,
        backgroundColor: kSurface,
        color: kPrimary,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            for (final entry in grouped.entries) ...[
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
                  child: Text(entry.key,
                      style: GoogleFonts.poppins(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: kTextPrimary)),
                ),
              ),
              SliverGrid(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 4,
                  crossAxisSpacing: 2,
                  mainAxisSpacing: 2,
                ),
                delegate: SliverChildBuilderDelegate(
                  (ctx, i) => _buildTile(entry.value[i]),
                  childCount: entry.value.length,
                ),
              ),
            ],
            const SliverPadding(padding: EdgeInsets.only(bottom: 100)),
          ],
        ),
      ),
      if (_isUploading) _buildUploadOverlay(),
    ]);
  }

  Widget _buildTile(CloudFile file) {
    final selected = _selectedFileIds.contains(file.fileId);
    return GestureDetector(
      onTap: () {
        if (_isSelectionMode) {
          _toggleSelection(file);
        } else {
          _openFile(file);
        }
      },
      onLongPress: () {
        if (!_isSelectionMode) {
          _toggleSelection(file);
        }
      },
      child: Stack(
        fit: StackFit.expand,
        children: [
          file.isImage ? _imageTile(file) : _fileTile(file),
          if (_isSelectionMode)
            Container(
              color: selected ? kPrimary.withValues(alpha: 0.4) : Colors.black45,
              padding: const EdgeInsets.all(8),
              alignment: Alignment.topRight,
              child: Icon(
                selected ? Icons.check_circle : Icons.radio_button_unchecked,
                color: selected ? Colors.white : Colors.white70,
                size: 20,
              ),
            ),
        ],
      ),
    );
  }

  void _toggleSelection(CloudFile file) {
    setState(() {
      _isSelectionMode = true;
      if (_selectedFileIds.contains(file.fileId)) {
        _selectedFileIds.remove(file.fileId);
        if (_selectedFileIds.isEmpty) _isSelectionMode = false;
      } else {
        _selectedFileIds.add(file.fileId);
      }
    });
  }

  void _exitSelectionMode() {
    setState(() {
      _isSelectionMode = false;
      _selectedFileIds.clear();
    });
  }

  Future<void> _moveToTrash() async {
    final count = _selectedFileIds.length;
    if (count == 0) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: kSurface,
        title: Text('Move to Trash?', style: GoogleFonts.poppins(color: kTextPrimary)),
        content: Text('Move $count items to trash? They will be permanently deleted after 15 days.',
            style: GoogleFonts.poppins(color: kTextSecondary)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('Cancel', style: GoogleFonts.poppins(color: kTextSecondary))),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text('Move to Trash', style: GoogleFonts.poppins(color: kError))),
        ],
      ),
    );

    if (confirm != true) return;

    final now = DateTime.now();
    final toRemove = _files.where((f) => _selectedFileIds.contains(f.fileId)).toList();

    setState(() {
      for (final f in toRemove) {
        _files.remove(f);
        // Create new CloudFile with DeletedAt set
        _trashFiles.add(CloudFile(
          fileName: f.fileName,
          fileId: f.fileId,
          messageId: f.messageId,
          uploadedAt: f.uploadedAt,
          fileSize: f.fileSize,
          thumbnailFileId: f.thumbnailFileId,
          localPath: f.localPath,
          deletedAt: now,
        ));
      }
      _exitSelectionMode();
    });

    await FileStorage.save(_files);
    await FileStorage.saveTrash(_trashFiles);
    _syncIndexToCloud();
  }

  Future<void> _restoreFromTrash(CloudFile file) async {
    setState(() {
      _trashFiles.remove(file);
      // Remove deletedAt by creating new object
      _files.insert(0, CloudFile(
        fileName: file.fileName,
        fileId: file.fileId,
        messageId: file.messageId,
        uploadedAt: file.uploadedAt,
        fileSize: file.fileSize,
        thumbnailFileId: file.thumbnailFileId,
        localPath: file.localPath,
        deletedAt: null,
      ));
    });
    await FileStorage.save(_files);
    await FileStorage.saveTrash(_trashFiles);
    _syncIndexToCloud();
  }

  Future<void> _deleteForever(CloudFile file) async {
    final success = await _svc.deleteMessage(widget.chatId, file.messageId);
    if (success) {
      if (file.localPath != null) {
        try { File(file.localPath!).deleteSync(); } catch (_) {}
      }
      setState(() => _trashFiles.remove(file));
      await FileStorage.saveTrash(_trashFiles);
    }
  }

  Future<Uint8List?> _loadEncryptedImage(CloudFile file) async {
    if (_decryptedCache.containsKey(file.fileId)) {
      return _decryptedCache[file.fileId];
    }

    try {
      String? url = _urlCache[file.fileId] ?? _fullUrlCache[file.fileId];
      if (url == null) {
        url = await _svc.getFileUrl(file.fileId);
        if (url != null && mounted) {
           _fullUrlCache[file.fileId] = url;
        }
      }

      if (url == null) return null;

      final res = await http.get(Uri.parse(url));
      if (res.statusCode == 200) {
        // Decrypt
        final decrypted = await EncryptionService().decryptData(res.bodyBytes);
        if (mounted && decrypted.isNotEmpty) {
           _decryptedCache[file.fileId] = decrypted;
        }
        return decrypted;
      }
    } catch (e) {
      debugPrint('Error loading encrypted image: $e');
    }
    return null;
  }

  Widget _imageTile(CloudFile file) {
    // 1. Check for local cached file first (uploaded/downloaded)
    if (file.localPath != null && File(file.localPath!).existsSync()) {
      return Image.file(File(file.localPath!), fit: BoxFit.cover);
    }

    // 2. Handle Encrypted Images via ThumbnailService
    if (file.fileName.endsWith('.enc')) {
      final thumbFile = ThumbnailService().getThumbnailFile(file.fileId);
      if (thumbFile.existsSync()) {
        return Image.file(thumbFile, fit: BoxFit.cover);
      } else {
        // Queue for generation (FIFO for initial load, LIFO for scroll)
        if (!_thumbnailQueue.any((f) => f.fileId == file.fileId)) {
           // If we are just loading normally, append to end (Top -> Bottom)
           _thumbnailQueue.add(file);
           _processThumbnailQueue();
        }

        return Container(
          color: kSurface,
          child: const Center(
            child: SizedBox(
              width: 16, height: 16,
              child: CircularProgressIndicator(strokeWidth: 1.5, color: kPrimary),
            ),
          ),
        );
      }
    }

    // 3. Legacy Unencrypted Images
    final id = file.thumbnailFileId ?? file.fileId;
    final url = _urlCache[id];
    if (url != null) {
      return CachedNetworkImage(
        imageUrl: url,
        fit: BoxFit.cover,
        memCacheWidth: 200,
        placeholder: (ctx, url) => Container(
          color: kSurface,
          child: const Center(
            child: SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 1.5, color: kPrimary),
            ),
          ),
        ),
        errorWidget: (ctx, url, error) => _fileTile(file),
      );
    }
    return Container(
        color: kSurface,
        child: const Center(
            child: SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                    strokeWidth: 1.5, color: kPrimary))));
  }

  Widget _fileTile(CloudFile file) {
    return Container(
      color: kSurface,
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(file.icon, size: 32, color: file.iconColor),
        const SizedBox(height: 6),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Text(file.fileName,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(fontSize: 10, color: kTextSecondary)),
        ),
      ]),
    );
  }

  Widget _buildUploadOverlay() {
    return Positioned(
      left: 16,
      right: 16,
      bottom: 80,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        decoration: BoxDecoration(
          color: kSurface,
          borderRadius: BorderRadius.circular(kRadius),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.5),
                blurRadius: 20,
                offset: const Offset(0, 8)),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const SizedBox(
                  width: 22,
                  height: 22,
                  child:
                      CircularProgressIndicator(strokeWidth: 2.5, color: kTeal)),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  'Uploading ${_uploadQueue.where((f) => !f.isUploaded).length} files...',
                  style: GoogleFonts.poppins(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: kTextPrimary),
                ),
              ),
            ]),
            if (_uploadQueue.isNotEmpty) ...[
              const SizedBox(height: 12),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 120),
                child: ListView.separated(
                  shrinkWrap: true,
                  physics: const BouncingScrollPhysics(),
                  itemCount: _uploadQueue.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (_, i) {
                    final f = _uploadQueue[i];
                    return Row(
                      children: [
                        Icon(f.isUploaded ? Icons.check_circle : Icons.upload_file,
                            size: 16,
                            color: f.isUploaded ? kTeal : kTextSecondary),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                             crossAxisAlignment: CrossAxisAlignment.start,
                             children: [
                                Text(f.fileName,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: GoogleFonts.poppins(
                                        fontSize: 12, color: kTextSecondary)),
                                if (!f.isUploaded && !f.isFailed)
                                   Text(f.status, 
                                      style: GoogleFonts.poppins(
                                          fontSize: 10, color: kPrimary)),
                             ],
                          ),
                        ),
                        if (!f.isUploaded && !f.isFailed)
                          Text('${(f.progress * 100).toInt()}%',
                              style: GoogleFonts.poppins(
                                  fontSize: 12, color: kTeal)),
                      ],
                    );
                  },
                ),
              ),
            ]
          ],
        ),
      ),
    );
  }
}

// ─── Image Viewer Screen (Google Photos Style with Swipe) ───────────────────

class ImageViewerScreen extends StatefulWidget {
  final List<CloudFile> files;
  final int initialIndex;
  final TelegramService svc;
  final String chatId;
  final Map<String, String> fullUrlCache;
  final Map<String, String> thumbnailUrlCache;
  final Map<String, Uint8List> decryptedCache;

  const ImageViewerScreen({
    super.key,
    required this.files,
    required this.initialIndex,
    required this.svc,
    required this.chatId,
    required this.fullUrlCache,
    required this.thumbnailUrlCache,
    required this.decryptedCache,
  });

  @override
  State<ImageViewerScreen> createState() => _ImageViewerScreenState();
}

class _ImageViewerScreenState extends State<ImageViewerScreen> {
  late PageController _pageController;
  late int _currentIndex;
  bool _downloading = false;
  bool _deleting = false;
  bool _showControls = true;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: _currentIndex);
    // Preload next image after frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _preload(_currentIndex + 1);
      _preload(_currentIndex - 1);
    });
  }

  void _onPageChanged(int index) {
    setState(() => _currentIndex = index);
    _preload(index + 1);
    _preload(index - 1);
  }

  Future<void> _preload(int index) async {
    if (index < 0 || index >= widget.files.length) return;
    final file = widget.files[index];
    if (file.fileName.endsWith('.enc')) {
       if (!widget.decryptedCache.containsKey(file.fileId)) {
          // Trigger load silently
          _loadEncryptedImage(file).then((bytes) {
             if (bytes != null && mounted) {
                setState(() {
                   widget.decryptedCache[file.fileId] = bytes;
                });
             }
          });
       }
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  CloudFile get _currentFile => widget.files[_currentIndex];

  String _formatDateTime(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${months[dt.month - 1]} ${dt.day}, ${dt.year} · $h:$m';
  }

  Future<void> _download() async {
    // Request permission first (Only needed for < Android 10)
    // On Android 10+ (SDK 29+), Scoped Storage allows saving images without WRITE_EXTERNAL_STORAGE.
    // However, checking SDK version without device_info_plus is tricky with just dart:io (Platform.version is string).
    // Simple approach: Try to save. If it fails, maybe request? 
    // Or just request permissions, and if they are permanently denied (Android 13), assume we don't need them and proceed.
    
    if (Platform.isAndroid) {
       var status = await Permission.storage.status;
       if (!status.isGranted) {
          status = await Permission.storage.request();
       }
       
       // On Android 13, storage might be permanently denied, but we can still save via MediaStore (ImageGallerySaver).
       // So we don't return early even if denied. We just try.
       // If we really need to check photos permission:
       if (await Permission.photos.status.isDenied) {
          await Permission.photos.request();
       }
    }

    setState(() => _downloading = true);
    try {
      // Get the image bytes
      Uint8List imageBytes;
      if (_currentFile.localPath != null &&
          File(_currentFile.localPath!).existsSync()) {
        imageBytes = await File(_currentFile.localPath!).readAsBytes();
      } else {
        // 1. Resolve URL
        final url = widget.fullUrlCache[_currentFile.fileId] ??
            await widget.svc.getFileUrl(_currentFile.fileId);
        if (url == null) throw Exception('Could not resolve file URL');
        
        // 2. Download
        final response = await http.get(Uri.parse(url));
        var bytes = response.bodyBytes;

        // 3. Decrypt if needed
        if (_currentFile.fileName.toLowerCase().endsWith('.enc')) {
           bytes = await EncryptionService().decryptData(bytes);
        }
        imageBytes = bytes;
      }

      // Save to temp file first, then use saveFile for lossless gallery save
      // Fix: Strip .enc extension so Gallery Saver detects MIME type correctly
      var saveName = _currentFile.fileName;
      if (saveName.endsWith('.enc')) {
         saveName = saveName.substring(0, saveName.length - 4);
      }
      
      final dir = await getTemporaryDirectory();
      final tempFile = File('${dir.path}/$saveName');
      await tempFile.writeAsBytes(imageBytes);

      final result = await ImageGallerySaverPlus.saveFile(tempFile.path,
          name: 'Obsidian_${DateTime.now().millisecondsSinceEpoch}');

      // Cleanup temp file
      try { await tempFile.delete(); } catch (_) {}

      final isSuccess = result['isSuccess'] == true;

      if (mounted) {
        setState(() => _downloading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Row(children: [
            Icon(isSuccess ? Icons.check_circle : Icons.error,
                color: Colors.white, size: 18),
            const SizedBox(width: 8),
            Text(isSuccess ? 'Saved to gallery' : 'Failed to save',
                style: GoogleFonts.poppins(fontSize: 13, color: Colors.white)),
          ]),
          backgroundColor: isSuccess ? const Color(0xFF2E7D32) : kError,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          margin: const EdgeInsets.all(16),
        ));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _downloading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Row(children: [
            const Icon(Icons.error, color: Colors.white, size: 18),
            const SizedBox(width: 8),
            Text('Save failed', style: GoogleFonts.poppins(fontSize: 13, color: Colors.white)),
          ]),
          backgroundColor: kError.withValues(alpha: 0.9),
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          margin: const EdgeInsets.all(16),
        ));
      }
    }
  }




  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: kSurface,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(kRadius)),
        title: Text('Move to Trash',
            style: GoogleFonts.poppins(
                fontWeight: FontWeight.w600, color: kTextPrimary)),
        content: Text('Move this photo to trash? It will be deleted permanently after 15 days.',
            style: GoogleFonts.poppins(color: kTextSecondary)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('Cancel',
                  style: GoogleFonts.poppins(color: kTextSecondary))),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child:
                  Text('Move to Trash', style: GoogleFonts.poppins(color: kError))),
        ],
      ),
    );
    if (ok != true) return;

    // Return true to indicate we should delete (move to trash)
    Navigator.pop(context, 'deleted');
  }

  /// Get the thumbnail URL for a file (used for instant preview)
  String? _getThumbnailUrl(CloudFile file) {
    final thumbId = file.thumbnailFileId ?? file.fileId;
    return widget.thumbnailUrlCache[thumbId];
  }

  Widget _buildImagePage(CloudFile file) {
    // Check local file first — instant, no loading
    if (file.localPath != null && File(file.localPath!).existsSync()) {
      return InteractiveViewer(
        minScale: 0.5,
        maxScale: 5.0,
        child: Image.file(
          File(file.localPath!),
          fit: BoxFit.contain,
        ),
      );
    }

    // Google Photos style: show thumbnail instantly, load full-res on top
    final thumbUrl = _getThumbnailUrl(file);
    final fullUrl = widget.fullUrlCache[file.fileId];
    final isEncrypted = file.fileName.toLowerCase().endsWith('.enc');

    // Check for local thumbnail (Encrypted files)
    File? localThumb;
    if (isEncrypted) {
      final f = ThumbnailService().getThumbnailFile(file.fileId);
      if (f.existsSync()) localThumb = f;
    }

    return InteractiveViewer(
      minScale: 0.5,
      maxScale: 5.0,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Layer 1: Thumbnail (instant)
          if (localThumb != null)
             Image.file(localThumb, fit: BoxFit.contain, width: double.infinity, height: double.infinity)
          else if (thumbUrl != null)
            CachedNetworkImage(
              imageUrl: thumbUrl,
              fit: BoxFit.contain,
              width: double.infinity,
              height: double.infinity,
              errorWidget: (_, url, e) => const SizedBox.shrink(),
            ),

          // Layer 2: Full resolution image on top
          if (fullUrl != null && !isEncrypted)
            CachedNetworkImage(
              imageUrl: fullUrl,
              fit: BoxFit.contain,
              width: double.infinity,
              height: double.infinity,
              placeholder: (_, url) => const SizedBox.shrink(), // Thumbnail is visible
              errorWidget: (_, url, e) => const SizedBox.shrink(),
            )
          else
            FutureBuilder<Uint8List?>(
              initialData: widget.decryptedCache[file.fileId],
              future: _loadEncryptedImage(file),
              builder: (context, snapshot) {
                if (snapshot.hasData && snapshot.data != null) {
                  return Image.memory(
                    snapshot.data!,
                    fit: BoxFit.contain,
                    width: double.infinity,
                    height: double.infinity,
                  );
                }
                // While loading, the thumbnail (Layer 1) is shown.
                // We can add a loading indicator on top if we want, but "Google Photos" style usually just shows blurry thumb.
                // Let's add a small spinner if no thumbnail exists.
                if (localThumb == null && thumbUrl == null) {
                   return const Center(child: CircularProgressIndicator(color: kPrimary));
                }
                return const SizedBox.shrink(); 
              },
            ),
        ],
      ),
    );
  }

  Future<Uint8List?> _loadEncryptedImage(CloudFile file) async {
     // Check memory cache first
     if (widget.decryptedCache.containsKey(file.fileId)) {
        return widget.decryptedCache[file.fileId];
     }
     try {
       // 1. Get URL
       final url = widget.fullUrlCache[file.fileId] ?? await widget.svc.getFileUrl(file.fileId);
       if (url == null) return null;
       widget.fullUrlCache[file.fileId] = url;

       // 2. Download Bytes
       final response = await http.get(Uri.parse(url));
       final bytes = response.bodyBytes;

       // 3. Decrypt if needed
       if (file.fileName.toLowerCase().endsWith('.enc')) {
          final decrypted = await EncryptionService().decryptData(bytes);
          if (decrypted.isNotEmpty) {
             widget.decryptedCache[file.fileId] = decrypted;
          }
          return decrypted;
       } else {
          return bytes; // Legacy unencrypted files
       }
     } catch (e) {
       debugPrint('Error loading image: $e');
       return null;
     }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      body: GestureDetector(
        onTap: () => setState(() => _showControls = !_showControls),
        child: Stack(
          children: [
            // Image PageView (swipeable)
            PageView.builder(
              controller: _pageController,
              itemCount: widget.files.length,
              onPageChanged: (index) {
                setState(() => _currentIndex = index);
                
                // Preload Next
                if (index + 1 < widget.files.length) {
                   _loadEncryptedImage(widget.files[index + 1]);
                }
                // Preload Previous
                if (index - 1 >= 0) {
                   _loadEncryptedImage(widget.files[index - 1]);
                }
              },
              itemBuilder: (context, index) {
                return Center(child: _buildImagePage(widget.files[index]));
              },
            ),

            // Top bar (overlay)
            if (_showControls)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withValues(alpha: 0.7),
                        Colors.transparent,
                      ],
                    ),
                  ),
                  child: SafeArea(
                    bottom: false,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 4, vertical: 4),
                      child: Row(
                        children: [
                          IconButton(
                            icon: const Icon(Icons.arrow_back,
                                color: Colors.white),
                            onPressed: () => Navigator.pop(context),
                          ),
                          const Spacer(),
                          Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                _formatDateTime(_currentFile.uploadedAt)
                                    .split(' · ')
                                    .first,
                                style: GoogleFonts.poppins(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                    color: Colors.white),
                              ),
                              Text(
                                _formatDateTime(_currentFile.uploadedAt)
                                    .split(' · ')
                                    .last,
                                style: GoogleFonts.poppins(
                                    fontSize: 12, color: Colors.white70),
                              ),
                            ],
                          ),
                          const Spacer(),
                          // Placeholder for symmetry
                          const SizedBox(width: 48),
                        ],
                      ),
                    ),
                  ),
                ),
              ),

            // Bottom bar (Google Photos style)
            if (_showControls)
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [
                        Colors.black.withValues(alpha: 0.7),
                        Colors.transparent,
                      ],
                    ),
                  ),
                  child: SafeArea(
                    top: false,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          _bottomAction(
                            icon: Icons.share_outlined,
                            label: 'Share',
                            onTap: () {},
                          ),
                          _bottomAction(
                            icon: _downloading
                                ? Icons.hourglass_top_rounded
                                : Icons.download_outlined,
                            label: _downloading ? 'Saving...' : 'Save',
                            onTap: _downloading ? null : _download,
                          ),
                          _bottomAction(
                            icon: _deleting
                                ? Icons.hourglass_top_rounded
                                : Icons.delete_outline,
                            label: _deleting ? 'Deleting...' : 'Delete',
                            onTap: _deleting ? null : _delete,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _bottomAction({
    required IconData icon,
    required String label,
    VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon,
              color: onTap == null ? Colors.white38 : Colors.white, size: 24),
          const SizedBox(height: 4),
          Text(label,
              style: GoogleFonts.poppins(
                  fontSize: 11,
                  color: onTap == null ? Colors.white38 : Colors.white70)),
        ],
      ),
    );
  }
}

// ─── File Viewer Screen (Non-Image Files) ───────────────────────────────────

class FileViewerScreen extends StatefulWidget {
  final CloudFile file;
  final TelegramService svc;
  final String chatId;

  const FileViewerScreen(
      {super.key, required this.file, required this.svc, required this.chatId});

  @override
  State<FileViewerScreen> createState() => _FileViewerScreenState();
}

class _FileViewerScreenState extends State<FileViewerScreen> {
  bool _downloading = false;
  bool _deleting = false;

  Future<void> _download() async {
    setState(() => _downloading = true);
    try {
      final url = await widget.svc.getFileUrl(widget.file.fileId);
      if (url == null) throw Exception('Could not resolve file URL');

      final response = await http.get(Uri.parse(url));
      final dir = await getApplicationDocumentsDirectory();
      final dlDir = Directory('${dir.path}/Obsidian');
      await dlDir.create(recursive: true);
      final local = File('${dlDir.path}/${widget.file.fileName}');
      await local.writeAsBytes(response.bodyBytes);

      widget.file.localPath = local.path;

      if (mounted) {
        setState(() => _downloading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Saved to ${local.path}',
              style: GoogleFonts.poppins(fontSize: 13)),
          backgroundColor: kSurface,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          margin: const EdgeInsets.all(16),
        ));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _downloading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Download failed',
              style: GoogleFonts.poppins(fontSize: 13)),
          backgroundColor: kError.withValues(alpha: 0.9),
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          margin: const EdgeInsets.all(16),
        ));
      }
    }
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: kSurface,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(kRadius)),
        title: Text('Move to Trash',
            style: GoogleFonts.poppins(
                fontWeight: FontWeight.w600, color: kTextPrimary)),
        content: Text('Move "${widget.file.fileName}" to trash? It will be deleted permanently after 15 days.',
            style: GoogleFonts.poppins(color: kTextSecondary)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('Cancel',
                  style: GoogleFonts.poppins(color: kTextSecondary))),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child:
                  Text('Move to Trash', style: GoogleFonts.poppins(color: kError))),
        ],
      ),
    );
    if (ok != true) return;

    // Return 'deleted' specifically
    Navigator.pop(context, 'deleted');
  }

  String _formatDateTime(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${months[dt.month - 1]} ${dt.day}, ${dt.year} · $h:$m';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(widget.file.fileName,
              style: GoogleFonts.poppins(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: kTextPrimary),
              overflow: TextOverflow.ellipsis),
          Text(widget.file.formattedSize,
              style:
                  GoogleFonts.poppins(fontSize: 12, color: kTextSecondary)),
        ]),
      ),
      body: Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: widget.file.iconColor.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child:
                Icon(widget.file.icon, size: 64, color: widget.file.iconColor),
          ),
          const SizedBox(height: 24),
          Text(widget.file.fileName,
              style: GoogleFonts.poppins(
                  fontSize: 18,
                  fontWeight: FontWeight.w500,
                  color: kTextPrimary),
              textAlign: TextAlign.center),
          const SizedBox(height: 8),
          Text(widget.file.formattedSize,
              style: GoogleFonts.poppins(fontSize: 14, color: kTextSecondary)),
          const SizedBox(height: 4),
          Text(_formatDateTime(widget.file.uploadedAt),
              style: GoogleFonts.poppins(fontSize: 13, color: kTextSecondary)),
        ]),
      ),
      bottomNavigationBar: Container(
        color: Colors.black,
        padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).padding.bottom + 12,
            top: 12,
            left: 16,
            right: 16),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
          _actionBtn(
            icon: _downloading
                ? Icons.hourglass_top_rounded
                : Icons.download_outlined,
            label: _downloading ? 'Saving...' : 'Save',
            onTap: _downloading ? null : _download,
          ),
          _actionBtn(
            icon: _deleting
                ? Icons.hourglass_top_rounded
                : Icons.delete_outline,
            label: _deleting ? 'Deleting...' : 'Delete',
            onTap: _deleting ? null : _delete,
          ),
        ]),
      ),
    );
  }

  Widget _actionBtn({
    required IconData icon,
    required String label,
    VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon,
            color: onTap == null ? Colors.white38 : Colors.white, size: 24),
        const SizedBox(height: 4),
        Text(label,
            style: GoogleFonts.poppins(
                fontSize: 11,
                color: onTap == null ? Colors.white38 : Colors.white70)),
      ]),
    );
  }
}
// ─── Trash Screen ──────────────────────────────────────────────────────────

class TrashScreen extends StatefulWidget {
  final List<CloudFile> trashFiles;
  final TelegramService svc;
  final String chatId;
  final Function(CloudFile) onRestore;
  final Function(CloudFile) onDeleteForever;

  const TrashScreen({
    super.key,
    required this.trashFiles,
    required this.svc,
    required this.chatId,
    required this.onRestore,
    required this.onDeleteForever,
  });

  @override
  State<TrashScreen> createState() => _TrashScreenState();
}

class _TrashScreenState extends State<TrashScreen> {
  bool _isProcessing = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: Text('Trash', style: GoogleFonts.poppins(color: kTextPrimary)),
        actions: [
          if (widget.trashFiles.isNotEmpty)
            TextButton(
              onPressed: _emptyTrash,
              child: Text('Empty Trash', style: GoogleFonts.poppins(color: kError)),
            )
        ],
      ),
      body: widget.trashFiles.isEmpty
          ? Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.delete_outline, size: 64, color: kTextSecondary.withValues(alpha: 0.3)),
                const SizedBox(height: 16),
                Text('Trash is empty', style: GoogleFonts.poppins(color: kTextSecondary)),
              ]),
            )
          : GridView.builder(
              padding: const EdgeInsets.all(2),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                crossAxisSpacing: 2,
                mainAxisSpacing: 2,
              ),
              itemCount: widget.trashFiles.length,
              itemBuilder: (ctx, i) => _buildTrashTile(widget.trashFiles[i]),
            ),
    );
  }

  Widget _buildTrashTile(CloudFile file) {
    // Default to 15 days if deletedAt is somehow null
    final deletedAt = file.deletedAt ?? DateTime.now();
    final daysLeft = 15 - (DateTime.now().difference(deletedAt).inDays);
    
    return GestureDetector(
      onTap: () => _showOptions(file),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Opacity(
            opacity: 0.7,
            child: file.isImage ? _buildImagePreview(file) : _buildFilePreview(file),
          ),
          Positioned(
            bottom: 4,
            right: 4,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                '$daysLeft days left',
                style: GoogleFonts.poppins(fontSize: 10, color: Colors.white),
              ),
            ),
          )
        ],
      ),
    );
  }

  Widget _buildImagePreview(CloudFile file) {
    // 1. Check local file (instant)
    if (file.localPath != null && File(file.localPath!).existsSync()) {
      return Image.file(File(file.localPath!), fit: BoxFit.cover);
    }

    // 2. Check encrypted thumbnail
    if (file.fileName.endsWith('.enc')) {
       final thumbFile = ThumbnailService().getThumbnailFile(file.fileId);
       if (thumbFile.existsSync()) {
          return Image.file(thumbFile, fit: BoxFit.cover);
       }
       // We don't generate thumbnails in trash, just show generic placeholder if missing
       return Container(
          color: kSurface,
          child: const Center(child: Icon(Icons.lock, color: kTextSecondary, size: 24)),
       );
    }

    // 3. Legacy CachedNetworkImage
    final id = file.thumbnailFileId ?? file.fileId;
    return FutureBuilder<String?>(
      future: widget.svc.getFileUrl(id),
      builder: (context, snapshot) {
        if (snapshot.hasData) {
          return CachedNetworkImage(
            imageUrl: snapshot.data!,
            fit: BoxFit.cover,
            memCacheWidth: 200,
            placeholder: (ctx, url) => Container(color: kSurface),
            errorWidget: (ctx, url, error) => Container(color: kSurface),
          );
        }
        return Container(color: kSurface);
      },
    );
  }

  Widget _buildFilePreview(CloudFile file) {
    return Container(
      color: kSurface,
      alignment: Alignment.center,
      child: Icon(file.icon, color: file.iconColor, size: 32),
    );
  }

  void _showOptions(CloudFile file) {
    showModalBottomSheet(
      context: context,
      backgroundColor: kCardDark,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.restore, color: Colors.white),
              title: Text('Restore', style: GoogleFonts.poppins(color: Colors.white)),
              onTap: () {
                Navigator.pop(context);
                widget.onRestore(file);
                // Force UI update
                setState(() {});
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_forever, color: kError),
              title: Text('Delete Forever', style: GoogleFonts.poppins(color: kError)),
              onTap: () async {
                Navigator.pop(context);
                setState(() => _isProcessing = true);
                await widget.onDeleteForever(file);
                if (mounted) {
                  setState(() {
                    _isProcessing = false;
                    // Ensure the file is removed from the view if the parent didn't trigger a rebuild (which it won't for a pushed route)
                    if (widget.trashFiles.contains(file)) {
                      widget.trashFiles.remove(file);
                    }
                  });
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _emptyTrash() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: kSurface,
        title: Text('Empty Trash?', style: GoogleFonts.poppins(color: kTextPrimary)),
        content: Text('Permanently delete all items? This cannot be undone.',
            style: GoogleFonts.poppins(color: kTextSecondary)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('Cancel', style: GoogleFonts.poppins(color: kTextSecondary))),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text('Empty Trash', style: GoogleFonts.poppins(color: kError))),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() {
      _isProcessing = true;
    });

    // Make a copy to iterate
    final files = List<CloudFile>.from(widget.trashFiles);
    
    // Process in batches of 5 for speed but safety
    final batches = <List<CloudFile>>[];
    for (var i = 0; i < files.length; i += 5) {
      batches.add(files.sublist(i, i + 5 > files.length ? files.length : i + 5));
    }

    for (final batch in batches) {
       await Future.wait(batch.map((f) => widget.onDeleteForever(f)));
    }

    if (mounted) {
       setState(() {
         _isProcessing = false;
       });
       // List should already be empty as onDeleteForever modifies it
    }
  }
}
