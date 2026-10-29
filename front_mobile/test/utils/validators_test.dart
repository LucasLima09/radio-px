import 'package:flutter_test/flutter_test.dart';

import 'package:front_mobile/utils/validators.dart';

void main() {
  test('usuário', () {
    expect(Validators.username('lucas.lima'), isNull);
    expect(Validators.username('Lucas_09'), isNull);
    expect(Validators.username('lucas lima'),
        'Use só letras sem acento, números, ponto, hífen ou sublinhado');
    expect(Validators.username('lu'), 'Use pelo menos 3 caracteres');
    expect(Validators.username('a' * 31), 'Use no máximo 30 caracteres');
  });

  test('primeiro nome', () {
    expect(Validators.firstName('Lucas'), isNull);
    expect(Validators.firstName('Ana Clara'), isNull);
    expect(Validators.firstName(''), 'Informe seu primeiro nome');
  });

  test('sobrenome', () {
    expect(Validators.lastName('Lima'), isNull);
    expect(Validators.lastName("D'Ávila Souza-Neto"), isNull);
    expect(Validators.lastName(' '), 'Informe seu sobrenome');
    expect(Validators.lastName('Lima2'), 'Use apenas letras');
  });

  test('placa Mercosul', () {
    expect(Validators.plate(''), isNull);
    expect(Validators.plate('ABC1D23'), isNull);
    expect(Validators.plate('ABC1234'), 'Use o padrão Mercosul: ABC1D23');
    expect(Validators.plate('ABC1D2'), 'Use o padrão Mercosul: ABC1D23');
  });

  test('telefone', () {
    expect(Validators.phone(''), isNull);
    expect(Validators.phone('(11) 98765-4321'), isNull);
    expect(Validators.phone('(11) 3333-4444'), isNull);
    expect(Validators.phone('(11) 9876'), 'Informe DDD e número');
    expect(Validators.phone('(01) 3333-4444'), 'DDD inválido');
    expect(Validators.phone('(11) 38765-4321'), 'Celular deve começar com 9');
  });

  test('senhas', () {
    expect(Validators.password('12345'), 'Use pelo menos 6 caracteres');
    expect(Validators.confirmPassword('abcdef', 'abcdeg'), 'As senhas não conferem');
    expect(Validators.confirmPassword('abcdef', 'abcdef'), isNull);
  });
}
