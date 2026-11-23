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

  /// Lê a sessão do disco. O beacon roda em outro isolate e também renova os
  /// tokens; o reload descarta o cache em memória deste isolate para enxergar
  /// a sessão mais recente gravada por qualquer um dos dois.
  Future<AuthSession?> load() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
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
