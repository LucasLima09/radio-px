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

import '../orbit_signals.dart';

class _FakeScanner implements OrbitScanner {
  final ads = StreamController<OrbitAdvertisement>.broadcast();
  int watchCount = 0;

  @override
  bool get isSupported => true;

  @override
  bool get canWatch => true;

  @override
  Stream<OrbitAdvertisement> watch() {
    watchCount++;
    return ads.stream;
  }
}

void main() {
  late FakeOrbit lucas;
  late FakeOrbit ana;
  late List<Map<String, dynamic>> sent;
  late _FakeScanner scanner;
  late OrbitController controller;
  late int reportStatus;
  late bool online;
  late List<int> serverKey;
  late ApiClient api;
  late DateTime now;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    lucas = await FakeOrbit.create(id: 1);
    ana = await FakeOrbit.create(id: 2);
    sent = [];
    reportStatus = 204;
    online = true;
    serverKey = lucas.publicKey;
    now = DateTime.now();
    scanner = _FakeScanner();
    api =
        ApiClient(
          baseUrl: 'http://x',
          sessionStore: SessionStore(),
          httpClient: MockClient((req) async {
            if (!online) throw http.ClientException('sem internet');
            if (req.method == 'GET' && req.url.path == '/api/v1/orbits') {
              return http.Response(
                jsonEncode({
                  'publicKey': serverKey.isEmpty
                      ? null
                      : base64Encode(serverKey),
                  'orbits': [
                    {'identifier': lucas.identifier, 'name': 'Orbit do Lucas'},
                  ],
                }),
                200,
              );
            }
            sent.add(jsonDecode(req.body) as Map<String, dynamic>);
            return reportStatus == 204
                ? http.Response('', 204)
                : http.Response(
                    jsonEncode({'error': 'Orbit desativado no painel.'}),
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
    );
    await controller.start();
  });

  tearDown(() => controller.dispose());

  Future<void> settle() async {
    // A conferência da assinatura é assíncrona e leva alguns milissegundos.
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await pumpEventQueue();
  }

  Future<List<int>> emit(FakeOrbit orbit, int? rssi, DateTime at) async {
    final raw = await orbit.sign(at);
    advertise(raw, at, rssi: rssi).forEach(scanner.ads.add);
    await settle();
    return raw;
  }

  test('a detecção liga sozinha e recarregar não a reinicia', () async {
    expect(controller.isWatching, isTrue);
    await controller.load(silent: true);
    expect(scanner.watchCount, 1);
  });

  test('repassa os bytes do Orbit, mesmo de um nunca visto', () async {
    final raw = await emit(ana, -60, now);
    expect(sent.single['signal'], base64Encode(raw));
    expect(sent.single['rssi'], -60);
    expect(sent.single.containsKey('lat'), isFalse);
    final e = controller.encounters.single;
    expect(e.sent, isTrue);
    expect((e.signal.lat, e.signal.lng), (-23.5, -46.6));
  });

  test('não envia assinatura falsa nem outros sinais BLE', () async {
    await emit(await FakeOrbit.create(seed: 9), -40, now);
    scanner.ads.add(OrbitAdvertisement(data: const [], at: now, rssi: -40));
    await settle();
    expect(sent, isEmpty);
    expect(controller.heardCount, 5);
    expect(controller.validCount, 0);
    expect(controller.rejectedCount, 1);
  });

  test('envia 1 vez por Orbit a cada intervalo e ignora sinal fraco', () async {
    await emit(lucas, -95, now);
    expect(sent, isEmpty);
    expect(controller.sightings, hasLength(1)); // ouvido, mas longe

    await emit(lucas, -60, now);
    expect(sent, hasLength(1));
    await emit(lucas, -50, now.add(const Duration(seconds: 10)));
    expect(sent, hasLength(1));
    await emit(ana, -70, now.add(const Duration(seconds: 10)));
    expect(sent, hasLength(2));
    await emit(lucas, -60, now.add(const Duration(seconds: 61)));
    expect(sent, hasLength(3));
  });

  test('usa o nome do painel, ou o id se ainda não tem', () async {
    await emit(lucas, -60, now);
    await emit(ana, -60, now);
    expect(
      controller.sightings.map((s) => controller.nameOf(s.signal)).toSet(),
      {'Orbit do Lucas', 'Orbit ${ana.identifier}'},
    );
  });

  test('Orbit recusado pelo servidor vira erro legível', () async {
    reportStatus = 422;
    await emit(lucas, -60, now);
    expect(controller.encounters.single.sent, isFalse);
    expect(controller.encounters.single.error, contains('desativado'));
    expect(controller.pendingCount, 0);
  });

  test('o diagnóstico mostra cada etapa da detecção', () async {
    await emit(lucas, -60, now);
    final text = controller.logs.map((l) => l.message).join('\n');
    expect(text, contains('Chave dos Orbits carregada'));
    expect(text, contains('Escuta Bluetooth iniciada'));
    expect(text, contains('(4/4) · -60 dBm'));
    expect(text, contains('Assinatura válida: ${lucas.identifier}'));
    expect(text, contains('Enviado à central: Orbit do Lucas'));
    expect(controller.fragmentCount, 4);

    await emit(ana, -95, now);
    expect(controller.logs.first.message, contains('Longe demais'));
    await emit(await FakeOrbit.create(seed: 9), -60, now);
    expect(controller.logs.first.message, contains('assinatura inválida'));
    controller.clearLogs();
    expect(controller.logs, isEmpty);
  });

  test('sem internet guarda e envia quando a conexão volta', () async {
    online = false;
    final raw = await emit(lucas, -60, now);
    expect(sent, isEmpty);
    expect(controller.pendingCount, 1);
    expect(controller.isOffline, isTrue);
    expect(controller.sendError, isNotNull);
    expect(controller.encounters.single.queued, isTrue);

    online = true;
    await controller.flush();
    expect(controller.pendingCount, 0);
    expect(controller.encounters.single.sent, isTrue);
    expect(sent.single['signal'], base64Encode(raw));
    expect(DateTime.parse(sent.single['at'] as String), now.toUtc());
    expect(sent.single['id'], controller.encounters.single.id);
  });

  test('a chave salva permite detectar abrindo o app sem internet', () async {
    online = false;
    final other = _FakeScanner();
    final c = OrbitController(
      api: api,
      queue: OrbitQueue(userId: '1'),
      scanner: other,
    );
    await c.start();
    expect(c.isWatching, isTrue);
    expect(c.error, isNull);
    c.dispose();
  });

  test('sem chave no servidor não escuta e explica', () async {
    SharedPreferences.setMockInitialValues({});
    serverKey = [];
    final c = OrbitController(
      api: api,
      queue: OrbitQueue(userId: '1'),
      scanner: _FakeScanner(),
    );
    await c.start();
    expect(c.isWatching, isFalse);
    expect(c.error, contains('ORBIT_PUBLIC_KEY'));
    c.dispose();
  });

  test('a fila sobrevive a fechar e abrir o app', () async {
    online = false;
    final raw = await emit(ana, -60, now);
    expect(controller.pendingCount, 1);

    online = true;
    final reopened = OrbitController(
      api: api,
      queue: OrbitQueue(userId: '1'),
      scanner: _FakeScanner(),
    );
    await reopened.start();
    await settle();
    expect(sent.single['signal'], base64Encode(raw));
    expect(reopened.pendingCount, 0);
    reopened.dispose();
  });

  test('a fila é por usuário e descarta itens do formato antigo', () async {
    online = false;
    await emit(lucas, -60, now);
    expect(await OrbitQueue(userId: '1').load(), hasLength(1));
    expect(await OrbitQueue(userId: '2').load(), isEmpty);

    final prefs = await SharedPreferences.getInstance();
    final items = jsonDecode(prefs.getString('orbit_queue_1')!) as List;
    items.insert(0, {'id': 'x', 'orbit': {}, 'lat': 1, 'lng': 2});
    await prefs.setString('orbit_queue_1', jsonEncode(items));
    expect(await OrbitQueue(userId: '1').load(), hasLength(1));
  });
}
