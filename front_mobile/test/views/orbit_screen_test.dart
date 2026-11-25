import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:front_mobile/controllers/orbit_controller.dart';
import 'package:front_mobile/models/auth_session.dart';
import 'package:front_mobile/models/orbit_encounter.dart';
import 'package:front_mobile/models/public_user.dart';
import 'package:front_mobile/services/api/api_client.dart';
import 'package:front_mobile/services/orbit/orbit_queue.dart';
import 'package:front_mobile/services/orbit/orbit_scanner.dart';
import 'package:front_mobile/services/storage/session_store.dart';
import 'package:front_mobile/views/screens/orbit_screen.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../orbit_signals.dart';

class _Scanner implements OrbitScanner {
  final ads = StreamController<OrbitAdvertisement>.broadcast();

  @override
  bool get isSupported => true;

  @override
  bool get canWatch => true;

  @override
  Stream<OrbitAdvertisement> watch() => ads.stream;
}

void main() {
  testWidgets('mostra o Orbit detectado, o envio e o diagnóstico', (t) async {
    t.view.physicalSize = const Size(1080, 4000);
    t.view.devicePixelRatio = 2;
    addTearDown(t.view.reset);
    SharedPreferences.setMockInitialValues({});
    final scanner = _Scanner();
    late OrbitController controller;
    await t.runAsync(() async {
      final orbit = await FakeOrbit.create();
      controller = OrbitController(
        api:
            ApiClient(
              baseUrl: 'http://central',
              sessionStore: SessionStore(),
              httpClient: MockClient(
                (req) async => req.method == 'GET'
                    ? http.Response(
                        jsonEncode({
                          'publicKey': base64Encode(orbit.publicKey),
                          'orbits': [
                            {
                              'identifier': orbit.identifier,
                              'name': 'Caminhao 12',
                            },
                          ],
                        }),
                        200,
                      )
                    : http.Response('', 204),
              ),
            )..setSession(
              const AuthSession(
                accessToken: 'a',
                refreshToken: 'r',
                expiresAt: 0,
                user: PublicUser(id: '1', username: 'motorista'),
              ),
            ),
        queue: OrbitQueue(userId: '1'),
        scanner: scanner,
      );
      await controller.start();
      final now = DateTime.now();
      advertise(await orbit.sign(now), now, rssi: -60).forEach(scanner.ads.add);
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(body: OrbitScreen(controller: controller)),
      ),
    );

    expect(find.text('Procurando Orbits por perto'), findsOneWidget);
    expect(find.text('Caminhao 12'), findsNWidgets(2)); // por perto e enviado
    expect(find.textContaining('-23.50000, -46.60000'), findsNWidgets(2));
    expect(find.textContaining('Chave dos Orbits: carregada'), findsOneWidget);
    expect(find.textContaining('http://central'), findsOneWidget);
    expect(find.textContaining('Enviado à central'), findsOneWidget);
    expect(t.takeException(), isNull);

    controller.dispose();
  });
}
