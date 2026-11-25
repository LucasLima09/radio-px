import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Guarda a chave pública dos Orbits e o acerto de relógio de cada servidor, para o app reconhecê-los
/// mesmo abrindo sem internet.
class OrbitKeyStore {
  OrbitKeyStore({required String baseUrl})
    : _name = 'orbit_key_$baseUrl',
      _offsetName = 'orbit_clock_$baseUrl';

  final String _name;
  final String _offsetName;

  Future<List<int>?> load() async {
    final raw = (await SharedPreferences.getInstance()).getString(_name);
    return raw == null ? null : base64Decode(raw);
  }

  Future<void> save(List<int> key) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_name, base64Encode(key));
  }

  /// Quanto somar ao relógio do aparelho para chegar ao da central.
  Future<Duration> loadClockOffset() async {
    final prefs = await SharedPreferences.getInstance();
    return Duration(milliseconds: prefs.getInt(_offsetName) ?? 0);
  }

  Future<void> saveClockOffset(Duration offset) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_offsetName, offset.inMilliseconds);
  }
}
