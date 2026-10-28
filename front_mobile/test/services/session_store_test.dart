import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_mobile/models/auth_session.dart';
import 'package:front_mobile/models/public_user.dart';
import 'package:front_mobile/services/storage/session_store.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('perfil atualizado preserva os tokens da sessão', () async {
    final store = SessionStore();
    await store.save(
      const AuthSession(
        accessToken: 'access',
        refreshToken: 'refresh',
        expiresAt: 123,
        user: PublicUser(id: '1', username: 'Antigo'),
      ),
    );
    await store.updateUser(
      const PublicUser(id: '1', username: 'Novo', avatar: 'photo'),
    );
    final saved = await store.load();
    expect(saved!.user.username, 'Novo');
    expect(saved.user.avatar, 'photo');
    expect(saved.accessToken, 'access');
    expect(saved.refreshToken, 'refresh');
    expect(saved.expiresAt, 123);
    await store.updateUser(
      const PublicUser(id: '2', username: 'Outra conta'),
    );
    expect((await store.load())!.user.id, '1');
  });

  test('sessão apagada não volta do armazenamento', () async {
    final store = SessionStore();
    await store.save(
      const AuthSession(
        accessToken: 'access',
        refreshToken: 'refresh',
        expiresAt: 123,
        user: PublicUser(id: '1', username: 'Antigo'),
      ),
    );
    await store.clear();
    expect(await store.load(), isNull);
  });
}
