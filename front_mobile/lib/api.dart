import 'dart:convert';

import 'package:http/http.dart' as http;

import 'models.dart';
import 'session_store.dart';

class ApiException implements Exception {
  final int statusCode;
  final String message;

  ApiException(this.statusCode, this.message);

  @override
  String toString() => message;
}

class ApiClient {
  final String baseUrl;

  ApiClient(this.baseUrl);

  String? _accessToken;
  String? _refreshToken;
  int _accessTokenExpiresAt = 0;

  String? get accessToken => _accessToken;

  void setSession(AuthSession session) {
    _accessToken = session.accessToken;
    _refreshToken = session.refreshToken;
    _accessTokenExpiresAt = session.expiresAt;
  }

  Uri _uri(String path) => Uri.parse('$baseUrl$path');

  Future<AuthSession> login(String username, String password) async {
    final res = await _request(
        'POST', '/api/v1/auth/login', {'username': username, 'password': password});
    final session = AuthSession.fromJson(_decode(res));
    setSession(session);
    await SessionStore.save(session);
    return session;
  }

  Future<PublicUser> register(String username, String password) async {
    final res = await _request(
        'POST', '/api/v1/auth/register', {'username': username, 'password': password});
    return PublicUser.fromJson(_decode(res));
  }

  Future<bool> refresh() async {
    final rt = _refreshToken;
    if (rt == null) return false;
    http.Response res;
    try {
      res = await http.post(_uri('/api/v1/auth/refresh'),
          headers: _headers(false),
          body: jsonEncode({'refreshToken': rt})).timeout(_timeout);
    } catch (_) {
      return false;
    }
    if (res.statusCode != 200) {
      _accessToken = null;
      _accessTokenExpiresAt = 0;
      return false;
    }
    final session = AuthSession.fromJson(_decode(res));
    setSession(session);
    await SessionStore.save(session);
    return true;
  }

  /// Margem para não abrir o WebSocket com um token que expira no meio do
  /// handshake.
  static const _tokenExpiryMargin = Duration(seconds: 30);

  /// Devolve um token de acesso válido, renovando quando necessário.
  ///
  /// A renovação é decidida por tempo de vida, e não por resposta 401, porque o
  /// WebSocket não tem como reagir a um 401 no handshake: sem isso, uma
  /// reconexão automática depois de o token expirar repetiria indefinidamente o
  /// mesmo token recusado.
  Future<String> ensureAccessToken() async {
    if (_accessToken != null && !_isExpired()) return _accessToken!;
    if (await refresh()) return _accessToken!;
    throw ApiException(401, 'Sessão expirada');
  }

  bool _isExpired() {
    if (_accessTokenExpiresAt <= 0) return false;
    return _accessTokenExpiresAt - _tokenExpiryMargin.inSeconds <=
        DateTime.now().millisecondsSinceEpoch ~/ 1000;
  }

  Future<List<Channel>> listChannels() async {
    final data = await _authed('GET', '/api/v1/channels');
    return (data as List)
        .map((e) => Channel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<Channel> createChannel(String name) async {
    final data =
        await _authed('POST', '/api/v1/channels', {'name': name, 'isPrivate': false});
    return Channel.fromJson(data as Map<String, dynamic>);
  }

  Future<Channel> joinChannel(String id) async {
    final data = await _authed('POST', '/api/v1/channels/$id/join');
    return Channel.fromJson(data as Map<String, dynamic>);
  }

  static const _timeout = Duration(seconds: 15);

  Future<dynamic> _authed(String method, String path, [Map<String, dynamic>? body]) async {
    var res = await _request(method, path, body, true);
    if (res.statusCode == 401 && _accessToken != null && await refresh()) {
      res = await _request(method, path, body, true);
    }
    return _decode(res);
  }

  Future<http.Response> _request(String method, String path,
      [Map<String, dynamic>? body, bool authed = false]) async {
    final req = http.Request(method, _uri(path));
    req.headers.addAll(_headers(authed));
    if (body != null) req.body = jsonEncode(body);
    final streamed = await req.send().timeout(_timeout);
    return http.Response.fromStream(streamed);
  }

  Map<String, String> _headers(bool authed) => {
        'Content-Type': 'application/json',
        'ngrok-skip-browser-warning': '1',
        if (authed && _accessToken != null) 'Authorization': 'Bearer $_accessToken',
      };

  dynamic _decode(http.Response res) {
    if (res.statusCode >= 400) throw _errorFrom(res);
    final text = res.body.trim();
    if (text.isEmpty) return null;
    try {
      return jsonDecode(text);
    } catch (_) {
      throw ApiException(
          res.statusCode, 'Resposta inválida do servidor (não é JSON)');
    }
  }

  ApiException _errorFrom(http.Response res) {
    String message = 'Erro ${res.statusCode}';
    try {
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      message = body['error'] as String? ?? message;
    } catch (_) {}
    return ApiException(res.statusCode, message);
  }
}