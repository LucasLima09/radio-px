import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_mobile/models/auth_session.dart';
import 'package:front_mobile/models/public_user.dart';
import 'package:front_mobile/services/api/api_client.dart';
import 'package:front_mobile/services/storage/session_store.dart';

const _user = PublicUser(id: '1', username: 'motorista');

int _inOneHour() =>
    DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch ~/ 1000;

AuthSession _session(String suffix, {int expiresAt = 0}) => AuthSession(
  accessToken: 'access-$suffix',
  refreshToken: 'refresh-$suffix',
  expiresAt: expiresAt,
  user: _user,
);

http.Response _tokens(String suffix) => http.Response(
  jsonEncode({
    'accessToken': 'access-$suffix',
    'refreshToken': 'refresh-$suffix',
    'expiresAt': _inOneHour(),
    'user': _user.toJson(),
  }),
  200,
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('renovações simultâneas usam o refresh token uma vez só', () async {
    var refreshCalls = 0;
    final client = MockClient((req) async {
      refreshCalls++;
      await Future<void>.delayed(const Duration(milliseconds: 10));
      return _tokens('new');
    });
    final store = SessionStore();
    await store.save(_session('old'));
    final api = ApiClient(
      baseUrl: 'http://x',
      sessionStore: store,
      httpClient: client,
    )..setSession(_session('old'));

    final results = await Future.wait([
      api.refresh(),
      api.refresh(),
      api.refresh(),
    ]);

    expect(results, [true, true, true]);
    expect(refreshCalls, 1);
    expect(api.accessToken, 'access-new');
  });

  test('adota a sessão já renovada por outro isolate', () async {
    var refreshCalls = 0;
    final client = MockClient((req) async {
      refreshCalls++;
      return http.Response('{"error":"refresh token revoked"}', 401);
    });
    final store = SessionStore();
    final api = ApiClient(
      baseUrl: 'http://x',
      sessionStore: store,
      httpClient: client,
    )..setSession(_session('old'));
    // O beacon renovou e gravou a sessão nova no disco.
    await store.save(_session('beacon', expiresAt: _inOneHour()));

    expect(await api.refresh(), isTrue);
    expect(refreshCalls, 0);
    expect(api.accessToken, 'access-beacon');
  });

  test('recusa sem sessão nova no disco encerra a sessão', () async {
    final client = MockClient(
      (req) async => http.Response('{"error":"refresh token revoked"}', 401),
    );
    final store = SessionStore();
    await store.save(_session('old'));
    final api = ApiClient(
      baseUrl: 'http://x',
      sessionStore: store,
      httpClient: client,
    )..setSession(_session('old'));

    expect(await api.refresh(), isFalse);
    expect(api.accessToken, isNull);
  });
}
