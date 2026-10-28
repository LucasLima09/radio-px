import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../models/auth_session.dart';
import '../../models/public_user.dart';

/// Sessão do usuário persistida no dispositivo.
class SessionStore {
  static const _key = 'auth_session';

  Future<void> save(AuthSession session) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(session.toJson()));
  }

  Future<AuthSession?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return null;
    try {
      return AuthSession.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }

  /// Atualiza só o usuário da sessão, preservando os tokens.
  Future<void> updateUser(PublicUser user) async {
    final session = await load();
    if (session == null || session.user.id != user.id) return;
    await save(
      AuthSession(
        accessToken: session.accessToken,
        refreshToken: session.refreshToken,
        expiresAt: session.expiresAt,
        user: user,
      ),
    );
  }
}
