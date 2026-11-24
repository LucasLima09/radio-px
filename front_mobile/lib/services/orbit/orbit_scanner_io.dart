import 'dart:async';
import 'dart:io';

import 'package:bluez/bluez.dart';

import '../../models/orbit_encounter.dart';
import 'orbit_decoder.dart';
import 'orbit_scanner.dart';
import 'orbit_scanner_mobile.dart';

/// Linux usa o BlueZ direto; Android e iOS, o flutter_blue_plus.
OrbitScanner createOrbitScanner() =>
    Platform.isLinux ? _BlueZOrbitScanner() : MobileOrbitScanner();

/// Varredura contínua pelo BlueZ, o Bluetooth do Linux, via D-Bus. Não precisa
/// de clique nem de permissão: começa no login e fica ligada.
///
/// O BlueZ atualiza o RSSI e os dados de cada aparelho a cada anúncio recebido;
/// cada atualização vira um [OrbitAdvertisement].
class _BlueZOrbitScanner implements OrbitScanner {
  static const _companyId = BlueZManufacturerId(OrbitDecoder.companyId);

  /// Se a busca parar (adaptador desligado e religado, outro programa
  /// encerrou a busca), ela é religada nesse intervalo.
  static const _watchdog = Duration(seconds: 10);

  @override
  bool get isSupported => Platform.isLinux;

  @override
  bool get canWatch => Platform.isLinux;

  @override
  Stream<OrbitAdvertisement> watch() {
    late final StreamController<OrbitAdvertisement> controller;
    final client = BlueZClient();
    final subs = <StreamSubscription<Object?>>[];
    final deviceSubs = <BlueZDevice, StreamSubscription<List<String>>>{};
    Timer? watchdog;
    BlueZAdapter? adapter;

    void check(BlueZDevice device) {
      // RSSI 0 = o BlueZ conhece o aparelho, mas não o ouviu nesta busca.
      final rssi = device.rssi;
      if (rssi == 0) return;
      controller.add(
        OrbitAdvertisement(
          data: device.manufacturerData[_companyId] ?? const [],
          rssi: rssi,
          at: DateTime.now(),
        ),
      );
    }

    void track(BlueZDevice device) {
      deviceSubs[device] ??= device.propertiesChanged.listen((changed) {
        if (changed.contains('RSSI') || changed.contains('ManufacturerData')) {
          check(device);
        }
      });
      check(device);
    }

    Future<void> ensureDiscovering() async {
      final a = adapter;
      if (a == null || !a.powered || a.discovering) return;
      try {
        await a.startDiscovery();
      } catch (_) {
        // Adaptador ocupado ou ainda ligando: o watchdog tenta de novo.
      }
    }

    Future<void> start() async {
      try {
        await client.connect();
      } catch (error) {
        controller.addError(
          OrbitException(
            'Não foi possível acessar o Bluetooth do sistema: $error',
          ),
        );
        return;
      }
      if (client.adapters.isEmpty) {
        controller.addError(
          OrbitException('Nenhum adaptador Bluetooth encontrado'),
        );
        return;
      }
      adapter = client.adapters.first;
      try {
        // DuplicateData: o BlueZ repassa cada anúncio repetido, mantendo o
        // RSSI atualizado enquanto o Orbit estiver por perto.
        await adapter!.setDiscoveryFilter(transport: 'le', duplicateData: true);
      } catch (_) {}

      client.devices.forEach(track);
      subs
        ..add(client.deviceAdded.listen(track))
        ..add(
          client.deviceRemoved.listen(
            (device) => deviceSubs.remove(device)?.cancel(),
          ),
        );
      await ensureDiscovering();
      watchdog = Timer.periodic(_watchdog, (_) => ensureDiscovering());
    }

    Future<void> stop() async {
      watchdog?.cancel();
      for (final sub in [...subs, ...deviceSubs.values]) {
        await sub.cancel();
      }
      try {
        if (adapter?.discovering ?? false) await adapter!.stopDiscovery();
      } catch (_) {}
      await client.close();
    }

    controller = StreamController<OrbitAdvertisement>(
      onListen: start,
      onCancel: stop,
    );
    return controller.stream;
  }
}
