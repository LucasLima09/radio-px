import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:geolocator/geolocator.dart';

import 'beacon_task.dart';

/// Gerencia o serviço de foreground (mantém o app vivo em segundo plano para
/// o RX continuar) e o beacon de localização sempre ativo.
class BeaconController {
  static bool get _supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  Future<bool> get isRunning async {
    if (!_supported) return false;
    return await FlutterForegroundTask.isRunningService;
  }

  /// Pede as permissões de localização necessárias para o beacon funcionar em
  /// segundo plano ("Permitir sempre"). O objetivo de bateria fica de fora de
  /// propósito: nenhum diálogo é exibido.
  Future<bool> ensureLocationPermission() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return false;

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return false;
    }
    // Com "somente enquanto o app está aberto", volta a perguntar para o
    // usuário escolher "Permitir sempre" — necessário para o GPS em segundo
    // plano.
    if (permission == LocationPermission.whileInUse) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.deniedForever) {
      return await Geolocator.openAppSettings() == true;
    }
    return true;
  }

  Future<void> _ensureNotificationPermission() async {
    final permission = await FlutterForegroundTask.checkNotificationPermission();
    if (permission != NotificationPermission.granted) {
      await FlutterForegroundTask.requestNotificationPermission();
    }
  }

  /// Inicia o beacon e o serviço de foreground. Não exibe diálogo de
  /// otimização de bateria (decisão do projeto).
  Future<bool> start() async {
    if (!_supported) return false;
    if (await FlutterForegroundTask.isRunningService) return true;

    await _ensureNotificationPermission();
    if (!await ensureLocationPermission()) return false;

    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'radio_px_background',
        channelName: 'Radio PX em segundo plano',
        channelDescription:
            'Mantém o rádio recebendo áudio e enviando a posição',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
        onlyAlertOnce: true,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: true,
        playSound: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.repeat(30000),
        autoRunOnBoot: false,
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );

    final result = await FlutterForegroundTask.startService(
      serviceTypes: const [
        ForegroundServiceTypes.location,
        ForegroundServiceTypes.mediaPlayback,
      ],
      notificationTitle: 'Radio PX ativo',
      notificationText: 'Recebendo áudio do canal e enviando a posição',
      callback: beaconCallback,
    );
    return result is ServiceRequestSuccess;
  }

  Future<void> stop() async {
    if (!_supported) return;
    if (!await FlutterForegroundTask.isRunningService) return;
    await FlutterForegroundTask.stopService();
  }
}
