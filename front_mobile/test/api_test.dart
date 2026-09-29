import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_mobile/api.dart';
import 'package:front_mobile/models.dart';

int unixNow() => DateTime.now().millisecondsSinceEpoch ~/ 1000;

PublicUser tester() => PublicUser.fromJson({
      'id': '00000000-0000-0000-0000-000000000000',
      'username': 'tester',
    });

void main() {
  // Sem refresh token, refresh() devolve false e ensureAccessToken lança. Isso
  // permite distinguir "devolveu o token em cache" de "tentou renovar" sem
  // precisar de rede.
  setUp(() => SharedPreferences.setMockInitialValues({}));

  ApiClient clientExpiringIn(Duration ttl) {
    final api = ApiClient('http://localhost:8080');
    api.setSession(AuthSession(
      accessToken: 'access-token',
      refreshToken: '',
      expiresAt: unixNow() + ttl.inSeconds,
      user: tester(),
    ));
    return api;
  }

  test('devolve o token em cache quando ainda é válido', () async {
    final api = clientExpiringIn(const Duration(minutes: 10));
    expect(await api.ensureAccessToken(), 'access-token');
  });

  test('renova em vez de devolver um token expirado', () async {
    final api = clientExpiringIn(const Duration(minutes: -1));
    await expectLater(api.ensureAccessToken(), throwsA(isA<ApiException>()));
  });

  test('renova antes do vencimento, com margem para o handshake', () async {
    final api = clientExpiringIn(const Duration(seconds: 10));
    await expectLater(api.ensureAccessToken(), throwsA(isA<ApiException>()));
  });

  test('confia no token quando o servidor não informou a validade', () async {
    final api = clientExpiringIn(Duration.zero);
    api.setSession(AuthSession(
      accessToken: 'opaque-token',
      refreshToken: '',
      expiresAt: 0,
      user: tester(),
    ));
    expect(await api.ensureAccessToken(), 'opaque-token');
  });
}
