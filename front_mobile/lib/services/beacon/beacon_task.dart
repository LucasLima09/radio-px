import 'package:flutter_foreground_task/flutter_foreground_task.dart';

/// Ponto de entrada executado pelo flutter_foreground_task em um isolado
/// próprio. Precisa ser uma função top-level.
@pragma('vm:entry-point')
void beaconCallback() {
  FlutterForegroundTask.setTaskHandler(BeaconTaskHandler());
}

/// Mantém o app vivo em segundo plano para o RX continuar recebendo áudio.
///
/// A posição não é mais enviada daqui: a localização só vai para a central
/// quando o app encontra um Orbit via Bluetooth.
class BeaconTaskHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {}

  @override
  void onRepeatEvent(DateTime timestamp) {}

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {}
}
