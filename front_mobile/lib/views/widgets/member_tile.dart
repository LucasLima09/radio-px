import 'package:flutter/material.dart';

import '../../models/member.dart';
import '../../theme/app_colors.dart';

/// Participante na lista de quem está no canal.
class MemberTile extends StatelessWidget {
  const MemberTile({
    super.key,
    required this.member,
    required this.isMe,
    required this.isPlaying,
  });

  final Member member;
  final bool isMe;

  /// Verdadeiro quando o áudio desta pessoa está tocando agora.
  final bool isPlaying;

  @override
  Widget build(BuildContext context) {
    final active = isPlaying || member.recording;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(vertical: 4),
      leading: CircleAvatar(
        radius: 18,
        backgroundColor: active ? pxAccent : pxTile,
        child: Text(
          member.username.isEmpty ? '?' : member.username[0].toUpperCase(),
          style: TextStyle(
            color: active ? pxOnAccent : pxAccent,
            fontSize: 13,
          ),
        ),
      ),
      title: Text(
        isMe ? '${member.username} (você)' : member.username,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        isPlaying
            ? 'Falando · reproduzindo agora'
            : member.recording
                ? 'Gravando uma fala…'
                : 'Ouvindo o canal',
        style: TextStyle(color: active ? pxAccent : pxMuted, fontSize: 12),
      ),
      trailing: active
          ? const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.graphic_eq, size: 20, color: pxAccent),
                SizedBox(width: 6),
                Text(
                  'Falando',
                  style: TextStyle(color: pxDanger, fontSize: 12),
                ),
              ],
            )
          : const Text(
              'Online',
              style: TextStyle(color: Colors.white54, fontSize: 12),
            ),
    );
  }
}
