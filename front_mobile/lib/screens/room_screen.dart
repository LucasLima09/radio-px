import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../api.dart';
import '../ui.dart';
import '../config.dart';
import '../location_tracker.dart';
import '../models.dart';
import '../radio_client.dart' as radio;

class RoomScreen extends StatefulWidget {
  const RoomScreen({
    super.key,
    required this.api,
    required this.channel,
    required this.myUser,
  });

  final ApiClient api;
  final Channel channel;
  final PublicUser myUser;

  @override
  State<RoomScreen> createState() => _RoomScreenState();
}

class _RoomScreenState extends State<RoomScreen> {
  late final radio.RadioClient _radio;
  final MapController _mapController = MapController();
  LocationTracker? _tracker;
  RecordMode _recordMode = RecordMode.hold;
  bool _pttPressed = false;
  bool _showMap = false;
  bool _mapReady = false;
  Set<String> _lastFitIds = {};
  bool _joining = false;
  bool _startingRecording = false;
  bool _wasConnected = false;
  String? _connectionError;

  @override
  void initState() {
    super.initState();
    _radio = radio.RadioClient(
      baseUrl: widget.api.baseUrl,
      channelId: widget.channel.id,
      tokenProvider: widget.api.ensureAccessToken,
    );
    _radio.onChanged = _onChanged;
    _radio.onNotice = _onNotice;
    _loadRecordMode();
    _initLocation();
    _connect();
  }

  Future<void> _loadRecordMode() async {
    final mode = await AppConfig.loadRecordMode();
    if (!mounted) return;
    setState(() => _recordMode = mode);
  }

  Future<void> _toggleRecordMode() async {
    final next = _recordMode == RecordMode.hold ? RecordMode.tap : RecordMode.hold;
    setState(() => _recordMode = next);
    await AppConfig.saveRecordMode(next);
  }

  Future<void> _initLocation() async {
    final tracker = LocationTracker()
      ..onPosition = _onPosition
      ..onError = _onNotice;
    _tracker = tracker;
    await tracker.start();
    if (mounted) setState(() {});
  }

  void _onPosition(double lat, double lng) {
    _radio.sendLocation(lat, lng);
  }

  Future<void> _connect() async {
    if (_joining) return;
    setState(() { _joining = true; _connectionError = null; });
    try {
      await widget.api.joinChannel(widget.channel.id);
      if (!mounted) return;
      await _radio.connect();
    } catch (error) {
      if (mounted) setState(() => _connectionError = error.toString());
    } finally {
      if (mounted) setState(() => _joining = false);
    }
  }

  void _onChanged() {
    if (!mounted) return;
    final connected = _radio.state == radio.RadioConnState.connected;
    if (connected && !_wasConnected) {
      _tracker?.sendLast();
      _connectionError = null;
    }
    _wasConnected = connected;
    setState(() {});
    _fitMapIfNeeded();
  }

