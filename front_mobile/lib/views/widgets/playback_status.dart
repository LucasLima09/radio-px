import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';

/// Painel que mostra quem está falando e quantas falas estão na fila.
class PlaybackStatus extends StatelessWidget {
  const PlaybackStatus({
    super.key,
    required this.title,
    required this.icon,
    required this.highlighted,
    required this.pendingCount,
    required this.hint,
  });

  /// Frase que resume a situação: quem está falando agora.
  final String title;

  final IconData icon;

  /// Verdadeiro quando alguém está falando (destaca o painel).
  final bool highlighted;

  /// Falas aguardando reprodução.
  final int pendingCount;

  /// Explicação em uma linha do que vai acontecer.
  final String hint;

  @override
  Widget build(BuildContext context) {
    final count = pendingCount;
    return Container(
      margin: const EdgeInsets.fromLTRB(24, 0, 24, 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: pxCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: highlighted ? pxAccent : pxBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: pxAccent),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Icon(Icons.queue_music, size: 20, color: pxMuted),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '$count fala${count == 1 ? '' : 's'} na fila para reproduzir',
                  style: const TextStyle(color: pxMuted, fontSize: 12),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(hint, style: const TextStyle(color: pxMuted, fontSize: 11)),
        ],
      ),
    );
  }
}
