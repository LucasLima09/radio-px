import 'package:flutter/material.dart';

import '../../controllers/auth_controller.dart';
import '../../di.dart';
import '../../routes.dart';
import '../../utils/input_masks.dart';
import '../../utils/validators.dart';
import '../widgets/page_heading.dart';

/// Tela de criação de conta.
class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key, this.serverUrl});

  /// Servidor escolhido na tela de login.
  final String? serverUrl;

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _form = GlobalKey<FormState>();
  final _userCtrl = TextEditingController();
  final _firstNameCtrl = TextEditingController();
  final _lastNameCtrl = TextEditingController();
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
    _firstNameCtrl.dispose();
    _lastNameCtrl.dispose();
    _passCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _register() async {
    if (!_form.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    final controller = _controller!;
    final session = await controller.register(
      serverUrl: widget.serverUrl ?? '',
      username: _userCtrl.text,
      firstName: _firstNameCtrl.text,
      lastName: _lastNameCtrl.text,
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
                  return Form(
                    key: _form,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Center(
                          child: Image.asset(
                            'assets/image/logoktm.png',
                            height: 80,
                          ),
                        ),
                        const SizedBox(height: 32),
                        const PageHeading(
                          title: 'Entre na conversa.',
                          subtitle: 'Crie sua conta. Escolha um canal. Fale.',
                        ),
                        const SizedBox(height: 36),
                        TextFormField(
                          controller: _firstNameCtrl,
                          enabled: !busy,
                          maxLength: 50,
                          textCapitalization: TextCapitalization.words,
                          textInputAction: TextInputAction.next,
                          autovalidateMode: AutovalidateMode.onUserInteraction,
                          validator: Validators.firstName,
                          decoration: const InputDecoration(
                            labelText: 'Primeiro nome',
                            counterText: '',
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _lastNameCtrl,
                          enabled: !busy,
                          maxLength: 50,
                          textCapitalization: TextCapitalization.words,
                          textInputAction: TextInputAction.next,
                          autovalidateMode: AutovalidateMode.onUserInteraction,
                          validator: Validators.lastName,
                          decoration: const InputDecoration(
                            labelText: 'Sobrenome',
                            counterText: '',
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _userCtrl,
                          enabled: !busy,
                          maxLength: 30,
                          autocorrect: false,
                          enableSuggestions: false,
                          textInputAction: TextInputAction.next,
                          autovalidateMode: AutovalidateMode.onUserInteraction,
                          inputFormatters: [usernameInputFormatter],
                          validator: Validators.username,
                          decoration: const InputDecoration(
                            labelText: 'Usuário',
                            helperText:
                                'É com ele e a senha que você entra no app.',
                            counterText: '',
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _passCtrl,
                          enabled: !busy,
                          obscureText: true,
                          textInputAction: TextInputAction.next,
                          autovalidateMode: AutovalidateMode.onUserInteraction,
                          validator: Validators.password,
                          decoration: const InputDecoration(labelText: 'Senha'),
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _confirmCtrl,
                          enabled: !busy,
                          obscureText: true,
                          textInputAction: TextInputAction.done,
                          autovalidateMode: AutovalidateMode.onUserInteraction,
                          onFieldSubmitted: (_) => _register(),
                          validator: (value) =>
                              Validators.confirmPassword(value, _passCtrl.text),
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
                    ),
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
