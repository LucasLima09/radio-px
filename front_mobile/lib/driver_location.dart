import 'dart:async';
import 'package:geolocator/geolocator.dart';

class DriverLocation {
  static Future<Position>? _pending;

  static Future<Position> current() {
    return _pending ??= _read().whenComplete(() => _pending = null);
  }

  static Future<Position> _read() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw StateError('Ative a localização do aparelho para ver canais próximos.');
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.deniedForever) {
      throw StateError('Permita a localização nas configurações do aplicativo.');
    }
    if (permission != LocationPermission.always && permission != LocationPermission.whileInUse) {
      throw StateError('Permita a localização para ver canais próximos ou selecione Todos.');
    }
    try {
      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 15),
        ),
      );
    } on TimeoutException {
      throw StateError('Não foi possível obter sua localização. Tente novamente.');
    }
  }
}
