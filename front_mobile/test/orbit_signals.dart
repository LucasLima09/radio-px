import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:front_mobile/models/orbit_encounter.dart';

/// Faz o papel de um Orbit nos testes: assina sinais e os divide em anúncios.
class FakeOrbit {
  FakeOrbit._(this._pair, this.publicKey, this.id);

  static Future<FakeOrbit> create({int seed = 7, int id = 1}) async {
    final pair = await Ed25519().newKeyPairFromSeed(List.filled(32, seed));
    final public = await pair.extractPublicKey();
    return FakeOrbit._(pair, public.bytes, id);
  }

  final SimpleKeyPair _pair;
  final List<int> publicKey;
  final int id;

  String get identifier => id.toRadixString(16).padLeft(16, '0').toUpperCase();

  Future<Uint8List> sign(
    DateTime at, {
    double lat = -23.5,
    double lng = -46.6,
  }) async {
    final body = ByteData(20)
      ..setUint32(4, id)
      ..setUint32(8, at.millisecondsSinceEpoch ~/ 1000)
      ..setInt32(12, (lat * 1e7).round())
      ..setInt32(16, (lng * 1e7).round());
    final bytes = body.buffer.asUint8List();
    final signature = await Ed25519().sign([
      ...utf8.encode('radiopx-orbit-v1'),
      ...bytes,
    ], keyPair: _pair);
    return Uint8List.fromList([...bytes, ...signature.bytes]);
  }
}

/// Os 4 anúncios em que o sinal é transmitido.
List<OrbitAdvertisement> advertise(List<int> raw, DateTime at, {int? rssi}) => [
  for (var i = 0; i < 4; i++)
    OrbitAdvertisement(
      data: [
        0x4F,
        1,
        i,
        ...raw.sublist(20, 23),
        ...raw.sublist(i * 21, (i + 1) * 21),
      ],
      at: at,
      rssi: rssi,
    ),
];
