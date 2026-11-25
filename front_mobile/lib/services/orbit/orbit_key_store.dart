import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Guarda a chave pública dos Orbits de cada servidor, para o app reconhecê-los
/// mesmo abrindo sem internet.
class OrbitKeyStore {
  OrbitKeyStore({required String baseUrl}) : _name = 'orbit_key_$baseUrl';

  final String _name;

  Future<List<int>?> load() async {
    final raw = (await SharedPreferences.getInstance()).getString(_name);
    return raw == null ? null : base64Decode(raw);
  }

  Future<void> save(List<int> key) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_name, base64Encode(key));
  }
}
