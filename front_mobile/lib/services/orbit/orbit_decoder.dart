import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import '../../models/orbit_encounter.dart';

/// Separa os sinais dos Orbits de todo o resto que chega por BLE.
///
/// O sinal tem 84 bytes e não cabe em um anúncio, então vem em 4 pedaços:
/// `'O'(1) | versão(1) | índice(1) | tag(3) | pedaço(21)`. A tag diz quais
/// pedaços são do mesmo sinal. Só sai daqui o que, remontado, tem a assinatura
/// da chave pública dos Orbits.
class OrbitDecoder {
  OrbitDecoder(List<int> publicKey, {this.onLog})
    : _key = SimplePublicKey(publicKey, type: KeyPairType.ed25519);

  static const companyId = 0xFFFF;
  static const magic = 0x4F;
  static const version = 1;
  static const fragments = 4;
  static const _header = 6;
  static const _chunk = 21;
  static const _context = 'radiopx-orbit-v1';

  static const _partialTtl = Duration(minutes: 1);
  static const _maxPartials = 64;

  /// Avisa o que está acontecendo, para a tela de diagnóstico.
  final void Function(String message)? onLog;

  final SimplePublicKey _key;
  final _algorithm = Ed25519();
  final _partials = <String, _Partial>{};

  /// Hora do sinal mais novo já aceito de cada Orbit: um anterior é repetição.
  final _newest = <String, DateTime>{};

  int _fragments = 0;
  int _valid = 0;
  int _rejected = 0;

  /// Anúncios no formato dos Orbits, ainda sem conferir a assinatura.
  int get fragmentCount => _fragments;

  /// Sinais distintos com assinatura válida.
  int get valid => _valid;

  /// Sinais remontados com assinatura inválida.
  int get rejected => _rejected;

  /// Processa um anúncio. Devolve o sinal quando ele está completo e
  /// assinado. A hora do celular não conta. Um anúncio repetido de um sinal já aceito o devolve de novo, com o
  /// RSSI novo.
  Future<OrbitSighting?> add(OrbitAdvertisement ad) async {
    final data = ad.data;
    if (data.length != _header + _chunk ||
        data[0] != magic ||
        data[1] != version ||
        data[2] >= fragments) {
      return null;
    }
    _fragments++;
    _partials.removeWhere((_, p) => ad.at.difference(p.lastAt) > _partialTtl);
    final tag = '${data[3]}.${data[4]}.${data[5]}';
    final partial = _partials.putIfAbsent(tag, () {
      if (_partials.length >= _maxPartials) {
        _partials.remove(_partials.keys.first);
      }
      return _Partial();
    });
    partial.lastAt = ad.at;
    if (partial.put(data[2], data.sublist(_header))) {
      onLog?.call(
        'Pedaço ${data[2] + 1} recebido (${partial.count}/$fragments)'
        '${ad.rssi == null ? '' : ' · ${ad.rssi} dBm'}',
      );
    }

    final bytes = partial.bytes;
    if (bytes == null) return null;
    // Guardado antes do await: os anúncios que chegam durante a conferência
    // esperam o mesmo resultado.
    final signal = await (partial.result ??= _open(bytes));
    if (signal == null) return null;

    final newest = _newest[signal.identifier];
    if (newest != null && signal.at.isBefore(newest)) return null;
    _newest[signal.identifier] = signal.at;
    return OrbitSighting(signal: signal, at: ad.at, rssi: ad.rssi);
  }

  Future<OrbitSignal?> _open(Uint8List bytes) async {
    final signal = OrbitSignal.parse(bytes);
    final ok = await _algorithm.verify(
      [...utf8.encode(_context), ...bytes.sublist(0, OrbitSignal.bodySize)],
      signature: Signature(
        bytes.sublist(OrbitSignal.bodySize),
        publicKey: _key,
      ),
    );
    if (!ok) {
      _rejected++;
      onLog?.call('Recusado: assinatura inválida (${signal.identifier})');
      return null;
    }
    _valid++;
    onLog?.call('Assinatura válida: ${signal.identifier}');
    return signal;
  }
}

class _Partial {
  final List<List<int>?> _parts = List.filled(OrbitDecoder.fragments, null);
  DateTime lastAt = DateTime.fromMillisecondsSinceEpoch(0);
  Future<OrbitSignal?>? result;

  int get count => _parts.where((p) => p != null).length;

  /// Devolve se o pedaço era novidade.
  bool put(int index, List<int> part) {
    final current = _parts[index];
    if (current != null && _equals(current, part)) return false;
    // Pedaço diferente com a mesma tag (ex.: um impostor): vale o último, e a
    // assinatura é conferida de novo.
    _parts[index] = part;
    result = null;
    return true;
  }

  Uint8List? get bytes {
    if (_parts.contains(null)) return null;
    return Uint8List.fromList([for (final p in _parts) ...p!]);
  }

  static bool _equals(List<int> a, List<int> b) {
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
