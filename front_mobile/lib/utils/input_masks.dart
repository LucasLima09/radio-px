import 'package:flutter/services.dart';

/// Só deixa digitar os caracteres aceitos no nome de usuário.
final usernameInputFormatter =
    FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9._-]'));

/// Placa em maiúsculas e só com letras e números — o formato do servidor.
String normalizePlate(String value) =>
    value.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');

/// Só os dígitos do telefone — o formato do servidor.
String normalizePhone(String value) => value.replaceAll(RegExp(r'\D'), '');

/// Monta a placa no padrão Mercosul (LLLNLNN) a partir do que foi digitado.
///
/// Caracteres fora do lugar são descartados. Um número na quinta posição
/// vira a letra equivalente (0→A, 1→B, ... 9→J), a mesma conversão oficial
/// das placas antigas: ABC1234 vira ABC1C34.
String formatPlate(String raw) {
  final out = StringBuffer();
  for (final c in normalizePlate(raw).split('')) {
    if (out.length == 7) break;
    final letter = c.compareTo('A') >= 0;
    switch (out.length) {
      case 0 || 1 || 2:
        if (letter) out.write(c);
      case 3 || 5 || 6:
        if (!letter) out.write(c);
      case 4:
        out.write(letter ? c : String.fromCharCode(65 + int.parse(c)));
    }
  }
  return out.toString();
}

/// Formata o telefone como (11) 98765-4321 ou (11) 3333-4444.
String formatPhone(String raw) {
  var digits = normalizePhone(raw);
  if (digits.length > 11) digits = digits.substring(0, 11);
  if (digits.isEmpty) return '';
  if (digits.length <= 2) return '($digits';
  final ddd = digits.substring(0, 2);
  final rest = digits.substring(2);
  if (rest.length <= 4) return '($ddd) $rest';
  final split = rest.length == 9 ? 5 : 4;
  return '($ddd) ${rest.substring(0, split)}-${rest.substring(split)}';
}

/// Máscara da placa Mercosul enquanto se digita.
class PlateInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final text = formatPlate(newValue.text);
    // A placa não tem separadores: o que vem antes do cursor, formatado,
    // dá a nova posição do cursor.
    final cursor = newValue.selection.isValid
        ? formatPlate(newValue.text.substring(0, newValue.selection.end)).length
        : text.length;
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: cursor),
    );
  }
}

/// Máscara do telefone enquanto se digita.
class PhoneInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    var raw = newValue.text;
    var end = newValue.selection.isValid ? newValue.selection.end : raw.length;
    // Apagar um separador ( "(", ")", " " ou "-" ) não muda os dígitos e a
    // máscara o colocaria de volta: apaga o dígito anterior a ele.
    if (raw.length < oldValue.text.length &&
        normalizePhone(raw) == normalizePhone(oldValue.text)) {
      final before = normalizePhone(raw.substring(0, end));
      if (before.isNotEmpty) {
        final digits = normalizePhone(raw);
        final cut = before.length - 1;
        raw = digits.substring(0, cut) + digits.substring(cut + 1);
        end = cut;
      }
    }
    final text = formatPhone(raw);
    final digitsBefore = raw == newValue.text
        ? normalizePhone(raw.substring(0, end)).length
        : end;
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(
        offset: _offsetAfter(text, digitsBefore),
      ),
    );
  }

  /// Posição no texto formatado logo depois do [digits]-ésimo dígito.
  static int _offsetAfter(String text, int digits) {
    if (digits <= 0) return text.isEmpty ? 0 : 1;
    var seen = 0;
    for (var i = 0; i < text.length; i++) {
      if (RegExp(r'\d').hasMatch(text[i]) && ++seen == digits) return i + 1;
    }
    return text.length;
  }
}
