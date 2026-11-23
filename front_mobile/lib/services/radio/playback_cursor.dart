import '../storage/app_config.dart';

/// Cursor de reprodução do canal: guarda o último áudio que terminou de tocar
/// neste aparelho.
///
/// A mesma instância é compartilhada entre o socket (que envia o valor no
/// handshake) e a fila de reprodução (que o avança), para que os dois lados
/// nunca discordem do que já foi ouvido.
class PlaybackCursor {
  PlaybackCursor({required this.channelId, required this.config});

  final String channelId;
  final AppConfig config;

  int _lastHeardSeq = 0;
  int get lastHeardSeq => _lastHeardSeq;

  /// Recarrega o cursor do dispositivo. Chamado a cada conexão, porque o
  /// servidor precisa saber de onde retomar.
  Future<void> load() async {
    _lastHeardSeq = await config.loadLastHeardSeq(channelId);
  }

  /// Avança o cursor. Só deve ser chamado quando o áudio realmente terminou
  /// de tocar: falhas de reprodução não podem silenciar o clipe para sempre.
  Future<void> markHeard(int seq) async {
    if (seq <= _lastHeardSeq) return;
    _lastHeardSeq = seq;
    await config.saveLastHeardSeq(channelId, seq);
  }
}
