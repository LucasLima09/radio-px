import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/record_mode.dart';

/// Configurações persistidas do app no dispositivo.
class AppConfig {
  static const _serverKey = 'server_url';
  static const _compiledServerKey = 'compiled_server_url';
  static const _recordModeKey = 'record_mode';

  /// Endereço usado quando o usuário ainda não configurou nenhum.
  String get defaultServerUrl {
    const configured = String.fromEnvironment('SERVER_URL');
    if (configured.isNotEmpty) return configured;
    if (kIsWeb) return 'http://localhost:8080';
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      return 'http://10.0.2.2:8080';
    }
    return 'http://localhost:8080';
  }

  Future<String> loadServerUrl() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_serverKey);
    const configured = String.fromEnvironment('SERVER_URL');
    // Apply a new bundled endpoint once; later manual edits remain available.
    if (configured.isNotEmpty && configured.startsWith('https://') &&
        prefs.getString(_compiledServerKey) != configured) {
      await prefs.setString(_serverKey, configured);
      await prefs.setString(_compiledServerKey, configured);
      return configured;
    }
    return saved ?? defaultServerUrl;
  }

  Future<void> saveServerUrl(String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_serverKey, value.trim());
  }

  Future<RecordMode> loadRecordMode() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_recordModeKey) == 'tap'
        ? RecordMode.tap
        : RecordMode.hold;
  }

  Future<void> saveRecordMode(RecordMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _recordModeKey, mode == RecordMode.tap ? 'tap' : 'hold');
  }

  String _lastHeardKey(String channelId) => 'last_heard_$channelId';

  /// Último áudio que terminou de tocar neste canal, usado para não reenviar
  /// o que o aparelho já ouviu ao reconectar.
  Future<int> loadLastHeardSeq(String channelId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_lastHeardKey(channelId)) ?? 0;
  }

  Future<void> saveLastHeardSeq(String channelId, int seq) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_lastHeardKey(channelId), seq);
  }
}
