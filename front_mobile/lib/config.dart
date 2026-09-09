import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppConfig {
  static const _serverKey = 'server_url';

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
}