import 'dart:typed_data';

import 'package:just_audio/just_audio.dart';

import 'audio_bridge_io.dart'
    if (dart.library.js_interop) 'audio_bridge_web.dart' as impl;

AudioBridge get audioBridge => impl.createAudioBridge();

abstract class AudioBridge {
  /// Caminho usado na gravação. No IO é um arquivo temporário real; na web o
  /// caminho é ignorado pelo record_web (ele grava em um Blob e `stop()` devolve
  /// uma blob URL).
  String newRecordingPath();

  /// Converte a saída da gravação (caminho no IO, blob URL na web) em bytes.
  Future<Uint8List> readCaptured(String output, {String? mimeType});

  /// Cria uma fonte de reprodução a partir dos bytes recebidos. O retorno é
  /// descartável quando o áudio encerra.
  PlaybackSource makePlaybackSource(
    Uint8List bytes, {
    required String mimeType,
    required String clipId,
  });
}

abstract class PlaybackSource {
  AudioSource get audioSource;

  Future<void> dispose();
}