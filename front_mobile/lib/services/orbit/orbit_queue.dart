import 'dart:convert';
import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

import '../../models/orbit_encounter.dart';

/// Fila dos encontros que ainda não chegaram à central, salva no aparelho:
/// sobrevive a ficar sem internet e a fechar o app. Uma fila por usuário, para
/// um encontro nunca ser enviado na conta de outra pessoa.
class OrbitQueue {
  OrbitQueue({required String userId}) : _key = 'orbit_queue_$userId';

  final String _key;

  /// Acima disso os mais antigos são descartados (vários dias sem internet
  /// passando por Orbits).
  static const maxItems = 1000;

  Future<List<OrbitEncounter>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return [];
    try {
      return [
        for (final item in jsonDecode(raw) as List)
          ?_parse(item as Map<String, dynamic>),
      ];
    } catch (_) {
      return [];
    }
  }

  /// Um item ilegível (ex.: formato de uma versão antiga do app) é descartado
  /// sem perder os outros.
  static OrbitEncounter? _parse(Map<String, dynamic> json) {
    try {
      return OrbitEncounter.fromJson(json);
    } catch (_) {
      return null;
    }
  }

  Future<void> save(List<OrbitEncounter> items) async {
    final prefs = await SharedPreferences.getInstance();
    if (items.isEmpty) {
      await prefs.remove(_key);
      return;
    }
    final kept = items.length > maxItems
        ? items.sublist(items.length - maxItems)
        : items;
    await prefs.setString(_key, jsonEncode([for (final e in kept) e.toJson()]));
  }
}

/// UUID v4 aleatório, para identificar o encontro desde o aparelho.
String newEncounterId() {
  final random = Random.secure();
  final b = List<int>.generate(16, (_) => random.nextInt(256));
  b[6] = (b[6] & 0x0f) | 0x40;
  b[8] = (b[8] & 0x3f) | 0x80;
  String hex(int from, int to) => [
    for (final v in b.sublist(from, to)) v.toRadixString(16).padLeft(2, '0'),
  ].join();
  return '${hex(0, 4)}-${hex(4, 6)}-${hex(6, 8)}-${hex(8, 10)}-${hex(10, 16)}';
}
