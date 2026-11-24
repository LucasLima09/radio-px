import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:web/web.dart' as web;

import '../../models/orbit_encounter.dart';
import 'orbit_scanner.dart';

OrbitScanner createOrbitScanner() => _WebOrbitScanner();

// Bindings mínimos da Web Bluetooth API: o package:web não traz essa spec.

extension type _Bluetooth._(JSObject _) implements web.EventTarget {
  external JSPromise<_BluetoothDevice> requestDevice(JSObject options);
  external JSPromise<_LEScan> requestLEScan(JSObject options);
}

extension type _BluetoothDevice._(JSObject _) implements JSObject {
  external String? get name;
}

extension type _LEScan._(JSObject _) implements JSObject {
  external void stop();
}

extension type _AdvertisementEvent._(JSObject _) implements web.Event {
  external _BluetoothDevice get device;
  external String? get name;
  external int? get rssi;
}

const _advertisementEvent = 'advertisementreceived';
const _interactionEvents = ['pointerdown', 'pointerup', 'keydown'];
final _capture = true.toJS;

// Só um pedido de busca por vez na página: um segundo requestLEScan com o
// pedido de permissão aberto faz o Chrome cancelar o primeiro.
bool _prompting = false;
var _requests = 0;

class _WebOrbitScanner implements OrbitScanner {
  _Bluetooth? get _bluetooth {
    final navigator = web.window.navigator as JSObject;
    if (!navigator.has('bluetooth')) return null;
    return navigator.getProperty<JSObject?>('bluetooth'.toJS) as _Bluetooth?;
  }

  @override
  bool get isSupported => _bluetooth != null;

  @override
  bool get canWatch => _bluetooth?.has('requestLEScan') ?? false;

  // O Chrome só libera a busca dentro de uma interação do usuário, mas não
  // precisa ser um botão: a busca começa no primeiro toque/tecla em qualquer
  // lugar do app (ver [watch]).
  @override
  bool get needsUserGesture => false;

  @override
  Stream<OrbitSighting> watch(List<RegisteredOrbit> orbits) {
    late final StreamController<OrbitSighting> controller;
    _Bluetooth? bluetooth;
    JSFunction? listener;
    _LEScan? scan;

    void handle(web.Event event) {
      final ad = event as _AdvertisementEvent;
      final orbit = matchOrbit(orbits, ad.name ?? ad.device.name);
      if (orbit == null) return;
      controller.add(
        OrbitSighting(orbit: orbit, rssi: ad.rssi, at: DateTime.now()),
      );
    }

    Future<void> beginScan() async {
      try {
        if (orbits.isEmpty) throw OrbitException('Nenhum Orbit cadastrado');
        bluetooth = _require();
        _prompting = true;
        final n = ++_requests;
        debugPrint('[Orbit] pedindo busca #$n');
        listener = handle.toJS;
        bluetooth!.addEventListener(_advertisementEvent, listener);
        // Filtra pelo nome anunciado, o que sobrevive à troca periódica de
        // endereço Bluetooth do aparelho.
        scan = await bluetooth!
            .requestLEScan(
              {
                    'filters': [
                      for (final o in orbits) {'name': o.identifier},
                    ],
                    'keepRepeatedDevices': true,
                  }.jsify()
                  as JSObject,
            )
            .toDart;
        debugPrint('[Orbit] busca #$n liberada');
      } catch (error) {
        controller.addError(
          error is OrbitException ? error : OrbitException(_describe(error)),
        );
      } finally {
        _prompting = false;
      }
    }

    // Sem interação recente o Chrome recusa o requestLEScan; espera o primeiro
    // toque/tecla em qualquer lugar e chama dentro do próprio evento (antes
    // de qualquer await, para não perder a ativação).
    JSFunction? onInteraction;
    void unwaitInteraction() {
      if (onInteraction == null) return;
      for (final type in _interactionEvents) {
        web.window.removeEventListener(type, onInteraction, _capture);
      }
      onInteraction = null;
    }

    void start() {
      if (!_prompting && web.window.navigator.userActivation.isActive) {
        beginScan();
        return;
      }
      onInteraction = ((web.Event _) {
        // Outro pedido aberto: espera a próxima interação.
        if (_prompting) return;
        unwaitInteraction();
        if (!controller.isClosed) beginScan();
      }).toJS;
      for (final type in _interactionEvents) {
        web.window.addEventListener(type, onInteraction, _capture);
      }
    }

    void stop() {
      unwaitInteraction();
      if (listener != null) {
        bluetooth?.removeEventListener(_advertisementEvent, listener);
      }
      try {
        scan?.stop();
      } catch (_) {}
    }

    controller = StreamController<OrbitSighting>(
      onListen: start,
      onCancel: stop,
    );
    return controller.stream;
  }

  @override
  Future<OrbitSighting?> scanOnce(List<RegisteredOrbit> orbits) async {
    if (orbits.isEmpty) throw OrbitException('Nenhum Orbit cadastrado');
    final bluetooth = _require();
    final _BluetoothDevice device;
    try {
      device = await bluetooth
          .requestDevice(
            {
                  'filters': [
                    for (final o in orbits) {'name': o.identifier},
                  ],
                }.jsify()
                as JSObject,
          )
          .toDart;
    } catch (error) {
      // O usuário fechou o seletor sem escolher.
      if (error.toString().contains('NotFoundError')) return null;
      throw OrbitException(_describe(error));
    }
    final orbit = matchOrbit(orbits, device.name);
    if (orbit == null) return null;
    return OrbitSighting(orbit: orbit, at: DateTime.now());
  }

  _Bluetooth _require() {
    final bluetooth = _bluetooth;
    if (bluetooth == null) {
      throw OrbitException(
        'Este navegador não tem Web Bluetooth. Use o Chrome em localhost ou HTTPS.',
      );
    }
    return bluetooth;
  }

  // Os erros do Web Bluetooth são DOMExceptions; o toString delas traz
  // "<nome>: <mensagem>", o que basta para exibir.
  static String _describe(Object error) => 'Bluetooth: $error';
}
