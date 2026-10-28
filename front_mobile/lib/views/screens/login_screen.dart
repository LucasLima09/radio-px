import 'package:flutter/material.dart';

import '../../controllers/auth_controller.dart';
import '../../di.dart';
import '../../routes.dart';
import '../../theme/app_colors.dart';
import '../widgets/page_heading.dart';
import '../widgets/radio_mark.dart';

/// Tela de entrada: servidor, usuário e senha.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _serverCtrl = TextEditingController();
  final _userCtrl = TextEditingController();
  final _passCtrl = TextEditingController();

  AuthController? _controller;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_controller != null) return;
    _controller = AuthController(deps: AppScope.of(context));
    _restore();
  }

  /// Preenche os campos com o que já ficou salvo no aparelho.
  Future<void> _restore() async {
    await _controller!.restore();
    if (!mounted) return;
    _serverCtrl.text = _controller!.serverUrl;
    _userCtrl.text = _controller!.username;
  }

  @override
  void dispose() {
    _controller?.dispose();
    _serverCtrl.dispose();
    _userCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    final controller = _controller!;
    final session = await controller.login(
      serverUrl: _serverCtrl.text,
      username: _userCtrl.text,
      password: _passCtrl.text,
    );
    if (!mounted || session == null) return;
    // O aviso sobre a falta de permissão de localização precisa sobreviver à
    // troca de tela: quem mostra é o messenger do app, que fica acima do
    // navegador de rotas.
    final messenger = ScaffoldMessenger.of(context);
    final warning = controller.warning;
    await Navigator.of(context).pushReplacementNamed(
      AppRoutes.channels,
      arguments: session,
    );
    if (warning != null) {
      messenger.showSnackBar(SnackBar(content: Text(warning)));
    }
  }

  Future<void> _openRegister() async {
    final controller = _controller!;
    final serverUrl = controller.normalizeServerUrl(_serverCtrl.text);
    await controller.deps.config.saveServerUrl(serverUrl);
    if (!mounted) return;
    await Navigator.of(context).pushNamed(
      AppRoutes.register,
      arguments: serverUrl,
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller!;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: ListenableBuilder(
                listenable: controller,
                builder: (context, _) {
                  final busy = controller.isSubmitting || controller.isRestoring;
                  return Column(
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
                      if (controller.error != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 16),
                          child: Text(
                            controller.error!,
                            style: const TextStyle(
                              color: pxDanger,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      FilledButton(
                        onPressed: busy ? null : _login,
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                        child: Text(
                          controller.isSubmitting ? 'Entrando...' : 'Entrar',
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: controller.isSubmitting ? null : _openRegister,
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        child: const Text('Criar conta'),
                      ),
                      const SizedBox(height: 12),
                      Theme(
                        data: Theme.of(context)
                            .copyWith(dividerColor: Colors.transparent),
                        child: ExpansionTile(
                          tilePadding: EdgeInsets.zero,
                          childrenPadding: const EdgeInsets.only(bottom: 12),
                          title: const Text(
                            'Configurar servidor',
                            style: TextStyle(color: pxMuted, fontSize: 13),
                          ),
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
