import 'dart:async';

import 'app_controller.dart';
import '../models/audio_clip.dart';
import '../models/channel.dart';
import '../models/member.dart';
import '../models/public_user.dart';
import '../models/record_mode.dart';
import '../services/api/api_client.dart';
import '../services/radio/clip_recorder.dart';
import '../services/radio/playback_cursor.dart';
import '../services/radio/playback_queue.dart';
import '../services/radio/radio_channel.dart';
import '../services/radio/radio_event.dart';
import '../services/storage/app_config.dart';

/// Controller da sala: coordena o canal, a gravação e a reprodução.
///
/// É o único lugar que conhece os três serviços ao mesmo tempo. Os serviços
/// não se conhecem entre si: o canal não sabe da gravação, a gravação não
/// sabe do player.
class RoomController extends AppController {
  RoomController({
    required this.api,
    required this.channel,
    required this.user,
    required this.config,
  }) {
    _cursor = PlaybackCursor(channelId: channel.id, config: config);
    _radio = RadioChannel(
      baseUrl: api.baseUrl,
      channelId: channel.id,
      tokenProvider: api.ensureAccessToken,
      cursor: _cursor,
      onEvent: _onRadioEvent,
    );
    _recorder = ClipRecorder(
      send: _radio.send,
      sendBytes: _radio.sendBytes,
      isConnected: () => _radio.state == RadioConnState.connected,
      onNotice: _showNotice,
      onChanged: notify,
    );
    _queue = PlaybackQueue(cursor: _cursor, onChanged: notify);
  }

  final ApiClient api;
  final Channel channel;
  final PublicUser user;
  final AppConfig config;

  late final PlaybackCursor _cursor;
  late final RadioChannel _radio;
  late final ClipRecorder _recorder;
  late final PlaybackQueue _queue;

  RecordMode _recordMode = RecordMode.hold;
  bool _pttPressed = false;
  bool _startingRecording = false;
  bool _joining = false;
  bool _wasConnected = false;
  String? _connectionError;
  String? _notice;
  int _noticeId = 0;

  // ---------------- Estado para a View ----------------

  RadioConnState get state => _radio.state;
  List<Member> get members => List.unmodifiable(_radio.members);
  String? get myUserId => _radio.myUserId;
  bool get isRecording => _recorder.isRecording;
  bool get audioPlaying => _queue.isPlaying && !_queue.isMuted;
  int get pendingCount => _queue.pendingCount;
  AudioClip? get currentPlayback => _queue.currentPlayback;
  RecordMode get recordMode => _recordMode;
  bool get isPttPressed => _pttPressed;
  bool get isJoining => _joining;
  String? get connectionError => _connectionError;

  /// Último aviso mostrado ao usuário. [noticeId] muda a cada aviso, para a
  /// View saber que precisa mostrar o SnackBar de novo.
  String? get notice => _notice;
  int get noticeId => _noticeId;

  /// Prepara a sala: modo de gravação e conexão.
  Future<void> init() async {
    _recordMode = await config.loadRecordMode();
    notify();
    await connect();
  }

  /// Entra no canal e abre o WebSocket.
  Future<void> connect() async {
    if (_joining) return;
    _joining = true;
    _connectionError = null;
    notify();
    try {
      await api.joinChannel(channel.id);
      if (isDisposed) return;
      await _radio.connect();
    } catch (error) {
      _connectionError = error.toString();
    } finally {
      _joining = false;
      notify();
    }
  }

  /// Alterna entre segurar para falar e tocar para falar.
  Future<void> toggleRecordMode() async {
    final next =
        _recordMode == RecordMode.hold ? RecordMode.tap : RecordMode.hold;
    _recordMode = next;
    notify();
    await config.saveRecordMode(next);
  }

  void toggleMap() {
    notify();
  }

  /// Botão de falar.
  ///
  /// No modo toque, liga e desliga a gravação. No modo segurar, só liga — o
  /// envio acontece em [releaseRecord].
  Future<void> pressRecord() async {
    if (_radio.state != RadioConnState.connected) {
      _showNotice('Ainda não conectado ao canal');
      return;
    }
    if (_recordMode == RecordMode.tap) {
      if (_recorder.isRecording) {
        await _stopRecording();
      } else {
        await _startRecording();
      }
      return;
    }
    if (_recorder.isRecording || _startingRecording) return;
    _startingRecording = true;
    _pttPressed = true;
    notify();
    final ok = await _startRecording();
    _startingRecording = false;
    if (!ok) {
      _pttPressed = false;
    } else if (!_pttPressed) {
      // O dedo já saiu antes de a gravação começar: envia o que gravou.
      await _stopRecording();
    }
    notify();
  }

  /// Botão de falar solto.
  Future<void> releaseRecord() async {
    if (_recordMode == RecordMode.tap) return;
    if (!_pttPressed) return;
    _pttPressed = false;
    notify();
    await _stopRecording();
  }

  Future<bool> _startRecording() async {
    final ok = await _recorder.start();
    if (ok) {
      // Durante a gravação a escuta para: o que chega fica na fila.
      _queue.mute();
      _queue.pauseIfPlaying();
    }
    notify();
    return ok;
  }

  Future<void> _stopRecording() async {
    if (!_recorder.isRecording) return;
    _queue.unmute();
    notify();
    await _recorder.stopAndSend();
    if (_queue.hasCurrent && _queue.isPlaying) {
      _queue.resume();
    } else {
      _queue.playNext();
    }
    notify();
  }

  // ---------------- Eventos do canal ----------------

  void _onRadioEvent(RadioEvent event) {
    switch (event) {
      case RadioClipReceived(:final meta, :final bytes):
        _queue.enqueue(meta, bytes);
      case RadioNotice(:final message):
        _showNotice(message);
      case RadioSessionEnded(:final message):
        unawaited(_handleSessionEnded(message));
      case RadioLocalRecordingStopped():
        unawaited(_recorder.markStoppedByServer());
      case RadioChanged():
        _handleRadioChanged();
    }
    notify();
  }

  /// O servidor recusou a sessão: o áudio pendente é descartado e o usuário
  /// precisa entrar de novo.
  Future<void> _handleSessionEnded(String message) async {
    await _recorder.abort();
    await _queue.clear();
    _showNotice(message);
  }

  void _handleRadioChanged() {
    final connected = _radio.state == RadioConnState.connected;
    if (connected && !_wasConnected) {
      _connectionError = null;
    }
    _wasConnected = connected;
  }

  void _showNotice(String message) {
    _notice = message;
    _noticeId++;
    notify();
  }

  @override
  void dispose() {
    unawaited(_cleanup());
    super.dispose();
  }

  Future<void> _cleanup() async {
    await _radio.dispose();
    await _recorder.dispose();
    await _queue.dispose();
  }
}
