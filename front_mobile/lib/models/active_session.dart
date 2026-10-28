import '../services/api/api_client.dart';
import 'public_user.dart';

/// Sessão ativa do usuário: o cliente da API apontando para o servidor
/// escolhido no login e o usuário autenticado.
///
/// É o objeto que a tela de login entrega para o resto do app, e que a rota
/// de canais usa para montar os controllers.
class ActiveSession {
  const ActiveSession({required this.api, required this.user});

  final ApiClient api;
  final PublicUser user;
}
