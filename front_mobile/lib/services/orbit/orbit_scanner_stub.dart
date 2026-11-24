import '../../models/orbit_encounter.dart';
import 'orbit_scanner.dart';

OrbitScanner createOrbitScanner() => _UnsupportedOrbitScanner();

class _UnsupportedOrbitScanner implements OrbitScanner {
  @override
  bool get isSupported => false;

  @override
  bool get canWatch => false;

  @override
  Stream<OrbitAdvertisement> watch() =>
      Stream.error(OrbitException('Bluetooth indisponível nesta plataforma'));
}
