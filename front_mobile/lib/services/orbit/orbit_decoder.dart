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
  OrbitDecoder(List<int> publicKey)
    : _key = SimplePublicKey(publicKey, type: KeyPairType.ed25519);

  static const companyId = 0xFFFF;
  static const magic = 0x4F;
  static const version = 1;
  static const fragments = 4;
  static const _header = 6;
  static const _chunk = 21;
  static const _context = 'radiopx-orbit-v1';

  /// Quanto a hora do sinal pode diferir do relógio do aparelho. Um sinal
  /// gravado e retransmitido depois chega velho. A central usa o mesmo limite.
  static const maxAge = Duration(minutes: 2);

  static const _partialTtl = Duration(minutes: 1);
  static const _maxPartials = 64;

  final SimplePublicKey _key;
  final _algorithm = Ed25519();
  final _partials = <String, _Partial>{};

  /// Hora do sinal mais novo já aceito de cada Orbit: um anterior é repetição.
  final _newest = <String, DateTime>{};

  int _valid = 0;
  int _rejected = 0;

  /// Sinais distintos com assinatura válida.
  int get valid => _valid;

  /// Sinais remontados com assinatura inválida ou hora fora do limite.
  int get rejected => _rejected;

  /// Processa um anúncio. Devolve o sinal quando ele está completo, assinado e
  /// atual; um anúncio repetido de um sinal já aceito o devolve de novo, com o
  /// RSSI novo.
  Future<OrbitSighting?> add(OrbitAdvertisement ad) async {
    final data = ad.data;
    if (data.length != _header + _chunk ||
        data[0] != magic ||
        data[1] != version ||
        data[2] >= fragments) {
      return null;
    }
    _partials.removeWhere((_, p) => ad.at.difference(p.lastAt) > _partialTtl);
    final tag = '${data[3]}.${data[4]}.${data[5]}';
    final partial = _partials.putIfAbsent(tag, () {
      if (_partials.length >= _maxPartials) {
        _partials.remove(_partials.keys.first);
      }
      return _Partial();
    });
    partial.lastAt = ad.at;
    partial.put(data[2], data.sublist(_header));

    final bytes = partial.bytes;
    if (bytes == null) return null;
    // Guardado antes do await: os anúncios que chegam durante a conferência
    // esperam o mesmo resultado.
    final signal = await (partial.result ??= _open(bytes, ad.at));
    if (signal == null) return null;

    final newest = _newest[signal.identifier];
    if (newest != null && signal.at.isBefore(newest)) return null;
    _newest[signal.identifier] = signal.at;
    // Continua no ar depois de vencer: deixa de valer.
    if (ad.at.difference(signal.at).abs() > maxAge) return null;
    return OrbitSighting(signal: signal, at: ad.at, rssi: ad.rssi);
  }

  Future<OrbitSignal?> _open(Uint8List bytes, DateTime at) async {
    final signal = OrbitSignal.parse(bytes);
    final ok = await _algorithm.verify(
      [...utf8.encode(_context), ...bytes.sublist(0, OrbitSignal.bodySize)],
      signature: Signature(
        bytes.sublist(OrbitSignal.bodySize),
        publicKey: _key,
      ),
    );
    if (!ok || at.difference(signal.at).abs() > maxAge) {
      _rejected++;
      return null;
    }
    _valid++;
    return signal;
  }
}

class _Partial {
  final List<List<int>?> _parts = List.filled(OrbitDecoder.fragments, null);
  DateTime lastAt = DateTime.fromMillisecondsSinceEpoch(0);
  Future<OrbitSignal?>? result;

  void put(int index, List<int> part) {
    final current = _parts[index];
    if (current != null && _equals(current, part)) return;
    // Pedaço diferente com a mesma tag (ex.: um impostor): vale o último, e a
    // assinatura é conferida de novo.
    _parts[index] = part;
    result = null;
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
