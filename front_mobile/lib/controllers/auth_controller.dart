import 'package:flutter/foundation.dart';

import 'app_controller.dart';
import '../di.dart';
import '../models/active_session.dart';
import '../models/auth_session.dart';
import '../services/api/api_client.dart';
import '../services/api/api_exception.dart';
import '../utils/validators.dart';

/// Controller das telas de login e registro.
///
/// Guarda o estado do formulário e as regras de validação; a View só
/// desenha o resultado e navega.
class AuthController extends AppController {
  AuthController({required this.deps, this.initialServerUrl});

  final AppDependencies deps;

  /// Endereço já resolvido, quando a tela é aberta a partir de outra que já
  /// o resolveu (o registro vem do login).
  final String? initialServerUrl;

  bool _restoring = true;
  bool _submitting = false;
  String? _error;
  String? _warning;
  String? _successMessage;
  String _serverUrl = '';
  String _username = '';

  bool get isRestoring => _restoring;
  bool get isSubmitting => _submitting;
  String? get error => _error;
  String? get warning => _warning;
  String? get successMessage => _successMessage;
  String get serverUrl => _serverUrl;
  String get username => _username;

  /// Recupera o servidor e o último usuário usados neste aparelho e, quando
  /// há uma sessão salva ainda renovável, devolve-a já ativa para o app
  /// entrar sem pedir login. Devolve `null` quando é preciso logar.
  Future<ActiveSession?> restore() async {
    try {
      _serverUrl = initialServerUrl ?? await deps.config.loadServerUrl();
      final saved = await deps.sessionStore.load();
      _username = saved?.user.username ?? '';
      if (saved != null && initialServerUrl == null) {
        return await _resume(saved);
      }
    } catch (error) {
      _error = 'Não foi possível carregar as configurações: $error';
    } finally {
      _restoring = false;
      notify();
    }
    return null;
  }

  /// Reaproveita a sessão salva, renovando o token de acesso se preciso. Só
  /// a falha ao renovar manda o usuário para o login; a sessão salva continua
  /// no disco até o logout.
  Future<ActiveSession?> _resume(AuthSession saved) async {
    final api = ApiClient(baseUrl: _serverUrl, sessionStore: deps.sessionStore)
      ..setSession(saved);
    try {
      await api.ensureAccessToken();
    } catch (_) {
      return null;
    }
    if (!await _startBeacon()) {
      _warning = 'Sem permissão de localização: o app não enviará sua '
          'posição em segundo plano.';
    }
    return ActiveSession(api: api, user: saved.user);
  }

  void setServerUrl(String value) {
    if (_serverUrl == value) return;
    _serverUrl = value;
  }

  void setUsername(String value) {
    if (_username == value) return;
    _username = value;
  }

  /// Normaliza o endereço digitado: sem esquema vira http e a barra final
  /// sai.
  String normalizeServerUrl(String raw) {
    var url = raw.trim();
    if (url.isEmpty) url = deps.config.defaultServerUrl;
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      url = 'http://$url';
    }
    while (url.endsWith('/')) {
      url = url.substring(0, url.length - 1);
    }
    return url;
  }

  /// Entra no servidor e devolve a sessão ativa, ou `null` em caso de falha
  /// (o motivo fica em [error]).
  Future<ActiveSession?> login({
    required String serverUrl,
    required String username,
    required String password,
  }) async {
    if (_submitting || _restoring) return null;
    final user = username.trim();
    if (user.isEmpty || password.isEmpty) {
      _error = 'Preencha o usuário e a senha.';
      notify();
      return null;
    }
    _submitting = true;
    _error = null;
    _warning = null;
    notify();
    try {
      final baseUrl = normalizeServerUrl(serverUrl);
      await deps.config.saveServerUrl(baseUrl);
      final api = ApiClient(baseUrl: baseUrl, sessionStore: deps.sessionStore);
      final session = await api.login(user, password);
      if (!await _startBeacon()) {
        _warning = 'Sem permissão de localização: o app não enviará sua '
            'posição em segundo plano.';
      }
      return ActiveSession(api: api, user: session.user);
    } on ApiException catch (error) {
      _error = error.message;
      return null;
    } catch (error) {
      _error = 'Não foi possível entrar: $error';
      return null;
    } finally {
      _submitting = false;
      notify();
    }
  }

  /// Cria a conta, entra e devolve a sessão ativa, ou `null` em caso de
  /// falha.
  Future<ActiveSession?> register({
    required String serverUrl,
    required String username,
    required String firstName,
    required String lastName,
    required String password,
    required String confirmPassword,
  }) async {
    if (_submitting) return null;
    final user = username.trim();
    final name = firstName.trim();
    final surname = lastName.trim();
    final invalid = Validators.username(user) ??
        Validators.firstName(name) ??
        Validators.lastName(surname) ??
        Validators.password(password) ??
        Validators.confirmPassword(confirmPassword, password);
    if (invalid != null) {
      _error = invalid;
      notify();
      return null;
    }
    _submitting = true;
    _error = null;
    notify();
    try {
      final baseUrl = normalizeServerUrl(serverUrl);
      await deps.config.saveServerUrl(baseUrl);
      final api = ApiClient(baseUrl: baseUrl, sessionStore: deps.sessionStore);
      final created = await api.register(
        username: user,
        firstName: name,
        lastName: surname,
        password: password,
      );
      final session = await api.login(user, password);
      _successMessage = 'Conta ${created.username} criada com sucesso';
      return ActiveSession(api: api, user: session.user);
    } on ApiException catch (error) {
      _error = error.message;
      return null;
    } catch (_) {
      _error = 'Não foi possível conectar ao servidor';
      return null;
    } finally {
      _submitting = false;
      notify();
    }
  }

  /// O beacon só existe no Android. Em outras plataformas a ausência de
  /// permissão não é um problema — e não deve virar aviso.
  Future<bool> _startBeacon() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return true;
    }
    return deps.beacon.start();
  }
}
