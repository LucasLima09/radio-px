import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../api.dart';
import '../background/beacon_controller.dart';
import '../ui.dart';
import '../config.dart';
import '../session_store.dart';
import 'channel_list_screen.dart';
import 'register_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _serverCtrl = TextEditingController();
  final _userCtrl = TextEditingController();
  final _passCtrl = TextEditingController();

  bool _loading = false;
  String? _error;
  bool _restoring = true;

  @override
  void initState() {
    super.initState();
    _restore();
  }

  Future<void> _restore() async {
    try {
      final server = await AppConfig.loadServerUrl();
      final saved = await SessionStore.load();
      if (!mounted) return;
      _serverCtrl.text = server;
      _userCtrl.text = saved?.user.username ?? '';
    } catch (error) {
      if (mounted) _error = 'Não foi possível carregar as configurações: $error';
    } finally {
      if (mounted) setState(() => _restoring = false);
    }
  }

  @override
  void dispose() {
    _serverCtrl.dispose();
    _userCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  String _normalizedServerUrl() {
    var url = _serverCtrl.text.trim();
    if (url.isEmpty) url = AppConfig.defaultServerUrl;
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      url = 'http://$url';
    }
    while (url.endsWith('/')) {
      url = url.substring(0, url.length - 1);
    }
    return url;
  }

  Future<void> _login() async {
    if (_loading || _restoring) return;
    if (_userCtrl.text.trim().isEmpty || _passCtrl.text.isEmpty) {
      _showError('Preencha o usuário e a senha.');
      return;
    }
    setState(() { _loading = true; _error = null; });
    try {
      final serverUrl = _normalizedServerUrl();
      await AppConfig.saveServerUrl(serverUrl);
      final api = ApiClient(serverUrl);
      final session = await api.login(_userCtrl.text.trim(), _passCtrl.text);
      api.setSession(session);
      final beaconOk = !kIsWeb && defaultTargetPlatform == TargetPlatform.android
          ? await BeaconController.start()
          : true;
      if (!beaconOk) {
        _showError(
            'Sem permissão de localização: o app não enviará sua posição em '
            'segundo plano.');
      }
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => ChannelListScreen(api: api, user: session.user),
        ),
      );
    } on ApiException catch (e) {
      _showError(e.message);
    } catch (error) {
      _showError('Não foi possível entrar: $error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _openRegister() async {
    final serverUrl = _normalizedServerUrl();
    await AppConfig.saveServerUrl(serverUrl);
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => RegisterScreen(serverUrl: serverUrl)),
    );
  }

  void _showError(String message) {
    if (!mounted) return;
    setState(() => _error = message);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: RadioMark(),
                  ),
                  const SizedBox(height: 32),
                  const PageHeading(
                    title: 'Entre no Radio PX',
                    subtitle: 'Faça login, escolha um canal e comece a falar.',
                  ),
                  const SizedBox(height: 36),
                  TextField(
                    controller: _userCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Usuário',
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _passCtrl,
                    obscureText: true,
                    onSubmitted: (_) => _login(),
                    decoration: const InputDecoration(
                      labelText: 'Senha',
                    ),
                  ),
                  const SizedBox(height: 24),
                  if (_error != null) Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Text(_error!, style: const TextStyle(color: Color(0xFFE79B94), fontSize: 13)),
                  ),
                  FilledButton(
                    onPressed: _loading || _restoring ? null : _login,
                    child: Text(_loading ? 'Entrando...' : 'Entrar'),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: _loading ? null : _openRegister,
                    child: const Text('Criar conta'),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Theme(
                    data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                    child: ExpansionTile(
                      tilePadding: EdgeInsets.zero,
                      childrenPadding: const EdgeInsets.only(bottom: 12),
                      title: const Text('Configurar servidor',
                          style: TextStyle(color: pxMuted, fontSize: 13)),
                      children: [
                  TextField(
                    controller: _serverCtrl,
                    keyboardType: TextInputType.url,
                    decoration: const InputDecoration(
                      labelText: 'Servidor',
                      hintText: 'http://10.0.2.2:8080',
                    ),
                  ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
