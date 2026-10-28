import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_mobile/controllers/profile_controller.dart';
import 'package:front_mobile/models/public_user.dart';
import 'package:front_mobile/services/api/api_client.dart';
import 'package:front_mobile/services/api/api_exception.dart';
import 'package:front_mobile/services/storage/session_store.dart';
import 'package:front_mobile/views/screens/profile_screen.dart';

/// API de mentira: só o que a tela de perfil usa.
class ProfileTestApi extends ApiClient {
  ProfileTestApi()
      : super(baseUrl: 'http://localhost', sessionStore: SessionStore());

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

Widget _host(ProfileController controller) => MaterialApp(
      home: Scaffold(body: ProfileScreen(controller: controller)),
    );

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('salva nome e entrega o novo perfil à navegação', (tester) async {
    final api = ProfileTestApi();
    PublicUser? updated;
    final controller = ProfileController(
      api: api,
      user: api.profile,
      onUserChanged: (user) => updated = user,
    );
    await tester.pumpWidget(_host(controller));
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
      _host(ProfileController(api: api, user: api.profile)),
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
