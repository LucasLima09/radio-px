import 'package:flutter/material.dart';

import '../api.dart';
import 'channel_list_screen.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key, required this.serverUrl});

  final String serverUrl;

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _userCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();

  bool _loading = false;

  @override
  void dispose() {
    _userCtrl.dispose();
    _passCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _register() async {
    final username = _userCtrl.text.trim();
    final password = _passCtrl.text;

    if (username.length < 3) {
      _showError('Usuário precisa ter pelo menos 3 caracteres');
      return;
    }
    if (password.length < 6) {
      _showError('Senha precisa ter pelo menos 6 caracteres');
      return;
    }
    if (password != _confirmCtrl.text) {
      _showError('As senhas não conferem');
      return;
    }

    setState(() => _loading = true);
    try {
      final api = ApiClient(widget.serverUrl);
      final user = await api.register(username, password);
      final session = await api.login(username, password);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Conta ${user.username} criada com sucesso')),
      );
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => ChannelListScreen(api: api, user: session.user),
        ),
      );
    } on ApiException catch (e) {
      _showError(e.message);
      if (mounted) setState(() => _loading = false);
    } catch (_) {
      _showError('Não foi possível conectar ao servidor');
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Criar conta')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Servidor: ${widget.serverUrl}',
                      style: const TextStyle(color: Colors.white54)),
                  const SizedBox(height: 24),
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
                    decoration: const InputDecoration(
                      labelText: 'Senha',
                      prefixIcon: Icon(Icons.lock_outline),
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _confirmCtrl,
                    obscureText: true,
                    onSubmitted: (_) => _register(),
                    decoration: const InputDecoration(
                      labelText: 'Confirmar senha',
                      prefixIcon: Icon(Icons.lock_outline),
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: _loading ? null : _register,
                    icon: _loading
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.check),
                    label: const Text('Criar conta'),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
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