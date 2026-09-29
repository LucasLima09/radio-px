import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:record/record.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'audio_bridge.dart';
import 'models.dart';
import 'ws_channel.dart';

enum RadioConnState { connecting, connected, disconnected }

/// Um áudio aguardando reprodução local (bytes já recebidos).
class QueuedAudio {
  final AudioClip meta;
  final PlaybackSource source;

  QueuedAudio(this.meta, this.source);
}

class RadioClient {
  RadioClient({
    required this.baseUrl,
    required this.channelId,
    required this.tokenProvider,
  });

  final String baseUrl;
  final String channelId;
  final Future<String> Function() tokenProvider;

  static const int _uploadChunk = 64 << 10;
  static const int _maxClipSeconds = 60;

  WebSocketChannel? _ws;
  StreamSubscription? _sub;
  StreamSubscription<PlayerState>? _playerSub;

  final AudioRecorder _recorder = AudioRecorder();
  final AudioPlayer _player = AudioPlayer();

  String? myUserId;

  RadioConnState _state = RadioConnState.disconnected;
  RadioConnState get state => _state;

  final List<Member> members = [];
  final Map<String, MemberLocation> locations = {};

  bool recording = false;
  bool get mutedWhileRecording => _muted;

  VoidCallback? onChanged;
  void Function(String message)? onNotice;

  // Estado de reprodução da fila local.
  bool _playing = false;
  bool _muted = false;
  final List<QueuedAudio> _queue = [];
  QueuedAudio? _current;
  int get pendingPlaybackCount => _queue.isEmpty ? (_playing ? 1 : 0) : _queue.length + (_playing ? 1 : 0);
  bool get audioPlaying => _playing;

  // Gravação em andamento.
  String? _recordingPath;
  String _recordingMime = 'audio/mp4';
  Timer? _recordingTimer;
  Stopwatch? _recordingClock;

  // Montagem de áudios recebidos (clip_new + frames binários).
  AudioClip? _incomingMeta;
  final List<int> _incomingBytes = [];
  Timer? _incomingTimer;

  bool _disposed = false;
  Future<void> _pending = Future.value();

  Future<void> connect() async {
    _disposed = false;
    _setState(RadioConnState.connecting);
    _playerSub ??= _player.playerStateStream.listen((ps) {
      if (ps.processingState == ProcessingState.completed && _playing) {
        _onPlaybackCompleted();
      }
    });
    try {
      final token = await tokenProvider();
      final wsBase = baseUrl.replaceFirst(RegExp(r'^http'), 'ws');
      final uri = Uri.parse('$wsBase/ws').replace(queryParameters: {
        'token': token,
        'channel_id': channelId,
      });
      _ws = await openWsChannel(uri, {
        'ngrok-skip-browser-warning': '1',
      });
      _sub = _ws!.stream.listen(
        _enqueue,
        onError: (_) => _onClosed(),
        onDone: _onClosed,
      );
    } catch (_) {
      _onClosed();
    }
    _notify();
  }

