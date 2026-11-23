import 'package:flutter/material.dart';

import '../../services/radio/radio_channel.dart';

/// Linha de status da sala: conexão e quantas pessoas estão online.
class RoomStatus extends StatelessWidget {
  const RoomStatus({
    super.key,
    required this.state,
    required this.memberCount,
    required this.othersCount,
  });

  final RadioConnState state;

  /// Total de participantes no canal.
  final int memberCount;

  /// Participantes que não são o usuário atual.
  final int othersCount;

  @override
  Widget build(BuildContext context) {
    final label = switch (state) {
      RadioConnState.connecting => 'Conectando...',
      RadioConnState.disconnected => 'Desconectado',
      RadioConnState.connected when othersCount == 0 => 'Só você no canal',
      RadioConnState.connected => '$memberCount participantes online',
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
      child: Row(
        children: [
          Icon(
            Icons.circle,
            size: 6,
            color: state == RadioConnState.connected
                ? const Color(0xFF93B5A1)
                : Colors.white54,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(color: Colors.white54, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}
