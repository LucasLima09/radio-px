import 'dart:async';

import 'package:flutter/foundation.dart'
    show TargetPlatform, debugPrint, defaultTargetPlatform, kIsWeb;
import 'package:geolocator/geolocator.dart';

import '../models/orbit_encounter.dart';
import '../services/api/api_client.dart';
import '../services/api/api_exception.dart';
import '../services/orbit/orbit_queue.dart';
import '../services/orbit/orbit_scanner.dart';
import 'app_controller.dart';

/// Lê a posição atual do aparelho como (lat, lng).
typedef PositionReader = Future<(double, double)> Function();

/// Controller do encontro com os Orbits.
///
/// Os Orbits são cadastrados uma vez no painel admin; o app baixa a lista e
/// reconhece qualquer um deles pelo nome que anuncia no Bluetooth. A
/// localização só vai para a central quando há um encontro.
class OrbitController extends AppController {
  OrbitController({
    required this.api,
    required this.queue,
    OrbitScanner? scanner,
    PositionReader? readPosition,
  }) : scanner = scanner ?? createOrbitScanner(),
       _readPosition = readPosition ?? _currentPosition;

  final ApiClient api;
  final OrbitScanner scanner;

  /// Encontros ainda não entregues, salvos no aparelho.
  final OrbitQueue queue;
  final PositionReader _readPosition;

  /// Abaixo disso o sinal é fraco demais para contar como "passou perto".
  static const rssiThreshold = -80;

  /// Cada Orbit anuncia várias vezes por segundo; sem esse intervalo, cada
  /// anúncio viraria um envio. Vale por Orbit: dois Orbits diferentes podem
  /// gerar envios no mesmo minuto.
  static const cooldown = Duration(seconds: 60);

  static const _maxHistory = 20;

  /// Quando a detecção é automática, ela é religada depois de uma falha
  /// (Bluetooth desligado, por exemplo) nesse intervalo.
  static const retryDelay = Duration(seconds: 10);

  /// A lista de Orbits é rebaixada nesse intervalo, para um Orbit cadastrado
  /// no painel passar a valer sem reiniciar o app.
  static const refreshInterval = Duration(minutes: 1);

  /// Com encontros na fila, tenta entregá-los nesse intervalo (a internet
  /// pode ter voltado).
  static const flushInterval = Duration(seconds: 30);

  List<RegisteredOrbit>? _orbits;
  StreamSubscription<OrbitSighting>? _watch;
  Timer? _retry;
  Timer? _refresh;
  Timer? _flushTimer;
  List<OrbitEncounter> _pending = [];
  bool _flushing = false;
  bool _offline = false;
  final Map<String, OrbitSighting> _lastSighting = {};
  final Map<String, DateTime> _lastSentAt = {};
  final Set<String> _sending = {};
  bool _loading = false;
  bool _scanning = false;
  String? _error;
  final List<OrbitEncounter> _encounters = [];

  bool get isSupported => scanner.isSupported;
  bool get canWatch => scanner.canWatch;

  /// A detecção liga sozinha e fica sempre ligada (sem botão).
  bool get isAlwaysOn => canWatch && !scanner.needsUserGesture;

  /// Orbits cadastrados; `null` enquanto carrega.
  List<RegisteredOrbit>? get orbits => _orbits;
  bool get isLoading => _loading;
  bool get isWatching => _watch != null;
  bool get isScanning => _scanning;
  bool get isSending => _sending.isNotEmpty;
  String? get error => _error;
  List<OrbitEncounter> get encounters => List.unmodifiable(_encounters);

  /// Encontros guardados esperando internet.
  int get pendingCount => _pending.length;

  /// A última tentativa de entrega falhou por falta de conexão.
  bool get isOffline => _offline;
  OrbitSighting? lastSightingOf(RegisteredOrbit orbit) =>
      _lastSighting[orbit.identifier];

