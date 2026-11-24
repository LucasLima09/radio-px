import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint, listEquals;

import '../models/orbit_encounter.dart';
import '../services/api/api_client.dart';
import '../services/api/api_exception.dart';
import '../services/orbit/orbit_decoder.dart';
import '../services/orbit/orbit_key_store.dart';
import '../services/orbit/orbit_queue.dart';
import '../services/orbit/orbit_scanner.dart';
import 'app_controller.dart';

/// Controller do encontro com os Orbits.
///
/// O app escuta todo anúncio BLE em volta e só repassa à central os que têm a
/// assinatura dos Orbits. Id, hora e localização vêm do próprio Orbit; nenhum
/// precisa de cadastro.
class OrbitController extends AppController {
  OrbitController({
    required this.api,
    required this.queue,
    OrbitScanner? scanner,
    OrbitKeyStore? keyStore,
  }) : scanner = scanner ?? createOrbitScanner(),
       _keyStore = keyStore ?? OrbitKeyStore(baseUrl: api.baseUrl);

  final ApiClient api;
  final OrbitScanner scanner;

  /// Encontros ainda não entregues, salvos no aparelho.
  final OrbitQueue queue;
  final OrbitKeyStore _keyStore;

  /// Abaixo disso o sinal é fraco demais para contar como "passou perto".
  static const rssiThreshold = -80;

  /// Intervalo mínimo entre dois envios do mesmo Orbit. Dois Orbits diferentes
  /// podem gerar envios no mesmo minuto.
  static const cooldown = Duration(seconds: 60);

  static const _maxHistory = 20;

  /// A escuta é religada depois de uma falha (Bluetooth desligado, por
  /// exemplo) nesse intervalo.
  static const retryDelay = Duration(seconds: 10);

  /// A chave e os nomes são rebaixados nesse intervalo.
  static const refreshInterval = Duration(minutes: 1);

  /// Com encontros na fila, tenta entregá-los nesse intervalo (a internet
  /// pode ter voltado).
  static const flushInterval = Duration(seconds: 30);

  /// Os anúncios chegam às dezenas por segundo; a tela não precisa disso tudo.
  static const _notifyEvery = Duration(seconds: 1);

  List<int>? _key;
  OrbitDecoder? _decoder;
  Map<String, String> _names = const {};
  StreamSubscription<OrbitAdvertisement>? _watch;
  Timer? _retry;
  Timer? _refresh;
  Timer? _flushTimer;
  Timer? _notifyTimer;
  List<OrbitEncounter> _pending = [];
  bool _flushing = false;
  bool _offline = false;
  final Map<String, OrbitSighting> _sightings = {};
  final Map<String, DateTime> _lastSentAt = {};
  bool _loading = false;
  bool _ready = false;
  int _heard = 0;
  String? _error;
  final List<OrbitEncounter> _encounters = [];

  bool get isSupported => scanner.isSupported;
  bool get canWatch => scanner.canWatch;

  /// Já tentou carregar a chave dos Orbits.
  bool get isReady => _ready;
  bool get isLoading => _loading;
  bool get isWatching => _watch != null;
  bool get isSending => _flushing;
  String? get error => _error;
  List<OrbitEncounter> get encounters => List.unmodifiable(_encounters);

  /// Anúncios BLE ouvidos, de qualquer aparelho.
  int get heardCount => _heard;

  /// Sinais com assinatura de Orbit válida.
  int get validCount => _decoder?.valid ?? 0;

  /// Sinais no formato dos Orbits com assinatura falsa ou fora da hora.
  int get rejectedCount => _decoder?.rejected ?? 0;

  /// Último sinal de cada Orbit ouvido nesta sessão, do mais recente ao mais
  /// antigo.
  List<OrbitSighting> get sightings =>
      _sightings.values.toList()..sort((a, b) => b.at.compareTo(a.at));

  /// Encontros guardados esperando internet.
  int get pendingCount => _pending.length;

  /// A última tentativa de entrega falhou por falta de conexão.
  bool get isOffline => _offline;

  String nameOf(OrbitSignal signal) =>
      _names[signal.identifier] ?? 'Orbit ${signal.identifier}';

