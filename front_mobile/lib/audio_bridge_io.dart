import 'dart:io';
import 'dart:typed_data';

import 'package:just_audio/just_audio.dart';

import 'audio_bridge.dart';

AudioBridge createAudioBridge() => _IoAudioBridge();

class _IoAudioBridge implements AudioBridge {
  @override
  String newRecordingPath() =>
      '${Directory.systemTemp.path}/radio_${DateTime.now().microsecondsSinceEpoch}.m4a';

  @override
  Future<Uint8List> readCaptured(String output, {String? mimeType}) async {
    final file = File(output);
    final bytes = await file.readAsBytes();
    file.delete().then((_) {}, onError: (Object _) {});
    return bytes;
  }

  @override
  PlaybackSource makePlaybackSource(
    Uint8List bytes, {
    required String mimeType,
    required String clipId,
  }) {
    final dir = Directory('${Directory.systemTemp.path}/radio_clip_$clipId');
    dir.createSync(recursive: true);
    final file = File('${dir.path}/clip.${_extFor(mimeType)}')
      ..writeAsBytesSync(bytes, flush: true);
    return _FileSource(file, dir);
  }

  static String _extFor(String mime) {
    if (mime.contains('ogg') || mime.contains('opus')) return 'opus';
    if (mime.contains('webm')) return 'webm';
    if (mime.contains('wav')) return 'wav';
    return 'm4a';
  }
}

class _FileSource implements PlaybackSource {
  _FileSource(this.file, this.dir);

  final File file;
  final Directory dir;

  @override
  AudioSource get audioSource => AudioSource.file(file.path);

  @override
  Future<void> dispose() async {
    try {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    } catch (_) {}
  }
}