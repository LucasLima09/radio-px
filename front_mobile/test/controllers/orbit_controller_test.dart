import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_mobile/controllers/orbit_controller.dart';
import 'package:front_mobile/models/auth_session.dart';
import 'package:front_mobile/models/orbit_encounter.dart';
import 'package:front_mobile/models/public_user.dart';
import 'package:front_mobile/services/api/api_client.dart';
import 'package:front_mobile/services/orbit/orbit_queue.dart';
import 'package:front_mobile/services/orbit/orbit_scanner.dart';
import 'package:front_mobile/services/storage/session_store.dart';

const _lucas = RegisteredOrbit(
  id: '1',
  name: 'Orbit do Lucas',
  identifier: 'ORBIT-LUCAS',
);
const _ana = RegisteredOrbit(
  id: '2',
  name: 'Orbit da Ana',
  identifier: 'ORBIT-ANA',
);

class _FakeScanner implements OrbitScanner {
  final sightings = StreamController<OrbitSighting>.broadcast();
  List<RegisteredOrbit>? watched;
  OrbitSighting? manual;

  @override
  bool get isSupported => true;

  @override
  bool get canWatch => true;

  bool gesture = true;

  @override
  bool get needsUserGesture => gesture;

  int watchCount = 0;

  @override
  Stream<OrbitSighting> watch(List<RegisteredOrbit> orbits) {
    watched = orbits;
    watchCount++;
    return sightings.stream;
  }

  @override
  Future<OrbitSighting?> scanOnce(List<RegisteredOrbit> orbits) async => manual;
}

void main() {
  late List<Map<String, dynamic>> sent;
  late _FakeScanner scanner;
  late OrbitController controller;
  late int reportStatus;
  late bool online;
  late ApiClient api;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    sent = [];
    reportStatus = 204;
    online = true;
    scanner = _FakeScanner();
    api =
        ApiClient(
          baseUrl: 'http://x',
          sessionStore: SessionStore(),
          httpClient: MockClient((req) async {
            if (req.method == 'GET' && req.url.path == '/api/v1/orbits') {
              return http.Response(
                jsonEncode([
                  for (final o in [_lucas, _ana])
                    {'id': o.id, 'name': o.name, 'identifier': o.identifier},
                ]),
                200,
              );
            }
            if (!online) throw http.ClientException('sem internet');
            sent.add(jsonDecode(req.body) as Map<String, dynamic>);
            return reportStatus == 204
                ? http.Response('', 204)
                : http.Response(
                    jsonEncode({'error': 'unknown orbit'}),
                    reportStatus,
                  );
          }),
        )..setSession(
          const AuthSession(
            accessToken: 'a',
            refreshToken: 'r',
            expiresAt: 0,
            user: PublicUser(id: '1', username: 'motorista'),
          ),
        );
    controller = OrbitController(
      api: api,
      queue: OrbitQueue(userId: '1'),
      scanner: scanner,
      readPosition: () async => (-23.5, -46.6),
    );
    await controller.start();
  });

  tearDown(() => controller.dispose());

  Future<void> emit(RegisteredOrbit orbit, int? rssi, DateTime at) async {
    scanner.sightings.add(OrbitSighting(orbit: orbit, rssi: rssi, at: at));
    await pumpEventQueue();
  }

  test('carrega os Orbits do servidor e escuta todos eles', () {
    expect(controller.orbits!.map((o) => o.identifier), [
      'ORBIT-LUCAS',
      'ORBIT-ANA',
    ]);
    controller.startWatching();
    expect(scanner.watched, hasLength(2));
  });

  test('envia 1 vez por Orbit a cada intervalo e ignora sinal fraco', () async {
    controller.startWatching();
    final now = DateTime.now();

    await emit(_lucas, -95, now); // fraco
    expect(sent, isEmpty);

    await emit(_lucas, -60, now);
    expect(sent, hasLength(1));
    expect(sent.single['lat'], -23.5);
    expect(sent.single['orbit'], {'identifier': 'ORBIT-LUCAS', 'rssi': -60});

    await emit(_lucas, -50, now.add(const Duration(seconds: 10)));
    expect(sent, hasLength(1)); // mesmo Orbit, dentro do intervalo

    await emit(_ana, -70, now.add(const Duration(seconds: 10)));
    expect(sent, hasLength(2)); // outro Orbit, envia

    await emit(_lucas, -60, now.add(const Duration(seconds: 61)));
    expect(sent, hasLength(3));
  });

  test('Orbit recusado pelo servidor vira erro legível', () async {
    reportStatus = 422;
    controller.startWatching();
    await emit(_lucas, -60, DateTime.now());

    expect(controller.encounters.single.sent, isFalse);
    expect(controller.encounters.single.error, contains('não cadastrado'));
    // Recusa definitiva: não fica na fila tentando para sempre.
    expect(controller.pendingCount, 0);
  });

  test('modo manual envia o Orbit escolhido no seletor', () async {
    scanner.manual = OrbitSighting(orbit: _ana, at: DateTime.now());
    await controller.scanOnce();

    expect(sent.single['orbit'], {'identifier': 'ORBIT-ANA'});
    expect(controller.encounters.single.sent, isTrue);
  });

  test('sem exigência de clique, a detecção liga sozinha no início', () async {
    final auto = _FakeScanner()..gesture = false;
    final c = OrbitController(
      api: controller.api,
      queue: OrbitQueue(userId: '1'),
      scanner: auto,
      readPosition: () async => (0.0, 0.0),
    );
    await c.start();

    expect(c.isAlwaysOn, isTrue);
    expect(c.isWatching, isTrue);
    expect(auto.watchCount, 1);

    // Recarregar a mesma lista não reinicia a escuta.
    await c.load(silent: true);
    expect(auto.watchCount, 1);
    c.dispose();
  });

  test(
    'sem internet guarda o encontro e envia quando a conexão volta',
    () async {
      online = false;
      controller.startWatching();
      final at = DateTime.now().subtract(const Duration(minutes: 5));
      await emit(_lucas, -60, at);

      expect(sent, isEmpty);
      expect(controller.pendingCount, 1);
      expect(controller.isOffline, isTrue);
      expect(controller.encounters.single.queued, isTrue);

      online = true;
      await controller.flush();

      expect(controller.pendingCount, 0);
      expect(controller.isOffline, isFalse);
      expect(controller.encounters.single.sent, isTrue);
      // Vai com a hora do encontro, não a do envio, e com o id do aparelho.
      expect(DateTime.parse(sent.single['at'] as String), at.toUtc());
      expect(sent.single['id'], controller.encounters.single.id);
    },
  );

  test('a fila sobrevive a fechar e abrir o app', () async {
    online = false;
    controller.startWatching();
    await emit(_ana, -60, DateTime.now());
    expect(controller.pendingCount, 1);
    controller.dispose();

    online = true;
    final reopened = OrbitController(
      api: api,
      queue: OrbitQueue(userId: '1'),
      scanner: _FakeScanner(),
      readPosition: () async => (0.0, 0.0),
    );
    await reopened.start();
    await pumpEventQueue();

    expect(sent.single['orbit'], {'identifier': 'ORBIT-ANA', 'rssi': -60});
    expect(reopened.pendingCount, 0);
    reopened.dispose();
    controller = OrbitController(
      api: api,
      queue: OrbitQueue(userId: '1'),
    );
  });

  test('a fila é por usuário', () async {
    online = false;
    controller.startWatching();
    await emit(_lucas, -60, DateTime.now());

    expect(await OrbitQueue(userId: '1').load(), hasLength(1));
    expect(await OrbitQueue(userId: '2').load(), isEmpty);
  });
}
