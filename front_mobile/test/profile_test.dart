import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_mobile/api.dart';
import 'package:front_mobile/models.dart';
import 'package:front_mobile/screens/profile_screen.dart';
import 'package:front_mobile/session_store.dart';

class ProfileTestApi extends ApiClient {
  ProfileTestApi() : super('http://localhost');
  PublicUser profile = const PublicUser(id: '1', username: 'Motorista');
  int saves = 0;
  bool conflict = false;

  @override
  Future<PublicUser> getProfile() async => profile;

  @override
  Future<PublicUser> updateProfile({
    required String username,
    String? avatar,
  }) async {
    saves++;
    if (conflict) throw ApiException(409, 'username already taken');
    profile = PublicUser(
      id: profile.id,
      username: username,
      avatar: avatar ?? profile.avatar,
    );
    return profile;
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('perfil atualizado preserva os tokens da sessão', () async {
    await SessionStore.save(
      const AuthSession(
        accessToken: 'access',
        refreshToken: 'refresh',
        expiresAt: 123,
        user: PublicUser(id: '1', username: 'Antigo'),
      ),
    );
    await SessionStore.updateUser(
      const PublicUser(id: '1', username: 'Novo', avatar: 'photo'),
    );
    final saved = await SessionStore.load();
    expect(saved!.user.username, 'Novo');
    expect(saved.user.avatar, 'photo');
    expect(saved.accessToken, 'access');
    expect(saved.refreshToken, 'refresh');
    expect(saved.expiresAt, 123);
    await SessionStore.updateUser(
      const PublicUser(id: '2', username: 'Outra conta'),
    );
    expect((await SessionStore.load())!.user.id, '1');
  });

  testWidgets('salva nome e entrega o novo perfil à navegação', (tester) async {
    final api = ProfileTestApi();
    PublicUser? updated;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ProfileScreen(
            api: api,
            user: api.profile,
            onSaved: (user) => updated = user,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), ' Novo Motorista ');
    await tester.ensureVisible(find.text('Salvar alterações'));
    await tester.tap(find.text('Salvar alterações'));
    await tester.pumpAndSettle();
    expect(updated!.username, 'Novo Motorista');
    expect(api.saves, 1);
    expect(find.text('Perfil atualizado'), findsOneWidget);
  });

  testWidgets('nome curto não é enviado e conflito mantém a edição', (
    tester,
  ) async {
    final api = ProfileTestApi();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ProfileScreen(api: api, user: api.profile, onSaved: (_) {}),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), 'a');
    await tester.ensureVisible(find.text('Salvar alterações'));
    await tester.tap(find.text('Salvar alterações'));
    await tester.pumpAndSettle();
    expect(api.saves, 0);
    expect(find.text('Use pelo menos 3 caracteres'), findsOneWidget);
    api.conflict = true;
    await tester.enterText(find.byType(TextFormField), 'Nome existente');
    await tester.ensureVisible(find.text('Salvar alterações'));
    await tester.tap(find.text('Salvar alterações'));
    await tester.pumpAndSettle();
    expect(
      find.text('Esse nome já está em uso. Escolha outro.'),
      findsOneWidget,
    );
    expect(api.profile.username, 'Motorista');
    expect(find.text('Nome existente'), findsOneWidget);
  });
}
