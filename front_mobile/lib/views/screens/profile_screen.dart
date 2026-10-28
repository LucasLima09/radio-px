import 'package:flutter/material.dart';

import '../../controllers/profile_controller.dart';
import '../widgets/profile_avatar.dart';

/// Formulário de perfil: nome, foto e salvar.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key, required this.controller});

  final ProfileController controller;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _name;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.controller.username);
    widget.controller.addListener(_syncName);
    widget.controller.load();
  }

  /// Mantém o campo em dia quando o controller troca o nome (por exemplo,
  /// depois de carregar o perfil do servidor).
  void _syncName() {
    final value = widget.controller.username;
    if (value == _name.text) return;
    _name.value = TextEditingValue(
      text: value,
      selection: TextSelection.collapsed(offset: value.length),
    );
  }

  @override
  void dispose() {
    widget.controller.removeListener(_syncName);
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    final user = await widget.controller.save();
    if (!mounted || user == null) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Perfil atualizado')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final busy = controller.isBusy;
        return ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: Form(
                  key: _form,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SizedBox(height: 16),
                      Center(
                        child: ProfileAvatar(
                          name: _name.text,
                          avatar: controller.avatar,
                          radius: 58,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Center(
                        child: TextButton.icon(
                          onPressed: busy ? null : controller.pickPhoto,
                          icon: const Icon(Icons.photo_library_outlined),
                          label: Text(
                            controller.isPicking
                                ? 'Abrindo galeria...'
                                : 'Alterar foto',
                          ),
                        ),
                      ),
                      if (controller.avatar?.isNotEmpty == true)
                        Center(
                          child: TextButton(
                            onPressed: busy ? null : controller.removePhoto,
                            child: const Text('Remover foto'),
                          ),
                        ),
                      const SizedBox(height: 32),
                      TextFormField(
                        controller: _name,
                        enabled: !busy,
                        maxLength: 50,
                        textInputAction: TextInputAction.done,
                        onChanged: controller.setUsername,
                        decoration: const InputDecoration(
                          labelText: 'Nome',
                          helperText:
                              'Este também é o nome usado para entrar na conta.',
                          helperMaxLines: 2,
                          prefixIcon: Icon(Icons.person_outline),
                          border: OutlineInputBorder(),
                        ),
                        validator: (value) =>
                            (value?.trim().runes.length ?? 0) < 3
                                ? 'Use pelo menos 3 caracteres'
                                : null,
                      ),
                      const SizedBox(height: 20),
                      if (controller.error != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 16),
                          child: Text(
                            controller.error!,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ),
                      FilledButton.icon(
                        onPressed: busy ? null : _save,
                        icon: controller.isSaving || controller.isLoading
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.check),
                        label: Text(
                          controller.isSaving
                              ? 'Salvando...'
                              : controller.isLoading
                                  ? 'Carregando...'
                                  : 'Salvar alterações',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
