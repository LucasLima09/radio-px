import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import '../api/api_client.dart';
import '../location/location_tracker.dart';
import '../storage/app_config.dart';
import '../storage/session_store.dart';

/// Ponto de entrada executado pelo flutter_foreground_task em um isolado
/// próprio. Precisa ser uma função top-level.
@pragma('vm:entry-point')
void beaconCallback() {
  FlutterForegroundTask.setTaskHandler(BeaconTaskHandler());
}

/// Mantém o beacon de localização ativo mesmo com o app em segundo plano ou
/// encerrado dos recentes. A sessão e o endereço do servidor são lidos do
/// SharedPreferences, então o handler é autocontido e não depende da UI.
class BeaconTaskHandler extends TaskHandler {
  ApiClient? _api;
  LocationTracker? _tracker;

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    final sessionStore = SessionStore();
    final session = await sessionStore.load();
    if (session == null) return;

    final serverUrl = await AppConfig().loadServerUrl();
    final api = ApiClient(baseUrl: serverUrl, sessionStore: sessionStore)
      ..setSession(session);
    _api = api;

    final tracker = LocationTracker();
    tracker.onPosition = _report;
    tracker.onError = (_) {};
    _tracker = tracker;

    await tracker.start();
  }

  /// O LocationTracker já reenvia a posição em um heartbeat de 30s; este
  /// reperforço cobre o caso de o stream de GPS ter falhado silenciosamente.
  @override
  void onRepeatEvent(DateTime timestamp) {
    _tracker?.sendLast();
  }

  void _report(double lat, double lng) {
    final api = _api;
    if (api == null) return;
    // Beacon silencioso: falhas de rede/sessão não devem derrubar o serviço.
    api.sendLocation(lat, lng).catchError((_) {});
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
    final tracker = _tracker;
    _tracker = null;
    _api = null;
    await tracker?.stop();
  }
}