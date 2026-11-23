import 'input_masks.dart';

/// Regras de validação dos formulários. Cada função devolve a mensagem de
/// erro, ou `null` quando o valor é válido — o formato que o `validator` do
/// `TextFormField` espera.
abstract final class Validators {
  static final RegExp _mercosul = RegExp(r'^[A-Z]{3}[0-9][A-Z][0-9]{2}$');
  static final RegExp _username = RegExp(r'^[A-Za-z0-9._-]+$');
  static final RegExp _name = RegExp(
    r"^[\p{L}]+(?:[ '\-][\p{L}]+)*$",
    unicode: true,
  );

  /// Nome de usuário usado no login: de 3 a 30 caracteres, sem espaços.
  static String? username(String? value) {
    final name = value?.trim() ?? '';
    if (name.isEmpty) return 'Informe o usuário';
    if (!_username.hasMatch(name)) {
      return 'Use só letras sem acento, números, ponto, hífen ou sublinhado';
    }
    if (name.length < 3) return 'Use pelo menos 3 caracteres';
    if (name.length > 30) return 'Use no máximo 30 caracteres';
    return null;
  }

  static String? firstName(String? value) =>
      _personName(value, 'Informe seu primeiro nome');

  static String? lastName(String? value) =>
      _personName(value, 'Informe seu sobrenome');

  static String? _personName(String? value, String missing) {
    final name = value?.trim() ?? '';
    if (name.isEmpty) return missing;
    if (name.runes.length > 50) return 'Use no máximo 50 caracteres';
    if (!_name.hasMatch(name)) return 'Use apenas letras';
    return null;
  }

  static String? password(String? value) {
    if (value == null || value.isEmpty) return 'Informe a senha';
    if (value.length < 6) return 'Use pelo menos 6 caracteres';
    return null;
  }

  static String? confirmPassword(String? value, String password) {
    if (value == null || value.isEmpty) return 'Confirme a senha';
    if (value != password) return 'As senhas não conferem';
    return null;
  }

  /// Placa no padrão Mercosul (ABC1D23). Vazia é aceita.
  static String? plate(String? value) {
    final plate = normalizePlate(value ?? '');
    if (plate.isEmpty || _mercosul.hasMatch(plate)) return null;
    return 'Use o padrão Mercosul: ABC1D23';
  }

  /// Telefone brasileiro com DDD: fixo (10 dígitos) ou celular (11 dígitos,
  /// começando com 9). Vazio é aceito.
  static String? phone(String? value) {
    final digits = normalizePhone(value ?? '');
    if (digits.isEmpty) return null;
    if (digits.length < 10) return 'Informe DDD e número';
    if (digits.startsWith('0')) return 'DDD inválido';
    if (digits.length == 11 && digits[2] != '9') {
      return 'Celular deve começar com 9';
    }
    return null;
  }
}
