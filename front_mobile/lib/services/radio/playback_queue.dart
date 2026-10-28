import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

import '../../models/audio_clip.dart';
import '../platform/audio_bridge.dart';
import 'playback_cursor.dart';

/// Áudio aguardando reprodução local (bytes já recebidos).
class QueuedAudio {
  QueuedAudio(this.meta, this.source);

  final AudioClip meta;
  final PlaybackSource source;
}

/// Fila de reprodução local: guarda as falas recebidas e toca uma de cada vez.
///
/// Enquanto [isMuted] está ativo (durante a gravação) os clipes ficam
/// na fila, sem tocar.
class PlaybackQueue {
  PlaybackQueue({required this.cursor, required this.onChanged});

  final PlaybackCursor cursor;
  final void Function() onChanged;

  final List<QueuedAudio> _queue = [];
  QueuedAudio? _current;

  AudioPlayer? _player;
  StreamSubscription<PlayerState>? _playerSub;

  bool _playing = false;
  bool _muted = false;

  int get pendingCount => _queue.length;
  bool get isPlaying => _playing;
  bool get isMuted => _muted;
  bool get hasCurrent => _current != null;
  AudioClip? get currentPlayback => _current?.meta;
  List<AudioClip> get queued => List.unmodifiable(_queue.map((item) => item.meta));

  /// O player é criado sob demanda: enquanto ninguém fala, o app não segura
  /// o codec de áudio do aparelho.
  AudioPlayer get _playerInstance {
    final player = _player ??= AudioPlayer();
    _playerSub ??= player.playerStateStream.listen((ps) {
      if (ps.processingState == ProcessingState.completed && _playing) {
        onPlaybackCompleted(markedAsHeard: true);
      }
    });
    return player;
  }

  /// Coloca uma fala recebida no fim da fila.
  void enqueue(AudioClip meta, Uint8List bytes) {
    try {
      final source = audioBridge.makePlaybackSource(
        bytes,
        mimeType: meta.mime,
        clipId: meta.clipId,
      );
      _queue.add(QueuedAudio(meta, source));
      onChanged();
      playNext();
    } catch (e) {
      debugPrint('[PlaybackQueue] falha ao preparar áudio recebido: $e');
    }
  }

  void mute() => _muted = true;

  void unmute() => _muted = false;

  /// Pausa a reprodução atual, se houver. Usado quando a gravação começa.
  void pauseIfPlaying() {
    final player = _player;
    if (player == null || !_playing) return;
    unawaited(player.pause());
  }

  /// Retoma a reprodução pausada.
  void resume() {
    final player = _player;
    if (player == null) return;
    unawaited(player.play().catchError((_) {}));
  }

  /// Toca a próxima fala da fila, se houver.
  void playNext() {
    if (_muted || _playing || _queue.isEmpty) return;
    final next = _queue.removeAt(0);
    _current = next;
    _playing = true;
    onChanged();
    _playerInstance
        .setAudioSource(next.source.audioSource)
        .then((_) => _playerInstance.play())
        .catchError((Object e) {
      debugPrint('[PlaybackQueue] falha ao reproduzir: $e');
      // Não conta como ouvido: o servidor reenviará este áudio na reconexão.
      onPlaybackCompleted(markedAsHeard: false);
    });
  }

  /// [markedAsHeard] só é verdadeiro quando o player chegou ao fim do áudio.
  /// Falhas de reprodução não avançam o cursor, senão um áudio que nem tocou
  /// seria silenciado para sempre.
  void onPlaybackCompleted({required bool markedAsHeard}) {
    if (!_playing) return;
    final done = _current;
    _current = null;
    _playing = false;
    if (done != null) {
      done.source.dispose();
      if (markedAsHeard) unawaited(cursor.markHeard(done.meta.seq));
    }
    onChanged();
    playNext();
  }

  /// Para a reprodução e descarta a fila.
  Future<void> clear() async {
    try {
      await _player?.stop();
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
    onChanged();
  }

  Future<void> dispose() async {
    await clear();
    await _playerSub?.cancel();
    _playerSub = null;
    await _player?.dispose();
    _player = null;
  }
}
