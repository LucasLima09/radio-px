import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../api.dart';
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
  final RTCVideoRenderer _remoteRenderer = RTCVideoRenderer();
  bool _rendererReady = false;
  bool _pttPressed = false;

  @override
  void initState() {
    super.initState();
    _radio = radio.RadioClient(
      baseUrl: widget.api.baseUrl,
      channelId: widget.channel.id,
      channelName: widget.channel.name,
      tokenProvider: widget.api.ensureAccessToken,
    );
    _radio.onChanged = _onChanged;
    _radio.onNotice = _onNotice;
    _radio.onBusy = _onBusy;
    _remoteRenderer.initialize().then((_) {
      if (!mounted) return;
      _rendererReady = true;
      _syncAudio();
      setState(() {});
    });
    _connect();
  }

  Future<void> _connect() async {
    try {
      await widget.api.joinChannel(widget.channel.id);
    } on ApiException catch (e) {
      _onNotice(e.message);
    }
    await _radio.connect();
    if (mounted) setState(() {});
  }

  void _syncAudio() {
    if (_rendererReady) {
      _remoteRenderer.srcObject = _radio.remoteStream;
    }
  }

  void _onChanged() {
    if (!mounted) return;
    _syncAudio();
    setState(() {});
  }

  void _onNotice(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  void _onBusy() {
    if (!mounted) return;
    setState(() => _pttPressed = false);
  }

  void _pttDown() {
    if (_radio.state != radio.RadioConnState.connected) {
      _onNotice('Ainda não conectado ao canal');
      return;
    }
    if (_pttPressed) return;
    setState(() => _pttPressed = true);
    _radio.startTransmitting().then((ok) {
      if (!ok && mounted) setState(() => _pttPressed = false);
    });
  }

  void _pttUp() {
    if (!_pttPressed) return;
    setState(() => _pttPressed = false);
    _radio.stopTransmitting();
  }

  @override
  void dispose() {
    _radio.dispose();
    _remoteRenderer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = _radio.state;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.channel.name),
        actions: [
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
            _AudioStatusLine(client: _radio),
            if (_radio.activeTalkerId != null) _TalkerBanner(client: _radio),
            Expanded(
              child: _membersList(),
            ),
            _pttArea(state),
            const SizedBox(height: 28),
            SizedBox(
              width: 1,
              height: 1,
              child: RTCVideoView(_remoteRenderer),
            ),
          ],
        ),
      ),
    );
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
    final isTalking = member.userId == _radio.activeTalkerId;

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Stack(
          children: [
            CircleAvatar(
              radius: 28,
              backgroundColor:
                  isTalking ? Colors.orange.shade700 : Colors.white12,
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
                  color: isTalking ? Colors.orange : Colors.greenAccent,
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
            fontWeight: isTalking ? FontWeight.bold : FontWeight.normal,
            fontSize: 13,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        if (isTalking)
          const Text(
            'falando',
            style: TextStyle(color: Colors.orange, fontSize: 11),
          ),
      ],
    );
  }

  Widget _pttArea(radio.RadioConnState state) {
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
    return Listener(
      onPointerDown: connected ? (_) => _pttDown() : null,
      onPointerUp: connected ? (_) => _pttUp() : null,
      onPointerCancel: connected ? (_) => _pttUp() : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        width: 180,
        height: 180,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: _pttPressed
              ? Colors.redAccent
              : connected
                  ? const Color(0xFF1565C0)
                  : Colors.white12,
          boxShadow: [
            BoxShadow(
              color: (_pttPressed ? Colors.redAccent : const Color(0xFF1565C0))
                  .withValues(alpha: 0.4),
              blurRadius: _pttPressed ? 40 : 24,
              spreadRadius: _pttPressed ? 8 : 2,
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              _pttPressed ? Icons.mic : Icons.mic_none,
              size: 56,
              color: Colors.white,
            ),
            const SizedBox(height: 8),
            Text(
              _pttPressed
                  ? 'Transmitindo'
                  : connected
                      ? 'Segure para falar'
                      : 'Conectando...',
              style: const TextStyle(color: Colors.white, fontSize: 14),
            ),
          ],
        ),
      ),
    );
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
          others == 1 ? '1 outra pessoa conectada' : '$others outras pessoas conectadas',
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

class _AudioStatusLine extends StatelessWidget {
  const _AudioStatusLine({required this.client});

  final radio.RadioClient client;

  @override
  Widget build(BuildContext context) {
    final state = client.recvState;
    final (Color color, String text) = switch (state) {
      null => (Colors.grey, 'Áudio: aguardando conexão...'),
      RTCPeerConnectionState.RTCPeerConnectionStateConnected => (
          Colors.greenAccent,
          'Áudio recebido: conectado',
        ),
      RTCPeerConnectionState.RTCPeerConnectionStateConnecting => (
          Colors.orange,
          'Áudio: conectando...',
        ),
      RTCPeerConnectionState.RTCPeerConnectionStateDisconnected => (
          Colors.orange,
          'Áudio: desconectado',
        ),
      RTCPeerConnectionState.RTCPeerConnectionStateFailed => (
          Colors.redAccent,
          'Áudio: falha na conexão',
        ),
      _ => (Colors.grey, 'Áudio: $state'),
    };

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
          Icon(
            state == RTCPeerConnectionState.RTCPeerConnectionStateConnected
                ? Icons.graphic_eq
                : Icons.speaker,
            color: color,
            size: 18,
          ),
          const SizedBox(width: 8),
          Text(
            text,
            style: TextStyle(color: color, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _TalkerBanner extends StatelessWidget {
  const _TalkerBanner({required this.client});

  final radio.RadioClient client;

  @override
  Widget build(BuildContext context) {
    final talker = client.members
        .where((m) => m.userId == client.activeTalkerId)
        .firstOrNull;
    final name = talker == null
        ? (client.activeTalkerId == client.myUserId ? 'Você' : 'Alguém')
        : talker.username;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.redAccent.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.redAccent),
      ),
      child: Row(
        children: [
          Icon(Icons.record_voice_over, color: Colors.redAccent, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '$name está transmitindo...',
              style: const TextStyle(
                  color: Colors.redAccent, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}