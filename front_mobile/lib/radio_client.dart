import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'ws_channel.dart';

import 'models.dart';

enum RadioConnState { connecting, connected, disconnected }

class RadioClient {
  RadioClient({
    required this.baseUrl,
    required this.channelId,
    required this.channelName,
    required this.tokenProvider,
  });

  final String baseUrl;
  final String channelId;
  final String channelName;
  final Future<String> Function() tokenProvider;

  WebSocketChannel? _ws;
  StreamSubscription? _sub;
  RTCPeerConnection? _recvPc;
  RTCPeerConnection? _publishPc;
  MediaStream? _mic;
  MediaStream? _remoteStream;

  final List<WsIceCandidate> _pendingRecvCandidates = [];
  bool _recvRemoteSet = false;

  String? myUserId;

  RadioConnState _state = RadioConnState.disconnected;
  RadioConnState get state => _state;

  RTCPeerConnectionState? _recvState;
  RTCPeerConnectionState? get recvState => _recvState;

  MediaStream? get remoteStream => _remoteStream;

  final List<Member> members = [];
  final Map<String, MemberLocation> locations = {};
  bool transmitting = false;
  String? activeTalkerId;

  VoidCallback? onChanged;
  void Function(String message)? onNotice;
  VoidCallback? onBusy;

  bool _disposed = false;
  bool _webNgrokHintShown = false;
  Future<void> _pending = Future.value();

  static Map<String, dynamic> get _iceConfig => {
        'iceServers': [
          {
            'urls': [
              'stun:stun.l.google.com:19302',
              'stun:stun1.l.google.com:19302',
            ],
          },
        ],
      };

  Future<void> connect() async {
    _disposed = false;
    _setState(RadioConnState.connecting);
    try {
      final token = await tokenProvider();
      final wsBase = baseUrl.replaceFirst(RegExp(r'^http'), 'ws');
      final uri = Uri.parse('$wsBase/ws').replace(queryParameters: {
        'token': token,
        'channel_id': channelId,
      });
      _ws = await openWsChannel(uri, {'ngrok-skip-browser-warning': '1'});
      _sub = _ws!.stream.listen(
        _enqueue,
        onError: (_) => _onClosed(),
        onDone: _onClosed,
      );
    } catch (_) {
      _onClosed();
    }
    _notify();
  }

  Future<void> reconnect() async {
    await _sub?.cancel();
    _sub = null;
    _ws = null;
    await connect();
  }

  void _enqueue(dynamic data) {
    _pending = _pending
        .then((_) => _onMessage(data))
        .catchError((Object _) {});
  }

  Future<void> _onMessage(dynamic data) async {
    if (_disposed) return;
    final Map<String, dynamic> map;
    try {
      map = jsonDecode(data as String) as Map<String, dynamic>;
    } catch (_) {
      return;
    }

    final msg = WsMessage.fromJson(map);
    switch (msg.type) {
      case 'joined':
        _setState(RadioConnState.connected);
        myUserId = msg.userId;
        members
          ..clear()
          ..addAll(msg.members ?? const []);
        locations
          ..clear()
          ..addAll({
            for (final loc in msg.locations ?? const <MemberLocation>[])
              loc.userId: loc,
          });
        for (final m in members) {
          if (m.talking) {
            activeTalkerId = m.userId;
            break;
          }
        }
        _notify();

      case 'peer_joined':
        if (msg.userId != null) {
          members.removeWhere((m) => m.userId == msg.userId);
          members.add(
              Member(userId: msg.userId!, username: msg.username ?? 'Radialista'));
        }
        _notify();

      case 'peer_left':
        members.removeWhere((m) => m.userId == msg.userId);
        locations.remove(msg.userId);
        if (activeTalkerId == msg.userId) activeTalkerId = null;
        _notify();

      case 'location_update':
        if (msg.userId != null && msg.lat != null && msg.lng != null) {
          locations[msg.userId!] = MemberLocation(
            userId: msg.userId!,
            username: msg.username ?? '',
            lat: msg.lat!,
            lng: msg.lng!,
          );
          _notify();
        }

      case 'offer':
        if (msg.target == 'receive' && msg.sdp != null) {
          await _handleRecvOffer(msg.sdp!);
        }

      case 'answer':
        if (msg.target == 'publish' &&
            msg.sdp != null &&
            _publishPc != null) {
          await _publishPc!
              .setRemoteDescription(RTCSessionDescription(msg.sdp!, 'answer'));
        }

      case 'ice':
        if (msg.candidate == null || msg.candidate!.candidate.isEmpty) return;
        if (msg.target == 'publish') {
          final pc = _publishPc;
          if (pc == null) return;
          await pc.addCandidate(RTCIceCandidate(
            msg.candidate!.candidate,
            msg.candidate!.sdpMid,
            msg.candidate!.sdpMLineIndex,
          ));
        } else if (!_recvRemoteSet) {
          _pendingRecvCandidates.add(msg.candidate!);
        } else {
          await _recvPc!.addCandidate(RTCIceCandidate(
            msg.candidate!.candidate,
            msg.candidate!.sdpMid,
            msg.candidate!.sdpMLineIndex,
          ));
        }

      case 'talk_start':
        activeTalkerId = msg.userId;
        _setMemberTalking(msg.userId, true);
        _notify();

      case 'talk_stop':
        if (activeTalkerId == msg.userId) activeTalkerId = null;
        _setMemberTalking(msg.userId, false);
        _notify();

      case 'talk_busy':
        transmitting = false;
        await _cleanPublish();
        onBusy?.call();
        _notify();

      case 'error':
        onNotice?.call(msg.errorMessage ?? 'Erro do servidor');
        _notify();

      default:
        break;
    }
  }

