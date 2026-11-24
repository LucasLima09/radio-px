import 'dart:async';
import 'dart:io';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../../models/orbit_encounter.dart';
import 'orbit_scanner.dart';

/// Varredura BLE contínua no Android e no iOS. Começa no login, sem botão; as
/// permissões de Bluetooth são pedidas pelo próprio plugin na primeira busca.
///
/// A busca usa o filtro de nome do sistema (o identificador cadastrado no
/// painel, exato). No Android, só buscas com filtro continuam rodando com a
/// tela desligada, o que mantém a detecção viva com o app em segundo plano
/// (o serviço de foreground do rádio segura o processo).
class MobileOrbitScanner implements OrbitScanner {
  /// A busca é recomeçada nesse intervalo. Com filtro, muitos Androids só
  /// avisam cada aparelho uma vez por busca; recomeçar faz o Orbit que
  /// continua por perto ser avisado de novo. Também religa a busca se ela
  /// parou (Bluetooth desligado e religado). O Android recusa mais de 5
  /// inícios de busca a cada 30 s.
  static const _restartEvery = Duration(seconds: 20);

  static bool get _mobile => Platform.isAndroid || Platform.isIOS;

  @override
  bool get isSupported => _mobile;

  @override
  bool get canWatch => _mobile;

  @override
  bool get needsUserGesture => false;

  @override
  Stream<OrbitSighting> watch(List<RegisteredOrbit> orbits) {
    late final StreamController<OrbitSighting> controller;
    StreamSubscription<List<ScanResult>>? results;
    StreamSubscription<BluetoothAdapterState>? adapter;
    Timer? watchdog;
    var starting = false;
    var stopped = false;
    // A lista de resultados é reenviada inteira a cada anúncio; só conta o
    // que chegou depois do último visto de cada aparelho.
    final seen = <DeviceIdentifier, DateTime>{};

    void fail(String message) {
      if (!stopped) controller.addError(OrbitException(message));
    }

    Future<void> ensureScanning({bool restart = false}) async {
      if (stopped || starting) return;
      if (FlutterBluePlus.isScanningNow && !restart) return;
      if (FlutterBluePlus.adapterStateNow != BluetoothAdapterState.on) return;
      starting = true;
      try {
        if (FlutterBluePlus.isScanningNow) await FlutterBluePlus.stopScan();
        if (stopped) return;
        await FlutterBluePlus.startScan(
          withNames: [for (final o in orbits) o.identifier],
          continuousUpdates: true,
          androidScanMode: AndroidScanMode.lowLatency,
          // O app já usa localização; sem isso o Android pode esconder
          // beacons dos resultados.
          androidUsesFineLocation: true,
        );
      } catch (error) {
        fail('Bluetooth: $error');
      } finally {
        starting = false;
      }
    }

    void onResults(List<ScanResult> list) {
      for (final r in list) {
        final last = seen[r.device.remoteId];
        if (last != null && !r.timeStamp.isAfter(last)) continue;
        seen[r.device.remoteId] = r.timeStamp;
        final name = r.advertisementData.advName.isNotEmpty
            ? r.advertisementData.advName
            : r.device.platformName;
        final orbit = matchOrbit(orbits, name);
        if (orbit == null) continue;
        controller.add(
          OrbitSighting(orbit: orbit, rssi: r.rssi, at: r.timeStamp),
        );
      }
    }

    Future<void> start() async {
      if (orbits.isEmpty) return fail('Nenhum Orbit cadastrado');
      if (!await FlutterBluePlus.isSupported) {
        return fail('Este aparelho não tem Bluetooth LE');
      }
      results = FlutterBluePlus.onScanResults.listen(onResults);
      adapter = FlutterBluePlus.adapterState.listen((state) {
        switch (state) {
          case BluetoothAdapterState.on:
            ensureScanning();
          case BluetoothAdapterState.off:
            fail('Bluetooth desligado. Ligue o Bluetooth do aparelho.');
          case BluetoothAdapterState.unauthorized:
            fail('Permissão de Bluetooth negada nas configurações.');
          default:
            break;
        }
      });
      watchdog = Timer.periodic(
        _restartEvery,
        (_) => ensureScanning(restart: true),
      );
    }

    Future<void> stop() async {
      stopped = true;
      watchdog?.cancel();
      await results?.cancel();
      await adapter?.cancel();
      try {
        await FlutterBluePlus.stopScan();
      } catch (_) {}
    }

    controller = StreamController<OrbitSighting>(
      onListen: start,
      onCancel: stop,
    );
    return controller.stream;
  }

  @override
  Future<OrbitSighting?> scanOnce(List<RegisteredOrbit> orbits) async => null;
}
