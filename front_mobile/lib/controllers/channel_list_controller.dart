import 'dart:async';

import 'app_controller.dart';
import '../di.dart';
import '../models/channel.dart';
import '../models/public_user.dart';
import '../services/api/api_client.dart';
import '../services/api/api_exception.dart';

/// Controller da lista de canais.
class ChannelListController extends AppController {
  ChannelListController({
    required this.api,
    required this.user,
    required this.deps,
  });

  final ApiClient api;
  final AppDependencies deps;

  /// Atualiza a contagem de pessoas online. Sem isso, a lista fica com o
  /// valor de quando foi aberta — por exemplo, ainda mostrando a própria
  /// pessoa logo depois de sair de um canal.
  static const _refreshInterval = Duration(seconds: 5);

  PublicUser user;
  List<Channel>? _channels;
  String? _error;
  bool _creating = false;
  Timer? _refreshTimer;

  List<Channel>? get channels => _channels;
  String? get error => _error;
  bool get isCreating => _creating;
  bool get isLoading => _channels == null;

  /// Carrega a lista e passa a atualizá-la periodicamente.
  Future<void> start() async {
    await load();
    _refreshTimer ??= Timer.periodic(
      _refreshInterval,
      (_) => load(silent: true),
    );
  }

  /// Recarrega os canais.
  ///
  /// Em modo [silent] (atualização periódica) uma falha não apaga a lista já
  /// exibida: é melhor mostrar dado velho do que tela vazia.
  Future<void> load({bool silent = false}) async {
    if (!silent) {
      _error = null;
      notify();
    }
    try {
      _channels = await api.listChannels();
    } on ApiException catch (error) {
      if (silent) return;
      _channels = const [];
      _error = error.message;
    } catch (error) {
      if (silent) return;
      _channels = const [];
      _error = 'Falha de rede ou servidor inacessível: $error';
    }
    notify();
  }

  /// Cria um canal e devolve o novo canal, ou `null` em caso de falha.
  Future<Channel?> create(String name) async {
    if (_creating) return null;
    _creating = true;
    _error = null;
    notify();
    try {
      final channel = await api.createChannel(name);
      _channels = [...?_channels, channel];
      return channel;
    } catch (error) {
      _error = error.toString();
      return null;
    } finally {
      _creating = false;
      notify();
    }
  }

  /// Atualiza o usuário exibido depois de salvar o perfil.
  void updateUser(PublicUser updated) {
    user = updated;
    notify();
  }

  /// Encerra a sessão: para o beacon e apaga a sessão salva.
  Future<void> logout() async {
    await deps.beacon.stop();
    await deps.sessionStore.clear();
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _refreshTimer = null;
    super.dispose();
  }
}
