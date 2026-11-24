import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../../models/orbit_encounter.dart';
import 'orbit_decoder.dart';
import 'orbit_scanner.dart';

/// Varredura BLE contínua no Android e no iOS. Começa no login, sem botão; as
/// permissões de Bluetooth são pedidas pelo próprio plugin na primeira busca.
///
/// Com o app aberto a busca não tem filtro. Em segundo plano o Android
/// suspende buscas sem filtro quando a tela apaga, então passa a filtrar pelo
/// formato do sinal dos Orbits (a assinatura continua sendo conferida).
class MobileOrbitScanner implements OrbitScanner {
  /// A busca é recomeçada nesse intervalo. Religa a busca se ela parou
  /// (Bluetooth desligado e religado), cobre os Androids que só avisam cada
  /// aparelho uma vez por busca e evita o rebaixamento de buscas longas. O
  /// Android recusa mais de 5 inícios de busca a cada 30 s.
  static const _restartEvery = Duration(seconds: 20);

  static bool get _mobile => Platform.isAndroid || Platform.isIOS;

  @override
  bool get isSupported => _mobile;

  @override
  bool get canWatch => _mobile;

  @override
  Stream<OrbitAdvertisement> watch() {
    late final StreamController<OrbitAdvertisement> controller;
    StreamSubscription<List<ScanResult>>? results;
    StreamSubscription<BluetoothAdapterState>? adapter;
    AppLifecycleListener? lifecycle;
    Timer? watchdog;
    var background = false;
    var starting = false;
    var stopped = false;

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
          withMsd: [
            if (background)
              MsdFilter(
                OrbitDecoder.companyId,
                data: const [OrbitDecoder.magic, OrbitDecoder.version],
              ),
          ],
          continuousUpdates: true,
          // Cada anúncio importa: os pedaços do sinal chegam em anúncios
          // diferentes, às vezes do mesmo endereço.
          oneByOne: true,
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
        controller.add(
          OrbitAdvertisement(
            data:
                r.advertisementData.manufacturerData[OrbitDecoder.companyId] ??
                const [],
            rssi: r.rssi,
            at: r.timeStamp,
          ),
        );
      }
    }

    Future<void> start() async {
      if (!await FlutterBluePlus.isSupported) {
        return fail('Este aparelho não tem Bluetooth LE');
      }
      if (stopped) return;
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
      lifecycle = AppLifecycleListener(
        onHide: () {
          background = true;
          ensureScanning(restart: true);
        },
        onShow: () {
          background = false;
          ensureScanning(restart: true);
        },
      );
      watchdog = Timer.periodic(
        _restartEvery,
        (_) => ensureScanning(restart: true),
      );
    }

    Future<void> stop() async {
      stopped = true;
      watchdog?.cancel();
      lifecycle?.dispose();
      await results?.cancel();
      await adapter?.cancel();
      try {
        await FlutterBluePlus.stopScan();
      } catch (_) {}
    }

    controller = StreamController<OrbitAdvertisement>(
      onListen: start,
      onCancel: stop,
    );
    return controller.stream;
  }
}