  /// Baixa a lista de Orbits cadastrados e, onde dá, liga a detecção.
  Future<void> start() async {
    // A fila é entregue mesmo onde não há Bluetooth: pode ter sobrado de antes.
    _pending = await queue.load();
    for (final e in _pending.reversed) {
      _record(e);
    }
    _flushTimer ??= Timer.periodic(flushInterval, (_) => flush());
    unawaited(flush());
    if (!isSupported) return;
    await load();
    _refresh ??= Timer.periodic(refreshInterval, (_) => load(silent: true));
  }

  /// Recarrega a lista. Em modo [silent] (atualização periódica) uma falha
  /// mantém a lista atual sem mostrar erro.
  Future<void> load({bool silent = false}) async {
    if (_loading) return;
    _loading = true;
    if (!silent) _error = null;
    notify();
    try {
      final orbits = await api.listOrbits();
      final changed = !_sameOrbits(_orbits, orbits);
      _orbits = orbits;
      // A escuta filtra pela lista antiga; reinicia para pegar a nova.
      if (changed && _watch != null) {
        _cancelWatch();
        startWatching();
      }
      if (isAlwaysOn && _watch == null) startWatching();
    } catch (error) {
      _orbits ??= const [];
      if (!silent) _error = 'Falha ao carregar os Orbits: $error';
    } finally {
      _loading = false;
      notify();
    }
  }

