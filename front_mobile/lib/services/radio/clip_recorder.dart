import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:record/record.dart';

import '../platform/audio_bridge.dart';

/// Grava a fala do usuário e envia para o canal.
///
/// Não conhece o socket: recebe callbacks para enviar as mensagens e para
/// avisar o usuário, o que mantém a classe testável e o acoplamento baixo.
class ClipRecorder {
  ClipRecorder({
    required this.send,
    required this.sendBytes,
    required this.isConnected,
    required this.onNotice,
    required this.onChanged,
  });

  /// Envia uma mensagem de texto para o servidor.
  final void Function(Map<String, dynamic> message) send;

  /// Envia um bloco de bytes (parte de um clipe de áudio).
  final void Function(Uint8List bytes) sendBytes;

  /// Diz se o canal está conectado — sem conexão o áudio é descartado.
  final bool Function() isConnected;

  final void Function(String message) onNotice;
  final void Function() onChanged;

  static const int _uploadChunk = 64 << 10;
  static const Duration _maxClip = Duration(seconds: 60);

  AudioRecorder? _recorder;

  bool _recording = false;
  bool get isRecording => _recording;

  String? _recordingPath;
  String _recordingMime = 'audio/mp4';
  Timer? _recordingTimer;
  Stopwatch? _recordingClock;

  /// Inicia a gravação. Devolve `false` quando o microfone não está
  /// disponível, e o motivo já foi informado em [onNotice].
  Future<bool> start() async {
    if (_recording) return true;
    try {
      final recorder = _recorder ??= AudioRecorder();
      if (!await recorder.hasPermission()) {
        onNotice('Permissão de microfone negada');
        return false;
      }
      final path = audioBridge.newRecordingPath();
      // No navegador o record_web não usa MediaRecorder para WAV (e AAC/mp4
      // depende de suporte do Chrome); WAV via AudioWorklet é universal.
      final isWeb = kIsWeb;
      await recorder.start(
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
      _recordingTimer = Timer(_maxClip, () {
        if (_recording) unawaited(stopAndSend());
      });
      _recording = true;
      send({'type': 'recording_start'});
      onChanged();
      return true;
    } catch (e) {
      debugPrint('[ClipRecorder] erro ao iniciar gravação: $e');
      onNotice('Não foi possível acessar o microfone: $e');
      onChanged();
      return false;
    }
  }

  /// Encerra a gravação e envia a fala para o canal.
  Future<void> stopAndSend() async {
    if (!_recording) return;
    _recording = false;
    _recordingTimer?.cancel();
    _recordingTimer = null;
    onChanged();

    final path = _recordingPath;
    final ms = _recordingClock?.elapsedMilliseconds ?? 0;
    _recordingPath = null;
    _recordingClock = null;
    send({'type': 'recording_stop'});

    try {
      final stoppedPath = await _recorder?.stop();
      if (isConnected()) {
        await _uploadRecording(stoppedPath ?? path, ms);
      }
    } catch (e) {
      debugPrint('[ClipRecorder] falha ao encerrar gravação: $e');
    }
  }

  /// Descarta a gravação em andamento sem enviar nada.
  Future<void> abort() async {
    _recordingTimer?.cancel();
    _recordingTimer = null;
    _recording = false;
    _recordingPath = null;
    _recordingClock = null;
    try {
      await _recorder?.stop();
    } catch (_) {}
    onChanged();
  }

  /// O servidor avisou que a gravação local acabou: o estado local precisa
  /// acompanhar, e o microfone não pode ficar aberto.
  Future<void> markStoppedByServer() async {
    if (!_recording) return;
    _recording = false;
    _recordingTimer?.cancel();
    _recordingTimer = null;
    try {
      await _recorder?.stop();
    } catch (_) {}
    onChanged();
  }

  Future<void> _uploadRecording(String? path, int durationMs) async {
    if (path == null) return;
    try {
      final bytes = await audioBridge.readCaptured(path);
      if (bytes.isEmpty) return;

      final id = _genId();
      send({
        'type': 'clip_start',
        'clipId': id,
        'mime': _recordingMime,
        'durationMs': durationMs,
        'size': bytes.length,
      });
      for (var i = 0; i < bytes.length; i += _uploadChunk) {
        final end = min(i + _uploadChunk, bytes.length);
        sendBytes(Uint8List.sublistView(bytes, i, end));
      }
      send({'type': 'clip_end', 'clipId': id});
    } catch (e) {
      debugPrint('[ClipRecorder] falha ao enviar áudio: $e');
    }
  }

  static String _genId() {
    final rnd = Random.secure();
    final sb = StringBuffer();
    for (var i = 0; i < 32; i++) {
      sb.write(rnd.nextInt(16).toRadixString(16));
    }
    return sb.toString();
  }

  Future<void> dispose() async {
    await abort();
    await _recorder?.dispose();
    _recorder = null;
  }
}
