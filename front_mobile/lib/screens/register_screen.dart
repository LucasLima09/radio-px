import 'package:flutter/material.dart';

import '../api.dart';
import '../ui.dart';
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
      appBar: AppBar(),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: RadioMark(),
                  ),
                  const SizedBox(height: 32),
                  const PageHeading(
                    title: 'Entre na conversa.',
                    subtitle: 'Crie sua conta. Escolha um canal. Fale.',
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
                    decoration: const InputDecoration(
                      labelText: 'Senha',
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _confirmCtrl,
                    obscureText: true,
                    onSubmitted: (_) => _register(),
                    decoration: const InputDecoration(
                      labelText: 'Confirmar senha',
                    ),
                  ),
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: _loading ? null : _register,
                    child: Text(_loading ? 'Criando...' : 'Criar conta'),
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