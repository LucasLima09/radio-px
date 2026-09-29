import 'dart:js_interop';
import 'dart:typed_data';

import 'package:just_audio/just_audio.dart';
import 'package:web/web.dart' as web;

import 'audio_bridge.dart';

AudioBridge createAudioBridge() => _WebAudioBridge();

class _WebAudioBridge implements AudioBridge {
  @override
  String newRecordingPath() =>
      'record_${DateTime.now().microsecondsSinceEpoch}';

  @override
  Future<Uint8List> readCaptured(String output, {String? mimeType}) async {
    final response = await web.window.fetch(output.toJS).toDart;
    final buffer = await response.arrayBuffer().toDart;
    return buffer.toDart.asUint8List();
  }

  @override
  PlaybackSource makePlaybackSource(
    Uint8List bytes, {
    required String mimeType,
    required String clipId,
  }) {
    final blob = web.Blob(
      [bytes.toJS].toJS,
      web.BlobPropertyBag(type: mimeType),
    );
    final url = web.URL.createObjectURL(blob);
    return _BlobSource(url);
  }
}

class _BlobSource implements PlaybackSource {
  _BlobSource(this.url);

  final String url;

  @override
  AudioSource get audioSource => AudioSource.uri(Uri.parse(url));

  @override
  Future<void> dispose() async {
    web.URL.revokeObjectURL(url);
  }
}