import 'dart:typed_data';

import '../../models/audio_clip.dart';

/// Eventos emitidos pelo canal de rádio para o controller que o coordena.
sealed class RadioEvent {
  const RadioEvent();
}

/// Um clipe chegou completo: metadados e bytes.
class RadioClipReceived extends RadioEvent {
  const RadioClipReceived(this.meta, this.bytes);

  final AudioClip meta;
  final Uint8List bytes;
}

/// Aviso para o usuário.
class RadioNotice extends RadioEvent {
  const RadioNotice(this.message);

  final String message;
}

/// O servidor recusou a sessão: reconectar não resolve, é preciso entrar de
/// novo.
class RadioSessionEnded extends RadioEvent {
  const RadioSessionEnded(this.message);

  final String message;
}

/// O servidor avisou que a gravação local acabou.
class RadioLocalRecordingStopped extends RadioEvent {
  const RadioLocalRecordingStopped();
}

/// Presença ou estado da conexão mudaram.
class RadioChanged extends RadioEvent {
  const RadioChanged();
}
