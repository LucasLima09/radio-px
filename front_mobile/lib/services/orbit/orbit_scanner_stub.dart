import '../../models/orbit_encounter.dart';
import 'orbit_scanner.dart';

OrbitScanner createOrbitScanner() => _UnsupportedOrbitScanner();

class _UnsupportedOrbitScanner implements OrbitScanner {
  @override
  bool get isSupported => false;

  @override
  bool get canWatch => false;

  @override
  bool get needsUserGesture => true;

  @override
  Stream<OrbitSighting> watch(List<RegisteredOrbit> orbits) =>
      Stream.error(OrbitException('Bluetooth indisponível nesta plataforma'));

  @override
  Future<OrbitSighting?> scanOnce(List<RegisteredOrbit> orbits) async => null;
}
