import '../../models/orbit_encounter.dart';
import 'orbit_scanner_stub.dart'
    if (dart.library.io) 'orbit_scanner_io.dart'
    if (dart.library.js_interop) 'orbit_scanner_web.dart'
    as impl;

/// Scanner Bluetooth da plataforma atual: flutter_blue_plus no Android e iOS,
/// BlueZ no Linux desktop e Web Bluetooth no Chrome.
OrbitScanner createOrbitScanner() => impl.createOrbitScanner();

/// Falha do Bluetooth com mensagem pronta para a tela.
class OrbitException implements Exception {
  OrbitException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Escuta todos os anúncios BLE em volta, sem filtrar por nome, endereço ou
/// aparelho. Quem decide o que é um Orbit é o `OrbitDecoder`, pela assinatura.
abstract class OrbitScanner {
  /// Há Bluetooth utilizável nesta plataforma.
  bool get isSupported;

  /// A escuta está disponível. Na web depende de
  /// chrome://flags/#enable-experimental-web-platform-features.
  bool get canWatch;

  /// Todo anúncio recebido; os sem dados de fabricante dos Orbits vêm com
  /// [OrbitAdvertisement.data] vazio. Cancelar a assinatura encerra a escuta.
  Stream<OrbitAdvertisement> watch();
}
