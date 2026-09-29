import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../api.dart';
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
    try {
      await widget.api.joinChannel(widget.channel.id);
    } on ApiException catch (e) {
      _onNotice(e.message);
    }
    await _radio.connect();
    _tracker?.sendLast();
    if (mounted) setState(() {});
  }

  void _onChanged() {
    if (!mounted) return;
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
    if (_radio.recording) return;
    setState(() => _pttPressed = true);
    _radio.startRecording().then((ok) {
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
          IconButton(
            icon: Icon(_recordMode == RecordMode.hold
                ? Icons.pan_tool_outlined
                : Icons.touch_app_outlined),
            tooltip: _recordMode == RecordMode.hold
                ? 'Gravação: segurar para falar'
                : 'Gravação: toque para começar/parar',
            onPressed: _toggleRecordMode,
          ),
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(
              child: _ConnectionChip(
                state: state,
                onTap: state == radio.RadioConnState.disconnected ? _connect : null,
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            _PresenceBanner(client: _radio),
            _QueueStatusLine(client: _radio),
            if (_radio.members.any((m) => m.recording))
              _RecordingBanner(client: _radio),
            Expanded(
              child: _showMap ? _mapView() : _membersList(),
            ),
            _recordArea(state),
          ],
        ),
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
              backgroundColor: isMe ? Colors.blue.shade700 : Colors.redAccent,
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
      if (a.userId == _radio.myUserId) return -1;
      if (b.userId == _radio.myUserId) return 1;
      return a.username.compareTo(b.username);
    });

    return members.isEmpty
        ? const Center(
            child: Text('Aguardando participantes...',
                style: TextStyle(color: Colors.white54)),
          )
        : GridView.count(
            crossAxisCount: 3,
            padding: const EdgeInsets.all(16),
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            children: members.map(_memberTile).toList(),
          );
  }

  Widget _memberTile(Member member) {
    final isMe = member.userId == _radio.myUserId;
    final isRecording = member.recording;

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Stack(
          children: [
            CircleAvatar(
              radius: 28,
              backgroundColor:
                  isRecording ? Colors.orange.shade700 : Colors.white12,
              child: Text(
                member.username.isEmpty ? '?' : member.username[0].toUpperCase(),
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
            ),
            Positioned(
              right: 0,
              bottom: 0,
              child: Container(
                width: 16,
                height: 16,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isRecording ? Colors.orange : Colors.greenAccent,
                  border: Border.all(color: Colors.black, width: 2),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          isMe ? 'Você' : member.username,
          style: TextStyle(
            fontWeight: isRecording ? FontWeight.bold : FontWeight.normal,
            fontSize: 13,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        if (isRecording)
          const Text(
            'gravando',
            style: TextStyle(color: Colors.orange, fontSize: 11),
          ),
      ],
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
          width: 180,
          height: 180,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: active
                ? Colors.redAccent
                : connected
                    ? const Color(0xFF1565C0)
                    : Colors.white12,
            boxShadow: [
              BoxShadow(
                color: (active ? Colors.redAccent : const Color(0xFF1565C0))
                    .withValues(alpha: 0.4),
                blurRadius: active ? 40 : 24,
                spreadRadius: active ? 8 : 2,
              ),
            ],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                active ? Icons.mic : Icons.mic_none,
                size: 56,
                color: Colors.white,
              ),
              const SizedBox(height: 8),
              Text(
                _recordLabel(connected, active),
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontSize: 13),
              ),
            ],
          ),
        ),
      ),
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

class _ConnectionChip extends StatelessWidget {
  const _ConnectionChip({required this.state, this.onTap});

  final radio.RadioConnState state;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final (color, label) = switch (state) {
      radio.RadioConnState.connected => (Colors.greenAccent, 'Conectado'),
      radio.RadioConnState.connecting => (Colors.orange, 'Conectando'),
      radio.RadioConnState.disconnected => (Colors.redAccent, 'Reconectar'),
    };
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: 0.6)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.circle, size: 10, color: color),
            const SizedBox(width: 6),
            Text(label, style: const TextStyle(fontSize: 12)),
          ],
        ),
      ),
    );
  }
}

class _PresenceBanner extends StatelessWidget {
  const _PresenceBanner({required this.client});

  final radio.RadioClient client;

  @override
  Widget build(BuildContext context) {
    final others =
        client.members.where((m) => m.userId != client.myUserId).length;

    final (Color color, IconData icon, String text) = switch (client.state) {
      radio.RadioConnState.connecting => (
          Colors.orange,
          Icons.hourglass_top,
          'Conectando ao canal...',
        ),
      radio.RadioConnState.disconnected => (
          Colors.redAccent,
          Icons.cloud_off,
          'Conexão perdida',
        ),
      radio.RadioConnState.connected when others == 0 => (
          Colors.redAccent,
          Icons.person_off_outlined,
          'Você está sozinho no canal',
        ),
      radio.RadioConnState.connected => (
          Colors.greenAccent,
          Icons.people_alt_outlined,
          others == 1
              ? '1 outra pessoa conectada'
              : '$others outras pessoas conectadas',
        ),
    };

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(color: color, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

class _QueueStatusLine extends StatelessWidget {
  const _QueueStatusLine({required this.client});

  final radio.RadioClient client;

  @override
  Widget build(BuildContext context) {
    final count = client.pendingPlaybackCount;

    final (Color color, IconData icon, String text) =
        client.recording
            ? (
                Colors.redAccent,
                Icons.mic,
                'Gravando... a escuta está pausada para não atrapalhar',
              )
            : count > 0
                ? (
                    Colors.greenAccent,
                    Icons.graphic_eq,
                    client.audioPlaying
                        ? 'Tocando áudio · $count na fila'
                        : '$count áudio(s) na fila',
                  )
                : (Colors.grey, Icons.queue_music, 'Fila de áudios vazia');

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(color: color, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}

class _RecordingBanner extends StatelessWidget {
  const _RecordingBanner({required this.client});

  final radio.RadioClient client;

  @override
  Widget build(BuildContext context) {
    final recording = client.members.where((m) => m.recording).toList();
    final names = recording.map((m) {
      if (m.userId == client.myUserId) return 'Você';
      return m.username;
    }).toList();
    final label = names.isEmpty
        ? 'Gravando...'
        : recording.length > 1
            ? '${names.take(2).join(' e ')} estão gravando...'
            : '${names.first} está gravando...';

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.orange.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.orange),
      ),
      child: Row(
        children: [
          const Icon(Icons.record_voice_over, color: Colors.orange, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                  color: Colors.orange, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}