  static bool _sameOrbits(List<RegisteredOrbit>? a, List<RegisteredOrbit> b) {
    if (a == null || a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].identifier != b[i].identifier) return false;
    }
    return true;
  }

  /// Começa a escutar os Orbits cadastrados. Precisa vir de um clique.
  void startWatching() {
    final orbits = _orbits;
    if (orbits == null || orbits.isEmpty || _watch != null || !canWatch) {
      return;
    }
    _retry?.cancel();
    _retry = null;
    _error = null;
    _watch = scanner
        .watch(orbits)
        .listen(
          _onSighting,
          onError: (Object error) {
            debugPrint('[Orbit] detecção falhou: $error');
            _error = error.toString();
            _cancelWatch();
            if (isAlwaysOn && !isDisposed) {
              _retry = Timer(retryDelay, startWatching);
            }
            notify();
          },
        );
    notify();
  }

  void stopWatching() {
    _cancelWatch();
    notify();
  }

  void _cancelWatch() {
    _watch?.cancel();
    _watch = null;
  }

  /// Modo manual: o seletor do navegador mostra só os Orbits cadastrados por
  /// perto; escolher um conta como encontro.
  Future<void> scanOnce() async {
    final orbits = _orbits;
    if (_scanning || orbits == null || orbits.isEmpty) return;
    _scanning = true;
    _error = null;
    notify();
    try {
      final sighting = await scanner.scanOnce(orbits);
      if (sighting != null) {
        _lastSighting[sighting.orbit.identifier] = sighting;
        await _report(sighting);
      }
    } on OrbitException catch (error) {
      _error = error.message;
    } finally {
      _scanning = false;
      notify();
    }
  }

  void _onSighting(OrbitSighting sighting) {
    final key = sighting.orbit.identifier;
    _lastSighting[key] = sighting;
    notify();
    final rssi = sighting.rssi;
    if (rssi != null && rssi < rssiThreshold) return;
    final last = _lastSentAt[key];
    if (last != null && sighting.at.difference(last) < cooldown) return;
    _report(sighting);
  }

  /// Registra o encontro: lê a posição, guarda na fila do aparelho e tenta
  /// entregar. Sem internet, ele espera na fila com a hora do encontro.
  Future<void> _report(OrbitSighting sighting) async {
    final orbit = sighting.orbit;
    final key = orbit.identifier;
    if (!_sending.add(key)) return;
    // Marca antes de terminar para que os anúncios que chegam durante a
    // leitura da posição não disparem outro.
    _lastSentAt[key] = sighting.at;
    notify();
    try {
      final (lat, lng) = await _readPosition();
      final encounter = OrbitEncounter(
        id: newEncounterId(),
        orbit: orbit,
        at: sighting.at,
        rssi: sighting.rssi,
        lat: lat,
        lng: lng,
      );
      _pending.add(encounter);
      await queue.save(_pending);
      _record(encounter);
    } catch (error) {
      // Sem posição não há o que guardar; libera o próximo anúncio.
      _lastSentAt.remove(key);
      _record(
        OrbitEncounter(
          id: newEncounterId(),
          orbit: orbit,
          at: sighting.at,
          rssi: sighting.rssi,
          status: EncounterStatus.failed,
          error: 'Sem localização: $error',
        ),
      );
    } finally {
      _sending.remove(key);
      notify();
    }
    await flush();
  }

  /// Entrega a fila, do mais antigo ao mais novo. Para na primeira falha de
  /// conexão (tenta de novo em [flushInterval]); um encontro recusado de vez
  /// pelo servidor sai da fila.
  Future<void> flush() async {
    if (_flushing || _pending.isEmpty) return;
    _flushing = true;
    try {
      while (_pending.isNotEmpty && !isDisposed) {
        final e = _pending.first;
        EncounterStatus result;
        String? failure;
        try {
          await api.reportOrbitEncounter(
            id: e.id,
            at: e.at,
            lat: e.lat!,
            lng: e.lng!,
            identifier: e.orbit.identifier,
            rssi: e.rssi,
          );
          result = EncounterStatus.sent;
        } on ApiException catch (error) {
          if (!_isPermanent(error.statusCode)) {
            _offline = true;
            break;
          }
          result = EncounterStatus.failed;
          failure = error.statusCode == 422
              ? 'Orbit não cadastrado ou desativado no painel'
              : error.message;
        } catch (_) {
          // Sem internet (ou servidor fora do ar): fica na fila.
          _offline = true;
          break;
        }
        _offline = false;
        _pending.removeAt(0);
        await queue.save(_pending);
        _record(e.withStatus(result, error: failure));
        notify();
      }
    } finally {
      _flushing = false;
      notify();
    }
  }

  /// Recusas que não mudam tentando de novo. 401 (sessão), 408 e 429 ficam
  /// na fila.
  static bool _isPermanent(int status) =>
      status >= 400 &&
      status < 500 &&
      status != 401 &&
      status != 403 &&
      status != 408 &&
      status != 429;

  /// Mostra o encontro em "Envios recentes", substituindo a versão anterior
  /// do mesmo encontro (ex.: de "na fila" para "enviado").
  void _record(OrbitEncounter encounter) {
    final i = _encounters.indexWhere((e) => e.id == encounter.id);
    if (i >= 0) {
      _encounters[i] = encounter;
      return;
    }
    _encounters.insert(0, encounter);
    if (_encounters.length > _maxHistory) _encounters.removeLast();
  }

  static const _simLat = String.fromEnvironment(
    'SIM_LAT',
    defaultValue: '-28.4507437',
  );
  static const _simLng = String.fromEnvironment(
    'SIM_LNG',
    defaultValue: '-52.199568',
  );

  static Future<(double, double)> _currentPosition() async {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.linux) {
      return (double.parse(_simLat), double.parse(_simLng));
    }
    return _devicePosition(timeLimit: const Duration(seconds: 20));
  }

  static Future<(double, double)> _devicePosition({
    required Duration timeLimit,
  }) async {
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      throw Exception('Permissão de localização negada');
    }
    final position = await Geolocator.getCurrentPosition(
      locationSettings: LocationSettings(
        accuracy: LocationAccuracy.high,
        timeLimit: timeLimit,
      ),
    );
    return (position.latitude, position.longitude);
  }

  @override
  void dispose() {
    _retry?.cancel();
    _refresh?.cancel();
    _flushTimer?.cancel();
    _cancelWatch();
    super.dispose();
  }
}
