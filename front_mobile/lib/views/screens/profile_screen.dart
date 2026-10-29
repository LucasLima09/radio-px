import 'package:flutter/material.dart';

import '../../controllers/profile_controller.dart';
import '../../utils/input_masks.dart';
import '../../utils/validators.dart';
import '../widgets/profile_avatar.dart';

/// Formulário de perfil: foto, nome, usuário, placa, contato e salvar.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key, required this.controller});

  final ProfileController controller;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _firstName;
  late final TextEditingController _lastName;
  late final TextEditingController _username;
  late final TextEditingController _plate;
  late final TextEditingController _phone;

  @override
  void initState() {
    super.initState();
    final controller = widget.controller;
    _firstName = TextEditingController(text: controller.firstName);
    _lastName = TextEditingController(text: controller.lastName);
    _username = TextEditingController(text: controller.username);
    _plate = TextEditingController(text: controller.vehiclePlate);
    _phone = TextEditingController(text: controller.phone);
    controller.addListener(_syncFields);
    controller.load();
  }

  /// Mantém os campos em dia quando o controller troca os valores (por
  /// exemplo, depois de carregar o perfil do servidor).
  void _syncFields() {
    final controller = widget.controller;
    _sync(_firstName, controller.firstName);
    _sync(_lastName, controller.lastName);
    _sync(_username, controller.username);
    _sync(_plate, controller.vehiclePlate);
    _sync(_phone, controller.phone);
  }

  static void _sync(TextEditingController field, String value) {
    if (value == field.text) return;
    field.value = TextEditingValue(
      text: value,
      selection: TextSelection.collapsed(offset: value.length),
    );
  }

  @override
  void dispose() {
    widget.controller.removeListener(_syncFields);
    _firstName.dispose();
    _lastName.dispose();
    _username.dispose();
    _plate.dispose();
    _phone.dispose();
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
                          name: _firstName.text.trim().isEmpty
                              ? _username.text
                              : _firstName.text,
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
                        controller: _firstName,
                        enabled: !busy,
                        maxLength: 50,
                        textCapitalization: TextCapitalization.words,
                        textInputAction: TextInputAction.next,
                        autovalidateMode: AutovalidateMode.onUserInteraction,
                        onChanged: controller.setFirstName,
                        decoration: const InputDecoration(
                          labelText: 'Primeiro nome',
                          prefixIcon: Icon(Icons.badge_outlined),
                          border: OutlineInputBorder(),
                        ),
                        validator: Validators.firstName,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _lastName,
                        enabled: !busy,
                        maxLength: 50,
                        textCapitalization: TextCapitalization.words,
                        textInputAction: TextInputAction.next,
                        autovalidateMode: AutovalidateMode.onUserInteraction,
                        onChanged: controller.setLastName,
                        decoration: const InputDecoration(
                          labelText: 'Sobrenome',
                          prefixIcon: Icon(Icons.badge_outlined),
                          border: OutlineInputBorder(),
                        ),
                        validator: Validators.lastName,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _username,
                        enabled: !busy,
                        maxLength: 30,
                        autocorrect: false,
                        enableSuggestions: false,
                        textInputAction: TextInputAction.next,
                        autovalidateMode: AutovalidateMode.onUserInteraction,
                        inputFormatters: [usernameInputFormatter],
                        onChanged: controller.setUsername,
                        decoration: const InputDecoration(
                          labelText: 'Usuário',
                          helperText: 'Usado com a senha para entrar no app.',
                          helperMaxLines: 2,
                          prefixIcon: Icon(Icons.person_outline),
                          border: OutlineInputBorder(),
                        ),
                        validator: controller.validateUsername,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _plate,
                        enabled: !busy,
                        maxLength: 7,
                        textCapitalization: TextCapitalization.characters,
                        textInputAction: TextInputAction.next,
                        autovalidateMode: AutovalidateMode.onUserInteraction,
                        inputFormatters: [PlateInputFormatter()],
                        onChanged: controller.setVehiclePlate,
                        decoration: const InputDecoration(
                          labelText: 'Placa do veículo',
                          hintText: 'ABC1D23',
                          helperText: 'Padrão Mercosul',
                          prefixIcon: Icon(Icons.directions_car_outlined),
                          border: OutlineInputBorder(),
                        ),
                        validator: Validators.plate,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _phone,
                        enabled: !busy,
                        maxLength: 15,
                        keyboardType: TextInputType.phone,
                        textInputAction: TextInputAction.done,
                        autovalidateMode: AutovalidateMode.onUserInteraction,
                        inputFormatters: [PhoneInputFormatter()],
                        onChanged: controller.setPhone,
                        onFieldSubmitted: (_) {
                          if (!busy) _save();
                        },
                        decoration: const InputDecoration(
                          labelText: 'Contato (telefone)',
                          hintText: '(11) 98765-4321',
                          prefixIcon: Icon(Icons.phone_outlined),
                          border: OutlineInputBorder(),
                        ),
                        validator: Validators.phone,
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
