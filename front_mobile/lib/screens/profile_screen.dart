import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../api.dart';
import '../models.dart';
import '../widgets/profile_avatar.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({
    super.key,
    required this.api,
    required this.user,
    required this.onSaved,
  });
  final ApiClient api;
  final PublicUser user;
  final ValueChanged<PublicUser> onSaved;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _form = GlobalKey<FormState>();
  final _picker = ImagePicker();
  late final TextEditingController _name;
  String? _avatar;
  bool _photoChanged = false;
  bool _saving = false;
  bool _picking = false;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.user.username);
    _avatar = widget.user.avatar;
    _load();
  }

  Future<void> _load() async {
    try {
      final user = await widget.api.getProfile();
      if (!mounted) return;
      _name.text = user.username;
      setState(() => _avatar = user.avatar);
      widget.onSaved(user);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'Não foi possível atualizar o perfil. Seus dados salvos continuam disponíveis.',
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      try {
        final lost = await _picker.retrieveLostData();
        if (lost.exception != null) throw lost.exception!;
        if (lost.files?.isNotEmpty == true) await _usePhoto(lost.files!.first);
      } catch (_) {
        if (mounted) {
          setState(
            () => _error =
                'Não foi possível recuperar a foto. Escolha novamente.',
          );
        }
      }
    }
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _usePhoto(XFile photo) async {
    final bytes = await photo.readAsBytes();
    if (bytes.length > 256 * 1024) {
      throw Exception(
        'A foto ficou muito grande. Escolha uma imagem menor (até 256 KB).',
      );
    }
    final jpeg =
        bytes.length >= 3 &&
        bytes[0] == 0xff &&
        bytes[1] == 0xd8 &&
        bytes[2] == 0xff;
    final png =
        bytes.length >= 8 &&
        listEquals(bytes.take(8).toList(), [137, 80, 78, 71, 13, 10, 26, 10]);
    if (!jpeg && !png) throw Exception('Escolha uma foto JPEG ou PNG.');
    if (!mounted) return;
    setState(() {
      _avatar =
          'data:image/${jpeg ? 'jpeg' : 'png'};base64,${base64Encode(bytes)}';
      _photoChanged = true;
      _error = null;
    });
  }

  Future<void> _pickPhoto() async {
    setState(() => _picking = true);
    try {
      final photo = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 512,
        maxHeight: 512,
        imageQuality: 75,
        requestFullMetadata: false,
      );
      if (photo != null) await _usePhoto(photo);
    } catch (e) {
      if (mounted) {
        setState(
          () => _error =
              'Não foi possível usar a foto. ${e.toString().replaceFirst('Exception: ', '')}',
        );
      }
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final user = await widget.api.updateProfile(
        username: _name.text.trim(),
        avatar: _photoChanged ? (_avatar ?? '') : null,
      );
      if (!mounted) return;
      widget.onSaved(user);
      setState(() {
        _avatar = user.avatar;
        _photoChanged = false;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Perfil atualizado')));
    } on ApiException catch (e) {
      if (mounted) {
        setState(
          () => _error = e.statusCode == 409
              ? 'Esse nome já está em uso. Escolha outro.'
              : e.message,
        );
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'Não foi possível salvar. Confira sua conexão e tente novamente.',
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final busy = _saving || _picking || _loading;
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
                      avatar: _avatar,
                      radius: 58,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Center(
                    child: TextButton.icon(
                      onPressed: busy ? null : _pickPhoto,
                      icon: const Icon(Icons.photo_library_outlined),
                      label: Text(
                        _picking ? 'Abrindo galeria...' : 'Alterar foto',
                      ),
                    ),
                  ),
                  if (_avatar?.isNotEmpty == true)
                    Center(
                      child: TextButton(
                        onPressed: busy
                            ? null
                            : () => setState(() {
                                _avatar = null;
                                _photoChanged = true;
                              }),
                        child: const Text('Remover foto'),
                      ),
                    ),
                  const SizedBox(height: 32),
                  TextFormField(
                    controller: _name,
                    enabled: !busy,
                    maxLength: 50,
                    textInputAction: TextInputAction.done,
                    decoration: const InputDecoration(
                      labelText: 'Nome',
                      helperText:
                          'Este também é o nome usado para entrar na conta.',
                      helperMaxLines: 2,
                      prefixIcon: Icon(Icons.person_outline),
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) => (value?.trim().runes.length ?? 0) < 3
                        ? 'Use pelo menos 3 caracteres'
                        : null,
                  ),
                  const SizedBox(height: 20),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Text(
                        _error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  FilledButton.icon(
                    onPressed: busy ? null : _save,
                    icon: _saving || _loading
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.check),
                    label: Text(
                      _saving
                          ? 'Salvando...'
                          : _loading
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
  }
}
