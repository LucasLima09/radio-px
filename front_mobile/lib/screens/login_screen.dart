import 'package:flutter/material.dart';

import '../api.dart';
import '../config.dart';
import '../models.dart';
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
  PublicUser? _savedUser;

  @override
  void initState() {
    super.initState();
    _restore();
  }

  Future<void> _restore() async {
    final session = await SessionStore.load();
    if (!mounted) return;
    _serverCtrl.text = await AppConfig.loadServerUrl();
    if (session != null) {
      setState(() => _savedUser = session.user);
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

  Future<void> _login({bool asSaved = false}) async {
    setState(() => _loading = true);
    try {
      final serverUrl = _normalizedServerUrl();
      await AppConfig.saveServerUrl(serverUrl);
      final api = ApiClient(serverUrl);
      final session = asSaved
          ? (await SessionStore.load())!
          : await api.login(_userCtrl.text.trim(), _passCtrl.text);
      api.setSession(session);
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => ChannelListScreen(api: api, user: session.user),
        ),
      );
    } on ApiException catch (e) {
      _showError(e.message);
    } catch (_) {
      _showError('Não foi possível conectar ao servidor');
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
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
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
                  const Icon(Icons.radio, size: 72),
                  const SizedBox(height: 8),
                  Text(
                    'Radio PX',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const Text(
                    'Comunicação PTT',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white54),
                  ),
                  const SizedBox(height: 32),
                  TextField(
                    controller: _serverCtrl,
                    keyboardType: TextInputType.url,
                    decoration: const InputDecoration(
                      labelText: 'Servidor',
                      hintText: 'http://10.0.2.2:8080',
                      prefixIcon: Icon(Icons.dns_outlined),
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _userCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Usuário',
                      prefixIcon: Icon(Icons.person_outline),
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _passCtrl,
                    obscureText: true,
                    onSubmitted: (_) => _login(),
                    decoration: const InputDecoration(
                      labelText: 'Senha',
                      prefixIcon: Icon(Icons.lock_outline),
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: _loading ? null : _login,
                    icon: _loading
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.login),
                    label: const Text('Entrar'),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: _loading ? null : _openRegister,
                    icon: const Icon(Icons.person_add_alt),
                    label: const Text('Criar conta'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                  if (_savedUser != null) ...[
                    const SizedBox(height: 16),
                    TextButton.icon(
                      onPressed: _loading ? null : () => _login(asSaved: true),
                      icon: const Icon(Icons.play_arrow),
                      label: Text('Continuar como ${_savedUser!.username}'),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}