  Future<void> start() async {
    // A fila é entregue mesmo onde não há Bluetooth: pode ter sobrado de antes.
    _pending = await queue.load();
    for (final e in _pending.reversed) {
      _record(e);
    }
    _flushTimer ??= Timer.periodic(flushInterval, (_) => flush());
    unawaited(flush());
    if (!isSupported) return;
    // Com a chave salva a escuta começa já, mesmo sem internet.
    final saved = await _keyStore.load();
    if (saved != null) _useKey(saved);
    await load();
    if (isDisposed) return;
    _refresh ??= Timer.periodic(refreshInterval, (_) => load(silent: true));
  }

  /// Baixa a chave pública e os nomes. Em modo [silent] (atualização
  /// periódica) uma falha mantém o que já havia sem mostrar erro.
  Future<void> load({bool silent = false}) async {
    if (_loading) return;
    _loading = true;
    if (!silent) _error = null;
    notify();
    try {
      final config = await api.orbitConfig();
      if (isDisposed) return;
      _names = config.names;
      if (config.publicKey.isEmpty) {
        if (_key == null) {
          _error = 'O servidor está sem a chave dos Orbits (ORBIT_PUBLIC_KEY).';
        }
      } else {
        await _keyStore.save(config.publicKey);
        _useKey(config.publicKey);
      }
    } catch (error) {
      // Com a chave salva a detecção funciona sem internet.
      if (!silent && _key == null) {
        _error = 'Falha ao carregar a chave dos Orbits: $error';
      }
    } finally {
      _loading = false;
      _ready = true;
      notify();
    }
  }

  void _useKey(List<int> key) {
    if (isDisposed) return;
    if (!listEquals(key, _key)) {
      _key = key;
      _decoder = OrbitDecoder(key);
      _sightings.clear();
    }
    _error = null;
    _startWatching();
  }

  void _startWatching() {
    if (_decoder == null || _watch != null || !canWatch || isDisposed) return;
    _retry?.cancel();
    _retry = null;
    _watch = scanner.watch().listen(
      _onAdvertisement,
      onError: (Object error) {
        debugPrint('[Orbit] detecção falhou: $error');
        _error = error.toString();
        _watch?.cancel();
        _watch = null;
        if (!isDisposed) {
          _retry = Timer(retryDelay, () {
            _error = null;
            _startWatching();
            notify();
          });
        }
        notify();
      },
    );
    notify();
  }

  Future<void> _onAdvertisement(OrbitAdvertisement ad) async {
    _heard++;
    _scheduleNotify();
    final sighting = await _decoder?.add(ad);
    if (sighting == null || isDisposed) return;

    final key = sighting.signal.identifier;
    _sightings[key] = sighting;
    final rssi = sighting.rssi;
    if (rssi != null && rssi < rssiThreshold) return;
    final last = _lastSentAt[key];
    if (last != null && sighting.at.difference(last) < cooldown) return;
    _lastSentAt[key] = sighting.at;
    await _report(sighting);
  }

  void _scheduleNotify() {
    _notifyTimer ??= Timer(_notifyEvery, () {
      _notifyTimer = null;
      notify();
    });
  }

  /// Guarda o encontro na fila do aparelho e tenta entregar. Sem internet, ele
  /// espera na fila.
  Future<void> _report(OrbitSighting sighting) async {
    final encounter = OrbitEncounter(
      id: newEncounterId(),
      signal: sighting.signal,
      at: sighting.at,
      rssi: sighting.rssi,
    );
    _pending.add(encounter);
    _record(encounter);
    await queue.save(_pending);
    notify();
    await flush();
  }

  /// Entrega a fila, do mais antigo ao mais novo. Para na primeira falha de
  /// conexão (tenta de novo em [flushInterval]); um encontro recusado de vez
  /// pelo servidor sai da fila.
  Future<void> flush() async {
    if (_flushing || _pending.isEmpty) return;
    _flushing = true;
    notify();
    try {
      while (_pending.isNotEmpty && !isDisposed) {
        final e = _pending.first;
        EncounterStatus result;
        String? failure;
        try {
          await api.reportOrbitEncounter(e);
          result = EncounterStatus.sent;
        } on ApiException catch (error) {
          if (!_isPermanent(error.statusCode)) {
            _offline = true;
            break;
          }
          result = EncounterStatus.failed;
          failure = error.message;
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

  @override
  void dispose() {
    _retry?.cancel();
    _refresh?.cancel();
    _flushTimer?.cancel();
    _notifyTimer?.cancel();
    _watch?.cancel();
    super.dispose();
  }
}
