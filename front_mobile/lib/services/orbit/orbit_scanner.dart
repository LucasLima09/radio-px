import '../../models/orbit_encounter.dart';
import 'orbit_scanner_stub.dart'
    if (dart.library.io) 'orbit_scanner_io.dart'
    if (dart.library.js_interop) 'orbit_scanner_web.dart'
    as impl;

/// Scanner Bluetooth da plataforma atual: BlueZ no Linux desktop (sempre
/// ligado) e Web Bluetooth no Chrome (ligado por clique). Nas demais
/// plataformas [OrbitScanner.isSupported] é falso.
OrbitScanner createOrbitScanner() => impl.createOrbitScanner();

/// Reconhece um Orbit pelo nome anunciado. Ignora maiúsculas e espaços nas
/// pontas: o nome do aparelho costuma variar nisso ("Iphone" x "iPhone").
RegisteredOrbit? matchOrbit(List<RegisteredOrbit> orbits, String? name) {
  final key = name?.trim().toLowerCase();
  if (key == null || key.isEmpty) return null;
  for (final o in orbits) {
    if (o.identifier.trim().toLowerCase() == key) return o;
  }
  return null;
}

/// Falha do Bluetooth com mensagem pronta para a tela.
class OrbitException implements Exception {
  OrbitException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Reconhece os Orbits cadastrados pelo nome que anunciam no Bluetooth.
abstract class OrbitScanner {
  /// Há Bluetooth utilizável nesta plataforma.
  bool get isSupported;

  /// Detecção automática disponível. Na web depende de
  /// chrome://flags/#enable-experimental-web-platform-features.
  bool get canWatch;

  /// A escuta só pode começar a partir de um clique (exigência do navegador).
  /// Quando é falso, o app liga a detecção sozinho e a mantém ligada.
  bool get needsUserGesture;

  /// Escuta os anúncios de qualquer um dos [orbits]. Cancelar a assinatura
  /// encerra a escuta.
  Stream<OrbitSighting> watch(List<RegisteredOrbit> orbits);

  /// Modo manual: abre o seletor do navegador mostrando só os [orbits] que
  /// estão por perto. Devolve o escolhido, ou `null` se o usuário cancelar.
  Future<OrbitSighting?> scanOnce(List<RegisteredOrbit> orbits);
}
