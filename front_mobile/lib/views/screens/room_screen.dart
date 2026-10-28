import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

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

/// Tela da sala: quem está no canal, o mapa e o botão de falar.
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
  final MapController _mapController = MapController();

  RoomController? _controller;
  bool _mapReady = false;
  Set<String> _lastFitIds = {};
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

  // ---------------- Mapa ----------------

  void _scheduleFitMap() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _fitMapIfNeeded();
    });
  }

  /// Enquadra a câmera nos participantes conhecidos. Só refaz quando a lista
  /// de posições muda, para não brigar com o gesto do usuário.
  void _fitMapIfNeeded() {
    final controller = _controller!;
    if (!controller.showMap || !_mapReady) return;
    final locations = controller.locations;
    final ids = locations.keys.toSet();
    if (ids.isEmpty || ids == _lastFitIds) return;
    _lastFitIds = ids;
    final coords = locations.values
        .map((l) => LatLng(l.lat, l.lng))
        .toList();
    if (coords.isEmpty) return;
    try {
      if (coords.length == 1) {
        _mapController.move(coords.first, 16);
      } else {
        _mapController.fitCamera(CameraFit.coordinates(
          coordinates: coords,
          padding: const EdgeInsets.all(56),
        ));
      }
    } catch (_) {}
  }

  Widget _mapView(RoomController controller) {
    return Stack(
      children: [
        FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: const LatLng(-23.5505, -46.6333),
            initialZoom: 13,
            onMapReady: () {
              _mapReady = true;
              _fitMapIfNeeded();
            },
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'br.com.radiopx',
            ),
            MarkerLayer(markers: _buildMarkers(controller)),
          ],
        ),
        if (controller.locations.isEmpty)
          Center(
            child: Card(
              color: Colors.black.withValues(alpha: 0.6),
              child: const Padding(
                padding: EdgeInsets.all(16),
                child: Text('Aguardando posição dos participantes...'),
              ),
            ),
          ),
      ],
    );
  }

  List<Marker> _buildMarkers(RoomController controller) {
    return controller.locations.values.map((loc) {
      final isMe = loc.userId == controller.myUserId;
      final label = loc.username.isEmpty ? '?' : loc.username[0].toUpperCase();
      return Marker(
        point: LatLng(loc.lat, loc.lng),
        width: 96,
        height: 72,
        alignment: Alignment.topCenter,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor:
                  isMe ? const Color(0xFF525E68) : const Color(0xFF35383D),
              child: Text(
                label,
                style: const TextStyle(fontSize: 16, color: Colors.white),
              ),
            ),
            const SizedBox(height: 2),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                isMe ? 'Você' : loc.username,
                style: const TextStyle(color: Colors.white, fontSize: 10),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      );
    }).toList();
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
          IconButton(
            icon: Icon(
              controller.showMap ? Icons.group : Icons.map_outlined,
            ),
            tooltip: controller.showMap ? 'Ver membros' : 'Ver mapa',
            onPressed: controller.toggleMap,
          ),
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
            _scheduleFitMap();
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
                  if (!controller.showMap)
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
                    child: controller.showMap
                        ? _mapView(controller)
                        : _membersList(controller),
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
