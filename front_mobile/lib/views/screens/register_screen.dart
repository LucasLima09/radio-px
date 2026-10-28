import 'package:flutter/material.dart';

import '../../controllers/auth_controller.dart';
import '../../di.dart';
import '../../routes.dart';
import '../widgets/page_heading.dart';
import '../widgets/radio_mark.dart';

/// Tela de criação de conta.
class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key, this.serverUrl});

  /// Servidor escolhido na tela de login.
  final String? serverUrl;

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _userCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();

  AuthController? _controller;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_controller != null) return;
    _controller = AuthController(
      deps: AppScope.of(context),
      initialServerUrl: widget.serverUrl,
    );
  }

  @override
  void dispose() {
    _controller?.dispose();
    _userCtrl.dispose();
    _passCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _register() async {
    final controller = _controller!;
    final session = await controller.register(
      serverUrl: widget.serverUrl ?? '',
      username: _userCtrl.text,
      password: _passCtrl.text,
      confirmPassword: _confirmCtrl.text,
    );
    if (!mounted) return;
    if (session == null) {
      final error = controller.error;
      if (error != null) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error)));
      }
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    final message = controller.successMessage;
    await Navigator.of(context).pushReplacementNamed(
      AppRoutes.channels,
      arguments: session,
    );
    if (message != null) {
      messenger.showSnackBar(SnackBar(content: Text(message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller!;
    return Scaffold(
      appBar: AppBar(),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: ListenableBuilder(
                listenable: controller,
                builder: (context, _) {
                  final busy = controller.isSubmitting;
                  return Column(
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
                        onPressed: busy ? null : _register,
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                        child: Text(busy ? 'Criando...' : 'Criar conta'),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}