  Future<void> _handleRecvOffer(String sdp) async {
    if (_recvPc == null) {
      _recvPc = await createPeerConnection(_iceConfig);
      _recvPc!.onIceCandidate = (c) {
        debugPrint('[RadioClient] recv local candidate: ${c.candidate}');
        _sendIce('receive', c);
      };
      _recvPc!.onIceGatheringState = (s) {
        debugPrint('[RadioClient] recv gathering -> $s');
      };
      _recvPc!.onTrack = (event) async {
        debugPrint('[RadioClient] track recebido: ${event.track.kind}');
        if (event.streams.isNotEmpty) {
          _remoteStream = event.streams.first;
        } else {
          _remoteStream ??= await createLocalMediaStream('remote-audio');
          await _remoteStream!.addTrack(event.track);
        }
        if (!kIsWeb) {
          unawaited(Helper.setSpeakerphoneOn(true).catchError((_) {}));
        }
        _notify();
      };
      _recvPc!.onConnectionState = (s) {
        debugPrint('[RadioClient] receive pc -> $s');
        _recvState = s;
        _notify();
      };
    }
    await _recvPc!.setRemoteDescription(RTCSessionDescription(sdp, 'offer'));
    _recvRemoteSet = true;
    final pending = List<WsIceCandidate>.of(_pendingRecvCandidates);
    _pendingRecvCandidates.clear();
    if (pending.isNotEmpty) {
      debugPrint('[RadioClient] aplicando ${pending.length} candidatos '
          'pendentes do receive');
    }
    for (final c in pending) {
      await _recvPc!.addCandidate(RTCIceCandidate(
        c.candidate,
        c.sdpMid,
        c.sdpMLineIndex,
      ));
    }
    final answer = await _recvPc!.createAnswer();
    await _recvPc!.setLocalDescription(answer);
    _send({'type': 'answer', 'target': 'receive', 'sdp': answer.sdp});
  }

  Future<bool> startTransmitting() async {
    if (transmitting || _publishPc != null) return true;
    if (_state != RadioConnState.connected) {
      onNotice?.call('Ainda não conectado ao canal');
      return false;
    }
    try {
      await _cleanPublish();
      _mic = await navigator.mediaDevices
          .getUserMedia({'audio': true, 'video': false});
      _publishPc = await createPeerConnection(_iceConfig);
      _publishPc!.onIceCandidate = (c) {
        debugPrint('[RadioClient] publish local candidate: ${c.candidate}');
        _sendIce('publish', c);
      };
      _publishPc!.onConnectionState = (s) {
        debugPrint('[RadioClient] publish pc -> $s');
        if (s == RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
            s == RTCPeerConnectionState.RTCPeerConnectionStateClosed) {
          if (transmitting) transmitting = false;
          _cleanPublish();
          _notify();
        }
      };
      for (final track in _mic!.getTracks()) {
        await _publishPc!.addTrack(track, _mic!);
      }
      final offer = await _publishPc!.createOffer();
      await _publishPc!.setLocalDescription(offer);
      _send({'type': 'offer', 'target': 'publish', 'sdp': offer.sdp});
      transmitting = true;
      _notify();
      return true;
    } catch (_) {
      transmitting = false;
      await _cleanPublish();
      onNotice?.call('Não foi possível acessar o microfone');
      _notify();
      return false;
    }
  }

  Future<void> stopTransmitting() async {
    if (!transmitting) return;
    transmitting = false;
    _send({'type': 'talk_stop'});
    await _cleanPublish();
    _notify();
  }

  Future<void> _cleanPublish() async {
    final mic = _mic;
    _mic = null;
    if (mic != null) {
      for (final t in mic.getTracks()) {
        await t.stop();
      }
      await mic.dispose();
    }
    final pc = _publishPc;
    _publishPc = null;
    if (pc != null) {
      await pc.close();
    }
  }

  Future<void> _onClosed() async {
    if (_disposed) return;
    _setState(RadioConnState.disconnected);
    if (kIsWeb &&
        baseUrl.contains('ngrok') &&
        !_webNgrokHintShown) {
      _webNgrokHintShown = true;
      onNotice?.call(
          'O plano free do ngrok bloqueia o WebSocket no navegador. '
          'Use o APK no celular (distância) ou o endereço local (testes).');
    }
    myUserId = null;
    members.clear();
    locations.clear();
    activeTalkerId = null;
    transmitting = false;
    await _cleanPublish();
    if (_recvPc != null) {
      await _recvPc!.close();
      _recvPc = null;
    }
    _recvRemoteSet = false;
    _pendingRecvCandidates.clear();
    _notify();
  }

  void sendLocation(double lat, double lng) {
    if (_state != RadioConnState.connected) return;
    _send({'type': 'location', 'lat': lat, 'lng': lng});
  }

  void _send(Map<String, dynamic> message) {
    try {
      _ws?.sink.add(jsonEncode(message));
    } catch (_) {}
  }

  void _sendIce(String target, RTCIceCandidate candidate) {
    _send({
      'type': 'ice',
      'target': target,
      'candidate': {
        'candidate': candidate.candidate,
        'sdpMid': candidate.sdpMid,
        'sdpMLineIndex': candidate.sdpMLineIndex,
      },
    });
  }

  void _setMemberTalking(String? userId, bool talking) {
    for (final m in members) {
      if (m.userId == userId) m.talking = talking;
    }
  }

  void _setState(RadioConnState value) => _state = value;

  void _notify() => onChanged?.call();

  Future<void> dispose() async {
    _disposed = true;
    try {
      _ws?.sink.close();
    } catch (_) {}
    await _sub?.cancel();
    await _cleanPublish();
    if (_recvPc != null) {
      await _recvPc!.close();
      _recvPc = null;
    }
    _recvRemoteSet = false;
    _pendingRecvCandidates.clear();
  }
}