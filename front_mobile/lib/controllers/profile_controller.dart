import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';

import 'app_controller.dart';
import '../models/public_user.dart';
import '../services/api/api_client.dart';
import '../services/api/api_exception.dart';

/// Controller do perfil: carrega os dados, valida a foto e salva.
class ProfileController extends AppController {
  ProfileController({
    required this.api,
    required PublicUser user,
    ImagePicker? picker,
    this.onUserChanged,
  })  : _picker = picker ?? ImagePicker(),
        _username = user.username,
        _avatar = user.avatar;

  final ApiClient api;

  /// Chamado quando o servidor devolve o usuário atualizado, para quem
  /// precisa refletir a mudança (cabeçalho da lista de canais).
  final void Function(PublicUser user)? onUserChanged;

  static const int _maxPhotoBytes = 256 * 1024;

  final ImagePicker _picker;

  String _username;
  String? _avatar;
  bool _photoChanged = false;
  bool _saving = false;
  bool _picking = false;
  bool _loading = true;
  String? _error;

  String get username => _username;
  String? get avatar => _avatar;
  bool get isSaving => _saving;
  bool get isPicking => _picking;
  bool get isLoading => _loading;
  String? get error => _error;

  /// A tela fica bloqueada enquanto carrega, escolhe foto ou salva.
  bool get isBusy => _saving || _picking || _loading;

  /// Carrega o perfil do servidor e recupera a foto que o Android perdeu.
  Future<void> load() async {
    try {
      final user = await api.getProfile();
      _username = user.username;
      _avatar = user.avatar;
      onUserChanged?.call(user);
    } catch (_) {
      _error = 'Não foi possível atualizar o perfil. '
          'Seus dados salvos continuam disponíveis.';
    } finally {
      _loading = false;
    }
    notify();
    await _recoverLostPhoto();
  }

  void setUsername(String value) {
    if (_username == value) return;
    _username = value;
    notify();
  }

  /// Salva as alterações e devolve o usuário atualizado, ou `null` em caso de
  /// falha (o motivo fica em [error]).
  Future<PublicUser?> save() async {
    if (_saving) return null;
    if (_username.trim().runes.length < 3) {
      _error = 'Use pelo menos 3 caracteres';
      notify();
      return null;
    }
    _saving = true;
    _error = null;
    notify();
    try {
      final user = await api.updateProfile(
        username: _username.trim(),
        avatar: _photoChanged ? (_avatar ?? '') : null,
      );
      _username = user.username;
      _avatar = user.avatar;
      _photoChanged = false;
      onUserChanged?.call(user);
      return user;
    } on ApiException catch (error) {
      _error = error.statusCode == 409
          ? 'Esse nome já está em uso. Escolha outro.'
          : error.message;
      return null;
    } catch (_) {
      _error = 'Não foi possível salvar. '
          'Confira sua conexão e tente novamente.';
      return null;
    } finally {
      _saving = false;
      notify();
    }
  }

  /// Escolhe uma foto na galeria e valida o arquivo.
  Future<void> pickPhoto() async {
    if (_picking) return;
    _picking = true;
    _error = null;
    notify();
    try {
      final photo = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 512,
        maxHeight: 512,
        imageQuality: 75,
        requestFullMetadata: false,
      );
      if (photo != null) await _usePhoto(photo);
    } catch (error) {
      _error = 'Não foi possível usar a foto. '
          '${error.toString().replaceFirst('Exception: ', '')}';
    } finally {
      _picking = false;
      notify();
    }
  }

  /// Remove a foto. O servidor recebe string vazia no próximo salvamento.
  void removePhoto() {
    _avatar = null;
    _photoChanged = true;
    notify();
  }

  Future<void> _usePhoto(XFile photo) async {
    final bytes = await photo.readAsBytes();
    if (bytes.length > _maxPhotoBytes) {
      throw Exception(
        'A foto ficou muito grande. Escolha uma imagem menor (até 256 KB).',
      );
    }
    final jpeg =
        bytes.length >= 3 && bytes[0] == 0xff && bytes[1] == 0xd8 && bytes[2] == 0xff;
    final png = bytes.length >= 8 &&
        listEquals(bytes.take(8).toList(), [137, 80, 78, 71, 13, 10, 26, 10]);
    if (!jpeg && !png) throw Exception('Escolha uma foto JPEG ou PNG.');
    _avatar =
        'data:image/${jpeg ? 'jpeg' : 'png'};base64,${base64Encode(bytes)}';
    _photoChanged = true;
    _error = null;
    notify();
  }

  /// O Android pode perder a foto escolhida no seletor quando o app é
  /// recriado; a plataforma devolve o arquivo perdido para recuperar.
  Future<void> _recoverLostPhoto() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    try {
      final lost = await _picker.retrieveLostData();
      if (lost.exception != null) throw lost.exception!;
      if (lost.files?.isNotEmpty == true) await _usePhoto(lost.files!.first);
    } catch (_) {
      _error = 'Não foi possível recuperar a foto. Escolha novamente.';
      notify();
    }
  }
}
