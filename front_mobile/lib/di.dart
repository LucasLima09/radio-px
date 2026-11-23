import 'package:flutter/widgets.dart';

import 'services/beacon/beacon_controller.dart';
import 'services/storage/app_config.dart';
import 'services/storage/session_store.dart';

/// Dependências do app que existem desde o bootstrap.
///
/// O que só nasce depois do login — o cliente da API, por exemplo — é criado
/// pela rota de autenticação e viaja na [ActiveSession].
class AppDependencies {
  AppDependencies({
    required this.config,
    required this.sessionStore,
    required this.beacon,
  });

  /// Monta as dependências de produção.
  factory AppDependencies.production() => AppDependencies(
        config: AppConfig(),
        sessionStore: SessionStore(),
        beacon: BeaconController(),
      );

  final AppConfig config;
  final SessionStore sessionStore;
  final BeaconController beacon;
}

/// Disponibiliza as [AppDependencies] para toda a árvore de widgets.
///
/// As dependências nascem uma vez e nunca mudam, por isso basta procurá-las
/// na árvore — não é preciso reconstruir a tela quando algo muda nelas.
class AppScope extends InheritedWidget {
  const AppScope({
    super.key,
    required this.deps,
    required super.child,
  });

  final AppDependencies deps;

  /// Lê as dependências sem registrar dependência de reconstrução — seguro
  /// para usar em `initState`.
  static AppDependencies of(BuildContext context) =>
      context.getInheritedWidgetOfExactType<AppScope>()!.deps;

  @override
  bool updateShouldNotify(AppScope oldWidget) => oldWidget.deps != deps;
}
