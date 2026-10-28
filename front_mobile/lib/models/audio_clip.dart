/// Metadados de um clipe de áudio recebido da fila.
///
/// O payload binário chega logo depois da mensagem `clip_new` que carrega
/// estes metadados.
class AudioClip {
  final String clipId;
  final String userId;
  final String username;
  final String mime;
  final int durationMs;
  final int seq;
  final int size;

  const AudioClip({
    required this.clipId,
    required this.userId,
    required this.username,
    required this.mime,
    required this.durationMs,
    required this.seq,
    required this.size,
  });

  factory AudioClip.fromJson(Map<String, dynamic> json) => AudioClip(
        clipId: json['clipId'] as String,
        userId: json['userId'] as String,
        username: json['username'] as String? ?? '',
        mime: json['mime'] as String? ?? 'audio/mp4',
        durationMs: (json['durationMs'] as num?)?.toInt() ?? 0,
        seq: (json['seq'] as num?)?.toInt() ?? 0,
        size: (json['size'] as num?)?.toInt() ?? 0,
      );
}