  void _onNotice(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  void _recordPressed() {
    if (_radio.state != radio.RadioConnState.connected) {
      _onNotice('Ainda não conectado ao canal');
      return;
    }
    if (_recordMode == RecordMode.tap) {
      if (_radio.recording) {
        _radio.stopRecordingAndSend();
      } else {
        _radio.startRecording();
      }
      return;
    }
    if (_radio.recording || _startingRecording) return;
    _startingRecording = true;
    setState(() => _pttPressed = true);
    _radio.startRecording().then((ok) {
      _startingRecording = false;
      if (ok && !_pttPressed) _radio.stopRecordingAndSend();
      if (!ok && mounted) setState(() => _pttPressed = false);
    });
  }

  void _recordReleased() {
    if (_recordMode == RecordMode.tap) return;
    if (!_pttPressed) return;
    setState(() => _pttPressed = false);
    _radio.stopRecordingAndSend();
  }

  @override
  void dispose() {
    _radio.onChanged = null;
    _radio.onNotice = null;
    _tracker?.stop();
    _radio.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = _radio.state;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.channel.name),
        actions: [
          IconButton(
            icon: Icon(_showMap ? Icons.group : Icons.map_outlined),
            tooltip: _showMap ? 'Ver membros' : 'Ver mapa',
            onPressed: () => setState(() => _showMap = !_showMap),
          ),
          PopupMenuButton<String>(
            tooltip: 'Opções',
            onSelected: (value) {
              if (value == 'mode') _toggleRecordMode();
              if (value == 'reconnect') _connect();
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'mode',
                child: Text(_recordMode == RecordMode.hold
                    ? 'Mudar para toque'
                    : 'Mudar para segurar'),
              ),
              if (state == radio.RadioConnState.disconnected)
                const PopupMenuItem(
                  value: 'reconnect',
                  child: Text('Reconectar'),
                ),
            ],
          ),
        ],
      ),
      body: SafeArea(
        child: ContentWidth(child: Column(
          children: [
            _RoomStatus(client: _radio),
            if (!_showMap)
              const Padding(
                padding: EdgeInsets.fromLTRB(24, 8, 24, 16),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text('PESSOAS NO CANAL', style: TextStyle(
                    color: pxMuted, fontSize: 11,
                    letterSpacing: 1.8, fontWeight: FontWeight.w600,
                  )),
                ),
              ),
            if (_connectionError != null) Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
              child: Text(_connectionError!, style: const TextStyle(color: Color(0xFFE79B94)),
                  maxLines: 3, overflow: TextOverflow.ellipsis),
            ),
            _playbackStatus(),
            Expanded(
              child: _showMap ? _mapView() : _membersList(),
            ),
            _recordArea(state),
          ],
        )),
      ),
    );
  }

  Widget _mapView() {
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
            MarkerLayer(markers: _buildMarkers()),
          ],
        ),
        if (_radio.locations.isEmpty)
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

  List<Marker> _buildMarkers() {
    return _radio.locations.values.map((loc) {
      final isMe = loc.userId == _radio.myUserId;
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
              backgroundColor: isMe ? const Color(0xFF525E68) : const Color(0xFF35383D),
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

  void _fitMapIfNeeded() {
    if (!_showMap || !_mapReady) return;
    final ids = _radio.locations.keys.toSet();
    if (ids.isEmpty || ids == _lastFitIds) return;
    _lastFitIds = ids;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_mapReady) return;
      final locs = _radio.locations.values.toList();
      if (locs.isEmpty) return;
      final coords = locs.map((l) => LatLng(l.lat, l.lng)).toList();
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
    });
  }

  Widget _membersList() {
    final members = [..._radio.members];
    members.sort((a, b) {
      final playingId = _radio.audioPlaying ? _radio.currentPlayback?.userId : null;
      final aActive = a.recording || a.userId == playingId;
      final bActive = b.recording || b.userId == playingId;
      if (aActive != bActive) return aActive ? -1 : 1;
      if (a.userId == _radio.myUserId) return -1;
      if (b.userId == _radio.myUserId) return 1;
      return a.username.compareTo(b.username);
    });

    return members.isEmpty
        ? const Center(
            child: Text('Aguardando participantes...',
                style: TextStyle(color: Colors.white54)),
          )
        : ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
            itemCount: members.length,
            separatorBuilder: (_, _) => const Divider(),
            itemBuilder: (_, index) => _memberTile(members[index]),
          );
  }

  Widget _memberTile(Member member) {
    final isMe = member.userId == _radio.myUserId;
    final playing = _radio.audioPlaying && _radio.currentPlayback?.userId == member.userId;
    final active = playing || member.recording;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(vertical: 4),
      leading: CircleAvatar(
        radius: 18,
        backgroundColor: active ? pxAccent : const Color(0xFF232330),
        child: Text(member.username.isEmpty ? '?' : member.username[0].toUpperCase(),
            style: TextStyle(color: active ? const Color(0xFF101116) : pxAccent, fontSize: 13)),
      ),
      title: Text(isMe ? '${member.username} (você)' : member.username,
          maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(playing ? 'Falando · reproduzindo agora' : member.recording ? 'Gravando uma fala…' : 'Ouvindo o canal',
          style: TextStyle(color: active ? pxAccent : pxMuted, fontSize: 12)),
      trailing: active
          ? const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.graphic_eq, size: 20, color: pxAccent),
                SizedBox(width: 6),
                Text('Falando', style: TextStyle(
                    color: Color(0xFFE79B94), fontSize: 12)),
              ],
            )
          : const Text('Online',
              style: TextStyle(color: Colors.white54, fontSize: 12)),
    );
  }

  Widget _recordArea(radio.RadioConnState state) {
    if (state == radio.RadioConnState.disconnected) {
      return OutlinedButton.icon(
        onPressed: _connect,
        icon: const Icon(Icons.refresh),
        label: const Text('Reconectar'),
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
        ),
      );
    }

    final connected = state == radio.RadioConnState.connected;
    final recording = _radio.recording;
    final active = _pttPressed || recording;
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Listener(
        onPointerDown: connected ? (_) => _recordPressed() : null,
        onPointerUp: connected ? (_) => _recordReleased() : null,
        onPointerCancel: connected ? (_) => _recordReleased() : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          width: 144,
          height: 144,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: active
                ? const Color(0xFF9B4540)
                : connected
                    ? const Color(0xFFB9B2FF)
                    : const Color(0xFF25282C),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                active ? Icons.mic : Icons.mic_none,
                size: 36,
                color: connected && !active ? const Color(0xFF101116) : Colors.white,
              ),
              const SizedBox(height: 8),
              Text(
                _recordLabel(connected, active),
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: connected && !active ? const Color(0xFF101116) : Colors.white,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _playbackStatus() {
    final current = _radio.currentPlayback;
    final count = _radio.pendingPlaybackCount;
    final playing = _radio.audioPlaying && current != null;
    final speakers = _radio.members.where((member) => member.recording).map((member) => member.username).toList();
    final title = _radio.recording ? 'Você está falando'
        : playing ? '${current.username} está falando'
        : speakers.isNotEmpty ? '${speakers.join(', ')} gravando…'
        : 'Aguardando a próxima fala';
    return Container(
      margin: const EdgeInsets.fromLTRB(24, 0, 24, 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: const Color(0xFF1E1C2C),
          borderRadius: BorderRadius.circular(14), border: Border.all(color: playing || _radio.recording ? pxAccent : pxBorder)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(_radio.recording ? Icons.mic : playing ? Icons.volume_up : Icons.headphones, color: pxAccent),
          const SizedBox(width: 10),
          Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.w600), maxLines: 2, overflow: TextOverflow.ellipsis)),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          const Icon(Icons.queue_music, size: 20, color: pxMuted),
          const SizedBox(width: 8),
          Expanded(child: Text('$count fala${count == 1 ? '' : 's'} na fila para reproduzir',
              style: const TextStyle(color: pxMuted, fontSize: 12))),
        ]),
        const SizedBox(height: 6),
        Text(_radio.recording ? 'A escuta continua quando você terminar.'
            : playing ? 'Reproduzindo agora · próximas falas em ordem.' : 'As falas serão reproduzidas na ordem de chegada.',
            style: const TextStyle(color: pxMuted, fontSize: 11)),
      ]),
    );
  }

  String _recordLabel(bool connected, bool active) {
    if (!connected) return 'Conectando...';
    if (active) {
      return _recordMode == RecordMode.tap
          ? 'Gravando...\ntoque para enviar'
          : 'Gravando...\nsolte para enviar';
    }
    return _recordMode == RecordMode.tap
        ? 'Toque para gravar'
        : 'Segure para falar';
  }
}

class _RoomStatus extends StatelessWidget {
  const _RoomStatus({required this.client});

  final radio.RadioClient client;

  @override
  Widget build(BuildContext context) {
    final others = client.members.where((m) => m.userId != client.myUserId).length;
    final label = switch (client.state) {
      radio.RadioConnState.connecting => 'Conectando...',
      radio.RadioConnState.disconnected => 'Desconectado',
      radio.RadioConnState.connected when others == 0 => 'Só você no canal',
      radio.RadioConnState.connected => '${client.members.length} participantes online',
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
      child: Row(
        children: [
          Icon(Icons.circle, size: 6,
              color: client.state == radio.RadioConnState.connected
                  ? const Color(0xFF93B5A1)
                  : Colors.white54),
          const SizedBox(width: 8),
          Expanded(child: Text(label,
              style: const TextStyle(color: Colors.white54, fontSize: 13))),
        ],
      ),
    );
  }
}
