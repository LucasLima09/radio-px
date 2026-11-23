import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:front_mobile/utils/input_masks.dart';

TextEditingValue _typed(String text) => TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );

void main() {
  group('formatPlate', () {
    test('monta o padrão Mercosul', () {
      expect(formatPlate('abc1d23'), 'ABC1D23');
      expect(formatPlate('abc-1d23'), 'ABC1D23');
      expect(formatPlate('ABC1D234'), 'ABC1D23');
    });

    test('converte a placa antiga para Mercosul', () {
      expect(formatPlate('ABC1234'), 'ABC1C34');
      expect(formatPlate('XYZ-9087'), 'XYZ9A87');
    });

    test('descarta caracteres fora do lugar', () {
      expect(formatPlate('1ABC'), 'ABC');
      expect(formatPlate('ABCD'), 'ABC');
      expect(formatPlate('ABC1DE'), 'ABC1D');
    });
  });

  group('formatPhone', () {
    test('formata enquanto digita', () {
      expect(formatPhone('1'), '(1');
      expect(formatPhone('11'), '(11');
      expect(formatPhone('119'), '(11) 9');
      expect(formatPhone('1198765'), '(11) 9876-5');
    });

    test('fixo e celular', () {
      expect(formatPhone('1133334444'), '(11) 3333-4444');
      expect(formatPhone('11987654321'), '(11) 98765-4321');
      expect(formatPhone('119876543219'), '(11) 98765-4321');
    });
  });

  test('backspace num separador apaga o dígito anterior', () {
    final formatter = PhoneInputFormatter();
    const old = TextEditingValue(
      text: '(11) 9876-5',
      selection: TextSelection.collapsed(offset: 10),
    );
    final result = formatter.formatEditUpdate(
      old,
      const TextEditingValue(
        text: '(11) 98765',
        selection: TextSelection.collapsed(offset: 9),
      ),
    );
    expect(result.text, '(11) 9875');
    expect(result.selection.baseOffset, 8);
  });

  test('máscara da placa mantém o cursor no fim ao digitar', () {
    final result =
        PlateInputFormatter().formatEditUpdate(_typed('ABC'), _typed('abc1'));
    expect(result.text, 'ABC1');
    expect(result.selection.baseOffset, 4);
  });
}
