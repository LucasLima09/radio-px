import 'package:flutter/material.dart';

import '../../controllers/room_controller.dart';
import '../../di.dart';
import '../../models/active_session.dart';
import '../../models/channel.dart';
import '../../models/member.dart';
import '../../models/record_mode.dart';
import '../../services/radio/radio_channel.dart';
import '../../theme/app_colors.dart';
import '../widgets/content_width.dart';
import '../widgets/member_tile.dart';
import '../widgets/playback_status.dart';
import '../widgets/record_button.dart';
import '../widgets/room_status.dart';

/// Tela da sala: quem está no canal e o botão de falar.
class RoomScreen extends StatefulWidget {
  const RoomScreen({
    super.key,
    required this.session,
    required this.channel,
  });

  final ActiveSession session;
  final Channel channel;

  @override
  State<RoomScreen> createState() => _RoomScreenState();
}

class _RoomScreenState extends State<RoomScreen> {
  RoomController? _controller;
  int _lastNoticeId = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_controller != null) return;
    _controller = RoomController(
      api: widget.session.api,
      channel: widget.channel,
      user: widget.session.user,
      config: AppScope.of(context).config,
    );
    _controller!.init();
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  // ---------------- Lista de participantes ----------------

  List<Member> _sortedMembers(RoomController controller) {
    final members = [...controller.members];
    final playingId =
        controller.audioPlaying ? controller.currentPlayback?.userId : null;
    members.sort((a, b) {
      final aActive = a.recording || a.userId == playingId;
      final bActive = b.recording || b.userId == playingId;
      if (aActive != bActive) return aActive ? -1 : 1;
      if (a.userId == controller.myUserId) return -1;
      if (b.userId == controller.myUserId) return 1;
      return a.username.compareTo(b.username);
    });
    return members;
  }

  Widget _membersList(RoomController controller) {
    final members = _sortedMembers(controller);
    if (members.isEmpty) {
      return const Center(
        child: Text(
          'Aguardando participantes...',
          style: TextStyle(color: Colors.white54),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      itemCount: members.length,
      separatorBuilder: (_, _) => const Divider(),
      itemBuilder: (_, index) {
        final member = members[index];
        return MemberTile(
          member: member,
          isMe: member.userId == controller.myUserId,
          isPlaying: controller.audioPlaying &&
              controller.currentPlayback?.userId == member.userId,
        );
      },
    );
  }

  // ---------------- Painéis ----------------

  Widget _playbackStatus(RoomController controller) {
    final current = controller.currentPlayback;
    final recording = controller.isRecording;
    final playing = controller.audioPlaying && current != null;
    final speakers = controller.members
        .where((member) => member.recording)
        .map((member) => member.username)
        .toList();
    final title = recording
        ? 'Você está falando'
        : playing
            ? '${current.username} está falando'
            : speakers.isNotEmpty
                ? '${speakers.join(', ')} gravando…'
                : 'Aguardando a próxima fala';
    final hint = recording
        ? 'A escuta continua quando você terminar.'
        : playing
            ? 'Reproduzindo agora · próximas falas em ordem.'
            : 'As falas serão reproduzidas na ordem de chegada.';
    return PlaybackStatus(
      title: title,
      icon: recording
          ? Icons.mic
          : playing
              ? Icons.volume_up
              : Icons.headphones,
      highlighted: playing || recording,
      pendingCount: controller.pendingCount,
      hint: hint,
    );
  }

  String _recordLabel(RoomController controller) {
    if (controller.state != RadioConnState.connected) return 'Conectando...';
    final active = controller.isPttPressed || controller.isRecording;
    if (active) {
      return controller.recordMode == RecordMode.tap
          ? 'Gravando...\ntoque para enviar'
          : 'Gravando...\nsolte para enviar';
    }
    return controller.recordMode == RecordMode.tap
        ? 'Toque para gravar'
        : 'Segure para falar';
  }

  Widget _recordArea(RoomController controller) {
    if (controller.state == RadioConnState.disconnected) {
      return OutlinedButton.icon(
        onPressed: controller.connect,
        icon: const Icon(Icons.refresh),
        label: const Text('Reconectar'),
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
        ),
      );
    }
    final connected = controller.state == RadioConnState.connected;
    return RecordButton(
      connected: connected,
      active: controller.isPttPressed || controller.isRecording,
      label: _recordLabel(controller),
      onPressed: controller.pressRecord,
      onReleased: controller.releaseRecord,
    );
  }

  /// O controller avisa sobre os eventos que viram SnackBar. O id muda a cada
  /// aviso, então dá para mostrar o mesmo texto duas vezes seguidas.
  void _showPendingNotice() {
    final controller = _controller!;
    if (controller.noticeId == _lastNoticeId) return;
    _lastNoticeId = controller.noticeId;
    final notice = controller.notice;
    if (notice == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(SnackBar(content: Text(notice)));
    });
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller!;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.channel.name),
        actions: [
          PopupMenuButton<String>(
            tooltip: 'Opções',
            onSelected: (value) {
              if (value == 'mode') controller.toggleRecordMode();
              if (value == 'reconnect') controller.connect();
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'mode',
                child: Text(
                  controller.recordMode == RecordMode.hold
                      ? 'Mudar para toque'
                      : 'Mudar para segurar',
                ),
              ),
              if (controller.state == RadioConnState.disconnected)
                const PopupMenuItem(
                  value: 'reconnect',
                  child: Text('Reconectar'),
                ),
            ],
          ),
        ],
      ),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: controller,
          builder: (context, _) {
            _showPendingNotice();
            return ContentWidth(
              child: Column(
                children: [
                  RoomStatus(
                    state: controller.state,
                    memberCount: controller.members.length,
                    othersCount: controller.members
                        .where((m) => m.userId != controller.myUserId)
                        .length,
                  ),
                  const Padding(
                    padding: EdgeInsets.fromLTRB(24, 8, 24, 16),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'PESSOAS NO CANAL',
                        style: TextStyle(
                          color: pxMuted,
                          fontSize: 11,
                          letterSpacing: 1.8,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  if (controller.connectionError != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 8,
                      ),
                      child: Text(
                        controller.connectionError!,
                        style: const TextStyle(color: pxDanger),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  _playbackStatus(controller),
                  Expanded(
                    child: _membersList(controller),
                  ),
                  _recordArea(controller),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
