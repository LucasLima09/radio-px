import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';

/// Tamanho mínimo da senha de um canal privado. A API exige o mesmo.
const channelPasswordMinLength = 4;

/// Dados escolhidos no diálogo de novo canal.
class NewChannelRequest {
  final String name;
  final bool isPrivate;
  final String? password;

  const NewChannelRequest({
    required this.name,
    required this.isPrivate,
    this.password,
  });
}

/// Pede nome, visibilidade e, para canais privados, a senha do novo canal.
Future<NewChannelRequest?> showNewChannelDialog(BuildContext context) {
  return showDialog<NewChannelRequest>(
    context: context,
    builder: (_) => const _NewChannelDialog(),
  );
}

/// Pede a senha de um canal privado até acertar ou desistir.
///
/// [onSubmit] tenta entrar com a senha digitada e devolve `false` se ela
/// estiver errada. O diálogo devolve `true` quando a entrada deu certo.
Future<bool> showChannelPasswordDialog(
  BuildContext context, {
  required String channelName,
  required Future<bool> Function(String password) onSubmit,
}) async {
  final joined = await showDialog<bool>(
    context: context,
    builder: (_) =>
        _ChannelPasswordDialog(channelName: channelName, onSubmit: onSubmit),
  );
  return joined ?? false;
}

class _NewChannelDialog extends StatefulWidget {
  const _NewChannelDialog();

  @override
  State<_NewChannelDialog> createState() => _NewChannelDialogState();
}

class _NewChannelDialogState extends State<_NewChannelDialog> {
  final _nameCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _isPrivate = false;
  String? _passwordError;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) return;
    final password = _passwordCtrl.text;
    if (_isPrivate && password.length < channelPasswordMinLength) {
      setState(() {
        _passwordError =
            'A senha precisa ter ao menos $channelPasswordMinLength caracteres';
      });
      return;
    }
    Navigator.of(context).pop(
      NewChannelRequest(
        name: name,
        isPrivate: _isPrivate,
        password: _isPrivate ? password : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Novo canal'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _nameCtrl,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Nome do canal'),
            ),
            const SizedBox(height: 16),
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(
                  value: false,
                  icon: Icon(Icons.public),
                  label: Text('Público'),
                ),
                ButtonSegment(
                  value: true,
                  icon: Icon(Icons.lock_outline),
                  label: Text('Privado'),
                ),
              ],
              selected: {_isPrivate},
              onSelectionChanged: (selection) => setState(() {
                _isPrivate = selection.first;
                _passwordError = null;
              }),
            ),
            if (_isPrivate) ...[
              const SizedBox(height: 16),
              TextField(
                controller: _passwordCtrl,
                obscureText: true,
                onSubmitted: (_) => _submit(),
                decoration: InputDecoration(
                  labelText: 'Senha do canal',
                  helperText: 'Quem quiser entrar vai precisar dela',
                  errorText: _passwordError,
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Criar')),
      ],
    );
  }
}

class _ChannelPasswordDialog extends StatefulWidget {
  const _ChannelPasswordDialog({
    required this.channelName,
    required this.onSubmit,
  });

  final String channelName;
  final Future<bool> Function(String password) onSubmit;

  @override
  State<_ChannelPasswordDialog> createState() => _ChannelPasswordDialogState();
}

class _ChannelPasswordDialogState extends State<_ChannelPasswordDialog> {
  final _passwordCtrl = TextEditingController();
  bool _checking = false;
  String? _error;

  @override
  void dispose() {
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final password = _passwordCtrl.text;
    if (password.isEmpty || _checking) return;
    setState(() {
      _checking = true;
      _error = null;
    });
    try {
      final joined = await widget.onSubmit(password);
      if (!mounted) return;
      if (joined) {
        Navigator.of(context).pop(true);
        return;
      }
      _error = 'Senha incorreta';
    } catch (error) {
      if (!mounted) return;
      _error = error.toString();
    }
    setState(() => _checking = false);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.lock_outline, color: pxAccent),
          const SizedBox(width: 8),
          Expanded(child: Text(widget.channelName)),
        ],
      ),
      content: TextField(
        controller: _passwordCtrl,
        autofocus: true,
        obscureText: true,
        enabled: !_checking,
        onSubmitted: (_) => _submit(),
        decoration: InputDecoration(
          labelText: 'Senha do canal',
          helperText: 'Este canal é privado',
          errorText: _error,
        ),
      ),
      actions: [
        TextButton(
          onPressed: _checking ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _checking ? null : _submit,
          child: Text(_checking ? 'Entrando...' : 'Entrar'),
        ),
      ],
    );
  }
}