  Future<void> reconnect() async {
    await _sub?.cancel();
    _sub = null;
    _ws = null;
    await connect();
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
        _notify();

      case 'peer_joined':
        if (msg.userId != null) {
          members.removeWhere((m) => m.userId == msg.userId);
          members.add(
              Member(userId: msg.userId!, username: msg.username ?? 'Radialista'));
        }
        _notify();

      case 'peer_left':
        members.removeWhere((m) => m.userId == msg.userId);
        locations.remove(msg.userId);
        if (recording && msg.userId == myUserId) recording = false;
        _notify();

      case 'location_update':
        if (msg.userId != null && msg.lat != null && msg.lng != null) {
          locations[msg.userId!] = MemberLocation(
            userId: msg.userId!,
            username: msg.username ?? '',
            lat: msg.lat!,
            lng: msg.lng!,
          );
          _notify();
        }

      case 'recording_start':
        _setMemberRecording(msg.userId, true);
        _notify();

      case 'recording_stop':
        _setMemberRecording(msg.userId, false);
        if (msg.userId == myUserId) recording = false;
        _notify();

      case 'clip_new':
        _beginIncomingClip(msg.clip);
        _notify();

      case 'error':
        onNotice?.call(msg.errorMessage ?? 'Erro do servidor');
        _notify();

      default:
        break;
    }
  }

  // ---------------- Gravação ----------------

  Future<bool> startRecording() async {
    if (recording) return true;
    if (_state != RadioConnState.connected) {
      onNotice?.call('Ainda não conectado ao canal');
      return false;
    }
    try {
      if (!await _recorder.hasPermission()) {
        onNotice?.call('Permissão de microfone negada');
        return false;
      }
      final path = audioBridge.newRecordingPath();
      // No navegador o record_web não usa MediaRecorder para WAV (e AAC/mp4
      // depende de suporte do Chrome); WAV via AudioWorklet é universal.
      final isWeb = kIsWeb;
      await _recorder.start(
        RecordConfig(
          encoder: isWeb ? AudioEncoder.wav : AudioEncoder.aacLc,
          bitRate: 32000,
          sampleRate: 16000,
          numChannels: 1,
        ),
        path: path,
      );
      _recordingMime = isWeb ? 'audio/wav' : 'audio/mp4';
      _recordingPath = path;
      _recordingClock = Stopwatch()..start();
      _recordingTimer = Timer(Duration(seconds: _maxClipSeconds), () {
        if (recording) stopRecordingAndSend();
      });
      recording = true;
      _muted = true;
      if (_playing) await _player.pause();
      _send({'type': 'recording_start'});
      _notify();
      return true;
    } catch (e) {
      debugPrint('[RadioClient] erro ao iniciar gravação: $e');
      onNotice?.call('Não foi possível acessar o microfone: $e');
      _notify();
      return false;
    }
  }

  Future<void> stopRecordingAndSend() async {
    if (!recording) return;
    recording = false;
    _muted = false;
    _recordingTimer?.cancel();
    _recordingTimer = null;

    final path = _recordingPath;
    final ms = _recordingClock?.elapsedMilliseconds ?? 0;
    _recordingPath = null;
    _recordingClock = null;
    _send({'type': 'recording_stop'});

    try {
      final stoppedPath = await _recorder.stop();
      if (_state == RadioConnState.connected) {
        await _uploadRecording(stoppedPath ?? path, ms);
      }
    } catch (e) {
      debugPrint('[RadioClient] falha ao encerrar gravação: $e');
    }

    if (_current != null && _playing) {
      await _player.play().catchError((_) {});
    } else {
      _playNext();
    }
    _notify();
  }

  Future<void> _uploadRecording(String? path, int durationMs) async {
    if (path == null) return;
    try {
      final bytes = await audioBridge.readCaptured(path);
      if (bytes.isEmpty) return;

      final id = _genId();
      _send({
        'type': 'clip_start',
        'clipId': id,
        'mime': _recordingMime,
        'durationMs': durationMs,
        'size': bytes.length,
      });
      for (var i = 0; i < bytes.length; i += _uploadChunk) {
        final end = min(i + _uploadChunk, bytes.length);
        _sendBytes(Uint8List.sublistView(bytes, i, end));
      }
      _send({'type': 'clip_end', 'clipId': id});
    } catch (e) {
      debugPrint('[RadioClient] falha ao enviar áudio: $e');
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
      await _enqueuePlayback(meta, complete);
    }
  }

  void _cancelIncoming() {
    _incomingTimer?.cancel();
    _incomingTimer = null;
    _incomingMeta = null;
    _incomingBytes.clear();
  }

  Future<void> _enqueuePlayback(AudioClip meta, Uint8List bytes) async {
    try {
      final source = audioBridge.makePlaybackSource(
        bytes,
        mimeType: meta.mime,
        clipId: meta.clipId,
      );
      _queue.add(QueuedAudio(meta, source));
      _notify();
      _playNext();
    } catch (e) {
      debugPrint('[RadioClient] falha ao preparar áudio recebido: $e');
    }
  }

  void _playNext() {
    if (_muted || _playing || _queue.isEmpty) return;
    final next = _queue.removeAt(0);
    _current = next;
    _playing = true;
    _notify();
    _player
        .setAudioSource(next.source.audioSource)
        .then((_) => _player.play())
        .catchError((Object e) {
      debugPrint('[RadioClient] falha ao reproduzir: $e');
      _onPlaybackCompleted();
    });
  }

  void _onPlaybackCompleted() {
    if (!_playing) return;
    final done = _current;
    _current = null;
    _playing = false;
    if (done != null) {
      done.source.dispose();
    }
    _notify();
    _playNext();
  }

  // ---------------- Limpeza ----------------

  Future<void> _clearPlayback() async {
    _cancelIncoming();
    try {
      await _player.stop();
    } catch (_) {}
    _playing = false;
    for (final q in _queue) {
      q.source.dispose();
    }
    _queue.clear();
    final cur = _current;
    _current = null;
    if (cur != null) {
      cur.source.dispose();
    }
  }

  Future<void> _stopRecording() async {
    _recordingTimer?.cancel();
    _recordingTimer = null;
    recording = false;
    _muted = false;
    _recordingPath = null;
    _recordingClock = null;
    try {
      await _recorder.stop();
    } catch (_) {}
  }

  Future<void> _onClosed() async {
    if (_disposed) return;
    _setState(RadioConnState.disconnected);
    if (kIsWeb &&
        baseUrl.contains('ngrok') &&
        !_webNgrokHintShown) {
      _webNgrokHintShown = true;
      onNotice?.call(
          'O plano free do ngrok bloqueia o WebSocket no navegador. '
          'Use o APK no celular (distância) ou o endereço local (testes).');
    }
    myUserId = null;
    members.clear();
    locations.clear();
    await _stopRecording();
    await _clearPlayback();
    _notify();
  }

  // ---------------- Envio ----------------

  void sendLocation(double lat, double lng) {
    if (_state != RadioConnState.connected) return;
    _send({'type': 'location', 'lat': lat, 'lng': lng});
  }

  void _send(Map<String, dynamic> message) {
    try {
      _ws?.sink.add(jsonEncode(message));
    } catch (_) {}
  }

  void _sendBytes(Uint8List bytes) {
    try {
      _ws?.sink.add(bytes);
    } catch (_) {}
  }

  void _setMemberRecording(String? userId, bool value) {
    if (userId == null) return;
    for (final m in members) {
      if (m.userId == userId) m.recording = value;
    }
  }

  void _setState(RadioConnState value) => _state = value;

  void _notify() => onChanged?.call();

  static String _genId() {
    final rnd = Random.secure();
    final sb = StringBuffer();
    for (var i = 0; i < 32; i++) {
      sb.write(rnd.nextInt(16).toRadixString(16));
    }
    return sb.toString();
  }

  Future<void> dispose() async {
    _disposed = true;
    try {
      _ws?.sink.close();
    } catch (_) {}
    await _sub?.cancel();
    await _playerSub?.cancel();
    await _stopRecording();
    await _player.dispose();
    await _recorder.dispose();
  }
}

bool _webNgrokHintShown = false;