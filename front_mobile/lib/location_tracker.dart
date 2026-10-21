import 'dart:async';

import 'package:geolocator/geolocator.dart';

/// Envia a posição sempre que o usuário se move cerca de 10 metros
/// (distanceFilter) e, enquanto estiver parado, reenvia a última posição
/// a cada 30 segundos (heartbeat) para manter os marcadores atualizados.
class LocationTracker {
  static const _heartbeatInterval = Duration(seconds: 30);
  static const _distanceFilter = 10;

  void Function(double lat, double lng)? onPosition;
  void Function(String message)? onError;

  StreamSubscription<Position>? _sub;
  Timer? _heartbeat;
  Position? _last;
  bool _running = false;

  bool get isRunning => _running;

  Future<bool> start() async {
    if (_running) return true;
    if (!await _ensurePermission()) return false;

    _running = true;
    _sub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: _distanceFilter,
      ),
    ).listen(
      _handle,
      onError: (Object e) => onError?.call('Erro de localização: $e'),
    );

    _heartbeat = Timer.periodic(_heartbeatInterval, (_) {
      final last = _last;
      if (last != null) {
        onPosition?.call(last.latitude, last.longitude);
      }
    });

    try {
      final current = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: _distanceFilter,
        ),
      );
      _handle(current);
    } catch (_) {
      // Stream periódico cobre a ausência da primeira leitura.
    }
    return true;
  }

  void _handle(Position p) {
    _last = p;
    onPosition?.call(p.latitude, p.longitude);
  }

  void sendLast() {
    final last = _last;
    if (last != null) {
      onPosition?.call(last.latitude, last.longitude);
    }
  }

  Future<void> stop() async {
    _running = false;
    _last = null;
    await _sub?.cancel();
    _sub = null;
    _heartbeat?.cancel();
    _heartbeat = null;
  }

  Future<bool> _ensurePermission() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      onError?.call('Ative o serviço de localização do aparelho');
      return false;
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        onError?.call('Permissão de localização negada');
        return false;
      }
    }
    if (permission == LocationPermission.deniedForever) {
      onError?.call('Permissão de localização negada permanentemente');
      return false;
    }
    return true;
  }
}