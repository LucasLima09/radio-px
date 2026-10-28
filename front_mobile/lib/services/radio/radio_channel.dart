import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../../models/audio_clip.dart';
import '../../models/member.dart';
import '../../models/member_location.dart';
import '../../models/ws_message.dart';
import '../api/api_exception.dart';
import '../platform/ws_channel.dart';
import 'playback_cursor.dart';
import 'radio_event.dart';

enum RadioConnState { connecting, connected, disconnected }

/// Conexão WebSocket com o canal: transporte, reconexão e presença.
///
/// Não conhece gravação nem reprodução — apenas entrega os clipes completos
/// e avisa o resto do sistema sobre o que mudou.
class RadioChannel {
  RadioChannel({
    required this.baseUrl,
    required this.channelId,
    required this.tokenProvider,
    required this.cursor,
    required this.onEvent,
  });

  final String baseUrl;
  final String channelId;
  final Future<String> Function() tokenProvider;
  final PlaybackCursor cursor;
  final void Function(RadioEvent event) onEvent;

  static const Duration _reconnectBaseDelay = Duration(seconds: 1);
  static const Duration _reconnectMaxDelay = Duration(seconds: 30);
  static const double _reconnectJitter = 0.2;

  /// O aviso do ngrok no navegador é exibido uma vez por app, não por canal.
  static bool _webNgrokHintShown = false;

  WebSocketChannel? _ws;
  StreamSubscription? _sub;
  Timer? _reconnectTimer;
  int _reconnectAttempt = 0;
  bool _connecting = false;
  bool _disposed = false;
  Future<void> _pending = Future.value();

  RadioConnState _state = RadioConnState.disconnected;
  RadioConnState get state => _state;

  String? myUserId;
  final List<Member> members = [];
  final Map<String, MemberLocation> locations = {};

  // Montagem de áudios recebidos (clip_new + frames binários).
  AudioClip? _incomingMeta;
  final List<int> _incomingBytes = [];
  Timer? _incomingTimer;

  /// Abre a conexão com o canal. Chamadas concorrentes e reconexões
  /// pendentes são ignoradas; o que já está conectado não é reaberto.
  Future<void> connect() async {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    if (_disposed || _connecting || _state == RadioConnState.connected) return;
    _setState(RadioConnState.connecting);
    _emitChanged();
    _connecting = true;
    try {
      final token = await tokenProvider();
      if (_disposed) return;
      await cursor.load();
      if (_disposed) return;
      final wsBase = baseUrl.replaceFirst(RegExp(r'^http'), 'ws');
      final uri = Uri.parse('$wsBase/ws').replace(queryParameters: {
        'token': token,
        'channel_id': channelId,
        'last_heard_seq': '${cursor.lastHeardSeq}',
      });
      _ws = await openWsChannel(uri, {
        'ngrok-skip-browser-warning': '1',
      });
      await _ws!.ready.timeout(const Duration(seconds: 15));
      if (_disposed) {
        await _ws!.sink.close();
        return;
      }
      _sub = _ws!.stream.listen(
        _enqueue,
        onError: (_) => _onClosed(),
        onDone: _onClosed,
      );
    } on ApiException catch (e) {
      // Nenhuma nova tentativa resolve uma sessão encerrada: insistir só gasta
      // requisição a cada 30s. O usuário precisa entrar de novo.
      if (e.statusCode == 401) {
        _onAuthFailure(e);
      } else {
        await _onClosed();
      }
    } catch (_) {
      if (!_disposed) {
        onEvent(const RadioNotice(
            'Não foi possível conectar ao canal. Tentando novamente…'));
      }
      await _onClosed();
    } finally {
      _connecting = false;
    }
    _emitChanged();
  }

  /// Encerra a sessão sem agendar reconexão, usado quando o token é recusado
  /// porque a sessão acabou.
  void _onAuthFailure(ApiException e) {
    if (_disposed) return;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _setState(RadioConnState.disconnected);
    myUserId = null;
    members.clear();
    locations.clear();
    onEvent(RadioSessionEnded(e.message));
    _emitChanged();
  }

  /// Agenda uma nova tentativa de conexão com espera exponencial e jitter, para
  /// que vários aparelhos não voltem juntos depois de o servidor cair.
  void _scheduleReconnect() {
    if (_disposed) return;
    _reconnectTimer?.cancel();
    final delay = _reconnectDelay(_reconnectAttempt);
    _reconnectAttempt++;
    // `connecting` durante a espera evita oferecer um "Reconectar" para algo
    // que já está reconectando sozinho.
    _setState(RadioConnState.connecting);
    _reconnectTimer = Timer(delay, () {
      _reconnectTimer = null;
      if (_disposed) return;
      connect();
    });
    _emitChanged();
  }

  Duration _reconnectDelay(int attempt) {
    final scaled = _reconnectBaseDelay.inMilliseconds * pow(2, attempt);
    final capped = min(scaled.toDouble(), _reconnectMaxDelay.inMilliseconds.toDouble());
    final jitter = capped * _reconnectJitter * (Random().nextDouble() * 2 - 1);
    return Duration(milliseconds: (capped + jitter).round());
  }

  void _enqueue(dynamic data) {
    _pending = _pending
        .then((_) => _onMessage(data))
        .catchError((Object _) {});
  }

  Future<void> _onMessage(dynamic data) async {
    if (_disposed) return;
    if (data is String) {
      await _onTextMessage(data);
    } else if (data is List<int>) {
      await _onClipPayload(Uint8List.fromList(data));
    }
  }

