import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Como o botão de gravação do canal se comporta.
enum RecordMode {
  /// Segurar para gravar, soltar para enviar.
  hold,

  /// Toque para começar, toque de novo para parar e enviar.
  tap,
}

class AppConfig {
  static const _serverKey = 'server_url';
  static const _recordModeKey = 'record_mode';

  static String get defaultServerUrl {
    if (kIsWeb) return 'http://localhost:8080';
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      return 'http://10.0.2.2:8080';
    }
    return 'http://localhost:8080';
  }

  static Future<String> loadServerUrl() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_serverKey) ?? defaultServerUrl;
  }

  static Future<void> saveServerUrl(String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_serverKey, value.trim());
  }

  static Future<RecordMode> loadRecordMode() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_recordModeKey) == 'tap'
        ? RecordMode.tap
        : RecordMode.hold;
  }

  static Future<void> saveRecordMode(RecordMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _recordModeKey, mode == RecordMode.tap ? 'tap' : 'hold');
  }
}