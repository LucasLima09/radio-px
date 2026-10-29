import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../models/auth_session.dart';
import '../../models/channel.dart';
import '../../models/public_user.dart';
import '../storage/session_store.dart';
import 'api_exception.dart';

/// Cliente HTTP do servidor do Radio PX.
///
/// Também é o dono do ciclo do token de acesso: renova antes de expirar e
/// persiste a sessão renewed para que o app sobreviva a ser encerrado.
class ApiClient {
  ApiClient({
    required this.baseUrl,
    required this.sessionStore,
    http.Client? httpClient,
  }) : _http = httpClient ?? http.Client();

  final String baseUrl;
  final SessionStore sessionStore;
  final http.Client _http;

  /// Renovação em andamento, compartilhada por quem pedir outra ao mesmo
  /// tempo: o refresh token é de uso único, então duas renovações paralelas
  /// com ele derrubariam a sessão.
  Future<bool>? _refreshing;

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
    final res = await _request('POST', '/api/v1/auth/login', {
      'username': username,
      'password': password,
    });
    final session = AuthSession.fromJson(_decode(res));
    setSession(session);
    await sessionStore.save(session);
    return session;
  }

  Future<PublicUser> register({
    required String username,
    required String firstName,
    required String lastName,
    required String password,
  }) async {
    final res = await _request('POST', '/api/v1/auth/register', {
      'username': username,
      'firstName': firstName,
      'lastName': lastName,
      'password': password,
    });
    return PublicUser.fromJson(_decode(res));
  }

  Future<bool> refresh() {
    return _refreshing ??= _refresh().whenComplete(() => _refreshing = null);
  }

  Future<bool> _refresh() async {
    // O beacon (outro isolate) pode ter renovado antes: nesse caso o token em
    // memória já foi revogado e o salvo no disco é o válido.
    if (await _adoptStoredSession() && !_isExpired()) return true;

    final rt = _refreshToken;
    if (rt == null) return false;
    http.Response res;
    try {
      res = await _http
          .post(
            _uri('/api/v1/auth/refresh'),
            headers: _headers(false),
            body: jsonEncode({'refreshToken': rt}),
          )
          .timeout(_timeout);
    } catch (_) {
      return false;
    }
    if (res.statusCode != 200) {
      // Recusado porque o outro isolate renovou com o mesmo token ao mesmo
      // tempo: a sessão dele já está no disco.
      if (await _adoptStoredSession()) return true;
      _accessToken = null;
      _accessTokenExpiresAt = 0;
      return false;
    }
    final session = AuthSession.fromJson(_decode(res));
    setSession(session);
    await sessionStore.save(session);
    return true;
  }

  /// Assume a sessão salva quando ela traz um refresh token diferente do que
  /// está em memória, ou seja, foi renovada por outro isolate.
  Future<bool> _adoptStoredSession() async {
    final stored = await sessionStore.load();
    if (stored == null || stored.refreshToken == _refreshToken) return false;
    setSession(stored);
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

  Future<PublicUser> getProfile() async {
    final data = await _authed('GET', '/api/v1/profile');
    final user = PublicUser.fromJson(data as Map<String, dynamic>);
    await sessionStore.updateUser(user);
    return user;
  }

  Future<PublicUser> updateProfile({
    required String username,
    String? firstName,
    String? lastName,
    String? vehiclePlate,
    String? phone,
    String? avatar,
  }) async {
    final data = await _authed('PATCH', '/api/v1/profile', {
      'username': username,
      'firstName': ?firstName,
      'lastName': ?lastName,
      'vehiclePlate': ?vehiclePlate,
      'phone': ?phone,
      'avatar': ?avatar,
    });
    final user = PublicUser.fromJson(data as Map<String, dynamic>);
    await sessionStore.updateUser(user);
    return user;
  }

  Future<Channel> createChannel(String name) async {
    final data = await _authed('POST', '/api/v1/channels', {
      'name': name,
      'isPrivate': false,
    });
    return Channel.fromJson(data as Map<String, dynamic>);
  }

  Future<Channel> joinChannel(String id) async {
    final data = await _authed('POST', '/api/v1/channels/$id/join');
    return Channel.fromJson(data as Map<String, dynamic>);
  }

  /// Reporta a posição atual. Chamado pelo beacon em segundo plano; a resposta
  /// é 204, sem corpo.
  Future<void> sendLocation(double lat, double lng) async {
    await _authed('POST', '/api/v1/locations', {'lat': lat, 'lng': lng});
  }

  static const _timeout = Duration(seconds: 15);

  Future<dynamic> _authed(
    String method,
    String path, [
    Map<String, dynamic>? body,
  ]) async {
    var res = await _request(method, path, body, true);
    if (res.statusCode == 401 && _accessToken != null && await refresh()) {
      res = await _request(method, path, body, true);
    }
    return _decode(res);
  }

  Future<http.Response> _request(
    String method,
    String path, [
    Map<String, dynamic>? body,
    bool authed = false,
  ]) async {
    final req = http.Request(method, _uri(path));
    req.headers.addAll(_headers(authed));
    if (body != null) req.body = jsonEncode(body);
    try {
      final streamed = await _http.send(req).timeout(_timeout);
      return await http.Response.fromStream(streamed).timeout(_timeout);
    } on TimeoutException {
      throw ApiException(
        0,
        'O servidor $baseUrl não respondeu em 15 segundos. Verifique a conexão e o endereço.',
      );
    } on http.ClientException catch (error) {
      throw ApiException(0, 'Falha ao acessar $baseUrl: ${error.message}');
    }
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
        res.statusCode,
        'Resposta inválida do servidor (não é JSON)',
      );
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
