import 'package:flutter_test/flutter_test.dart';
import 'package:front_mobile/models/orbit_encounter.dart';
import 'package:front_mobile/services/orbit/orbit_decoder.dart';

import '../orbit_signals.dart';

// O mesmo vetor está em backend/internal/domain/orbit/signal_test.go: se o
// formato mudar de um lado só, um dos dois quebra.
const _vector =
    'a1b2c3d4010203046ab13b80ef0ac2d3e0e2fa60cb975187cf349477a000273722147e25a25e5620daec46de0295c731ca5143a7a1b55b9d392465a4a8d3547c49bc65ef0c7153c8f6fdc2b05ae4e6d2fc848409';

List<int> _hex(String s) => [
  for (var i = 0; i < s.length; i += 2)
    int.parse(s.substring(i, i + 2), radix: 16),
];

void main() {
  late FakeOrbit orbit;
  late OrbitDecoder decoder;
  final now = DateTime.fromMillisecondsSinceEpoch(1790000000 * 1000);

  setUp(() async {
    orbit = await FakeOrbit.create();
    decoder = OrbitDecoder(orbit.publicKey);
  });

  Future<OrbitSighting?> feed(Iterable<OrbitAdvertisement> ads) async {
    OrbitSighting? last;
    for (final ad in ads) {
      last = await decoder.add(ad) ?? last;
    }
    return last;
  }

  test('aceita o sinal gerado pelo Orbit em Go', () async {
    final s = (await feed(advertise(_hex(_vector), now, rssi: -50)))!;
    expect(s.signal.identifier, 'A1B2C3D401020304');
    expect(s.signal.at, now.toUtc());
    expect(s.signal.lat, closeTo(-28.4507437, 1e-9));
    expect(s.signal.lng, closeTo(-52.199568, 1e-9));
    expect(s.rssi, -50);
    expect(s.signal.raw, _hex(_vector));
  });

  test('os pedaços podem chegar fora de ordem e repetidos', () async {
    final ads = advertise(await orbit.sign(now), now);
    expect(await feed([ads[2], ads[0], ads[2], ads[3]]), isNull);
    expect(await feed([ads[1]]), isNotNull);
    expect(await feed([ads[0]]), isNotNull); // continua no ar
    expect(decoder.valid, 1);
  });

  test('dois Orbits ao mesmo tempo não se misturam', () async {
    final other = await FakeOrbit.create(id: 2);
    final a = advertise(await orbit.sign(now), now);
    final b = advertise(await other.sign(now), now);
    final seen = <String>{};
    for (var i = 0; i < 4; i++) {
      for (final ad in [a[i], b[i]]) {
        final s = await decoder.add(ad);
        if (s != null) seen.add(s.signal.identifier);
      }
    }
    expect(seen, {orbit.identifier, other.identifier});
  });

  test('recusa assinatura de outra chave', () async {
    final impostor = await FakeOrbit.create(seed: 8);
    expect(await feed(advertise(await impostor.sign(now), now)), isNull);
    expect((decoder.valid, decoder.rejected), (0, 1));
  });

  test('recusa posição adulterada', () async {
    final raw = await orbit.sign(now);
    raw[13] ^= 1;
    expect(await feed(advertise(raw, now)), isNull);
    expect(decoder.rejected, 1);
  });

  test('recusa sinal gravado e retransmitido depois', () async {
    final raw = await orbit.sign(now);
    final later = now.add(const Duration(minutes: 3));
    expect(await feed(advertise(raw, later)), isNull);
    expect(decoder.rejected, 1);
  });

  test('um sinal que continua no ar deixa de valer ao vencer', () async {
    final raw = await orbit.sign(now);
    expect(await feed(advertise(raw, now)), isNotNull);
    expect(
      await feed(advertise(raw, now.add(const Duration(seconds: 121)))),
      isNull,
    );
  });

  test('ignora sinal anterior ao mais novo já aceito', () async {
    final old = await orbit.sign(now);
    final recent = await orbit.sign(now.add(const Duration(seconds: 10)));
    final at = now.add(const Duration(seconds: 10));
    expect(await feed(advertise(recent, at)), isNotNull);
    expect(await feed(advertise(old, at)), isNull);
  });

  test('um pedaço falso não impede o verdadeiro', () async {
    final ads = advertise(await orbit.sign(now), now);
    final fake = OrbitAdvertisement(
      data: [...ads[1].data.sublist(0, 6), ...List.filled(21, 0)],
      at: now,
    );
    expect(await feed([ads[0], fake, ads[2], ads[3]]), isNull);
    expect(await feed([ads[1]]), isNotNull);
  });

  test('qualquer outro sinal BLE é ignorado', () async {
    for (final data in [
      <int>[],
      [1, 2, 3],
      List.filled(27, 0),
      [0x4F, 2, 0, ...List.filled(24, 0)],
      [0x4F, 1, 9, ...List.filled(24, 0)],
    ]) {
      expect(
        await decoder.add(OrbitAdvertisement(data: data, at: now)),
        isNull,
      );
    }
    expect((decoder.valid, decoder.rejected), (0, 0));
  });
}
