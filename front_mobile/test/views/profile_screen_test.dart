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

  PublicUser profile = const PublicUser(
    id: '1',
    username: 'motorista',
    firstName: 'João',
    lastName: 'Silva',
  );
  int saves = 0;
  bool conflict = false;

  @override
  Future<PublicUser> getProfile() async => profile;

  @override
  Future<PublicUser> updateProfile({
    required String username,
    String? firstName,
    String? lastName,
    String? vehiclePlate,
    String? phone,
    String? avatar,
  }) async {
    saves++;
    if (conflict) throw ApiException(409, 'username already taken');
    profile = PublicUser(
      id: profile.id,
      username: username,
      firstName: firstName ?? profile.firstName,
      lastName: lastName ?? profile.lastName,
      vehiclePlate: vehiclePlate ?? profile.vehiclePlate,
      phone: phone ?? profile.phone,
      avatar: avatar ?? profile.avatar,
    );
    return profile;
  }
}

final _userField = find.widgetWithText(TextFormField, 'Usuário');
final _firstNameField = find.widgetWithText(TextFormField, 'Primeiro nome');
final _lastNameField = find.widgetWithText(TextFormField, 'Sobrenome');
final _plateField = find.widgetWithText(TextFormField, 'Placa do veículo');
final _phoneField = find.widgetWithText(TextFormField, 'Contato (telefone)');

String _text(WidgetTester tester, Finder field) => tester
    .widget<EditableText>(
      find.descendant(of: field, matching: find.byType(EditableText)),
    )
    .controller
    .text;

/// O formulário passa da altura da tela de teste: rola até o botão antes
/// de tocar.
Future<void> _tapSave(WidgetTester tester) async {
  await tester.ensureVisible(find.text('Salvar alterações'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Salvar alterações'));
  await tester.pumpAndSettle();
}

Widget _host(ProfileController controller) => MaterialApp(
      home: Scaffold(body: ProfileScreen(controller: controller)),
    );

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('salva usuário e nomes e entrega o novo perfil à navegação', (tester) async {
    final api = ProfileTestApi();
    PublicUser? updated;
    final controller = ProfileController(
      api: api,
      user: api.profile,
      onUserChanged: (user) => updated = user,
    );
    await tester.pumpWidget(_host(controller));
    await tester.pumpAndSettle();
    await tester.enterText(_firstNameField, ' Pedro ');
    await tester.enterText(_lastNameField, 'Souza');
    await tester.enterText(_userField, 'novo.motorista');
    await _tapSave(tester);
    expect(updated!.username, 'novo.motorista');
    expect(updated!.firstName, 'Pedro');
    expect(updated!.lastName, 'Souza');
    expect(api.saves, 1);
    expect(find.text('Perfil atualizado'), findsOneWidget);
  });

  testWidgets('usuário curto não é enviado e conflito mantém a edição', (
    tester,
  ) async {
    final api = ProfileTestApi();
    await tester.pumpWidget(
      _host(ProfileController(api: api, user: api.profile)),
    );
    await tester.pumpAndSettle();
    await tester.enterText(_userField, 'a');
    await _tapSave(tester);
    expect(api.saves, 0);
    expect(find.text('Use pelo menos 3 caracteres'), findsOneWidget);
    api.conflict = true;
    await tester.enterText(_userField, 'usuario.existente');
    await _tapSave(tester);
    expect(
      find.text('Esse usuário já está em uso. Escolha outro.'),
      findsOneWidget,
    );
    expect(api.profile.username, 'motorista');
    expect(find.text('usuario.existente'), findsOneWidget);
  });

  testWidgets('conta antiga com espaço no usuário continua salvando', (
    tester,
  ) async {
    final api = ProfileTestApi()
      ..profile = const PublicUser(
        id: '1',
        username: 'Motorista Antigo',
        firstName: 'João',
        lastName: 'Silva',
      );
    await tester.pumpWidget(
      _host(ProfileController(api: api, user: api.profile)),
    );
    await tester.pumpAndSettle();
    await tester.enterText(_phoneField, '11987654321');
    await _tapSave(tester);
    expect(api.saves, 1);
    expect(api.profile.username, 'Motorista Antigo');
  });

  testWidgets('primeiro nome e sobrenome são obrigatórios', (tester) async {
    final api = ProfileTestApi();
    await tester.pumpWidget(
      _host(ProfileController(api: api, user: api.profile)),
    );
    await tester.pumpAndSettle();
    await tester.enterText(_firstNameField, '');
    await tester.enterText(_lastNameField, 'Silva2');
    await _tapSave(tester);
    expect(api.saves, 0);
    expect(find.text('Informe seu primeiro nome'), findsOneWidget);
    expect(find.text('Use apenas letras'), findsOneWidget);
  });

  testWidgets('salva placa e telefone normalizados', (tester) async {
    final api = ProfileTestApi();
    await tester.pumpWidget(
      _host(ProfileController(api: api, user: api.profile)),
    );
    await tester.pumpAndSettle();
    await tester.enterText(_plateField, 'abc-1d23');
    await tester.enterText(_phoneField, '(11) 98765-4321');
    await _tapSave(tester);
    expect(api.saves, 1);
    expect(api.profile.vehiclePlate, 'ABC1D23');
    expect(api.profile.phone, '11987654321');
    expect(_text(tester, _plateField), 'ABC1D23');
    expect(_text(tester, _phoneField), '(11) 98765-4321');
  });

  testWidgets('placa e telefone inválidos não são enviados', (tester) async {
    final api = ProfileTestApi();
    await tester.pumpWidget(
      _host(ProfileController(api: api, user: api.profile)),
    );
    await tester.pumpAndSettle();
    await tester.enterText(_plateField, 'AB12');
    await tester.enterText(_phoneField, '1234');
    await _tapSave(tester);
    expect(api.saves, 0);
    expect(find.text('Use o padrão Mercosul: ABC1D23'), findsOneWidget);
    expect(find.text('Informe DDD e número'), findsOneWidget);
  });
}