  Future<void> _onTextMessage(String text) async {
    final Map<String, dynamic> map;
    try {
      map = jsonDecode(text) as Map<String, dynamic>;
    } catch (_) {
      return;
    }

    final msg = WsMessage.fromJson(map);
    switch (msg.type) {
      case 'joined':
        _setState(RadioConnState.connected);
        _reconnectAttempt = 0;
        myUserId = msg.userId;
        members
          ..clear()
          ..addAll(msg.members ?? const []);
        locations
          ..clear()
          ..addAll({
            for (final loc in msg.locations ?? const <MemberLocation>[])
              loc.userId: loc,
          });
        _cancelIncoming();
        _emitChanged();

      case 'peer_joined':
        if (msg.userId != null) {
          members.removeWhere((m) => m.userId == msg.userId);
          members.add(
              Member(userId: msg.userId!, username: msg.username ?? 'Radialista'));
        }
        _emitChanged();

      case 'peer_left':
        members.removeWhere((m) => m.userId == msg.userId);
        locations.remove(msg.userId);
        if (msg.userId == myUserId) {
          onEvent(const RadioLocalRecordingStopped());
        }
        _emitChanged();

      case 'location_update':
        if (msg.userId != null && msg.lat != null && msg.lng != null) {
          locations[msg.userId!] = MemberLocation(
            userId: msg.userId!,
            username: msg.username ?? '',
            lat: msg.lat!,
            lng: msg.lng!,
          );
          _emitChanged();
        }

      case 'recording_start':
        _setMemberRecording(msg.userId, true);
        _emitChanged();

      case 'recording_stop':
        _setMemberRecording(msg.userId, false);
        if (msg.userId == myUserId) {
          onEvent(const RadioLocalRecordingStopped());
        }
        _emitChanged();

      case 'clip_new':
        _beginIncomingClip(msg.clip);
        _emitChanged();

      case 'error':
        onEvent(RadioNotice(msg.errorMessage ?? 'Erro do servidor'));
        _emitChanged();

      default:
        break;
    }
  }

  // ---------------- Recepção de clips ----------------

  void _beginIncomingClip(AudioClip? clip) {
    if (clip == null || clip.size <= 0) return;
    // Um clip novo chegou antes do anterior terminar: descarta o anterior.
    _cancelIncoming();
    _incomingMeta = clip;
    _incomingTimer = Timer(const Duration(seconds: 30), _cancelIncoming);
  }

  Future<void> _onClipPayload(Uint8List data) async {
    final meta = _incomingMeta;
    if (meta == null) return;
    _incomingBytes.addAll(data);
    if (_incomingBytes.length >= meta.size) {
      final complete = _incomingBytes.length == meta.size
          ? Uint8List.fromList(_incomingBytes)
          : Uint8List.fromList(_incomingBytes.sublist(0, meta.size));
      _cancelIncoming();
      onEvent(RadioClipReceived(meta, complete));
    }
  }

  void _cancelIncoming() {
    _incomingTimer?.cancel();
    _incomingTimer = null;
    _incomingMeta = null;
    _incomingBytes.clear();
  }

  // ---------------- Envio ----------------

  void send(Map<String, dynamic> message) {
    try {
      _ws?.sink.add(jsonEncode(message));
    } catch (_) {}
  }

  void sendBytes(Uint8List bytes) {
    try {
      _ws?.sink.add(bytes);
    } catch (_) {}
  }

  void sendLocation(double lat, double lng) {
    if (_state != RadioConnState.connected) return;
    send({'type': 'location', 'lat': lat, 'lng': lng});
  }

  // ---------------- Ciclo de vida ----------------

  Future<void> _onClosed() async {
    // onError e onDone disparam em sequência; sem esta guarda a queda geraria
    // duas reconexões. A primeira falha ainda passa, porque connect() já marcou
    // o estado como connecting.
    if (_disposed || _state == RadioConnState.disconnected) return;
    _setState(RadioConnState.disconnected);
    if (kIsWeb && baseUrl.contains('ngrok') && !_webNgrokHintShown) {
      _webNgrokHintShown = true;
      onEvent(const RadioNotice(
          'O plano free do ngrok bloqueia o WebSocket no navegador. '
          'Use o APK no celular (distância) ou o endereço local (testes).'));
    }
    myUserId = null;
    members.clear();
    locations.clear();
    // Os áudios que ainda não tocaram são descartados aqui de propósito: o
    // cursor faz o servidor reenviá-los, que é a única fonte da verdade.
    _cancelIncoming();
    _emitChanged();
    _scheduleReconnect();
  }

  void _setMemberRecording(String? userId, bool value) {
    if (userId == null) return;
    for (final m in members) {
      if (m.userId == userId) m.recording = value;
    }
  }

  void _setState(RadioConnState value) => _state = value;

  void _emitChanged() => onEvent(const RadioChanged());

  Future<void> dispose() async {
    _disposed = true;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    try {
      // Avisa o servidor que saímos para ele remover a presença na hora, sem
      // esperar o fechamento do socket — assim a contagem de online cai assim
      // que a tela do canal é fechada.
      if (_state == RadioConnState.connected) {
        send({'type': 'leave'});
      }
      await _ws?.sink.close();
    } catch (_) {}
    await _sub?.cancel();
    _cancelIncoming();
  }
}
