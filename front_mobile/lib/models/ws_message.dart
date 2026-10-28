import 'audio_clip.dart';
import 'member.dart';
import 'member_location.dart';
import 'room_info.dart';

/// Mensagem recebida do servidor no WebSocket do canal.
class WsMessage {
  final String type;
  final RoomInfo? room;
  final List<Member>? members;
  final List<MemberLocation>? locations;
  final AudioClip? clip;
  final String? userId;
  final String? username;
  final double? lat;
  final double? lng;
  final String? errorMessage;

  const WsMessage({
    required this.type,
    this.room,
    this.members,
    this.locations,
    this.clip,
    this.userId,
    this.username,
    this.lat,
    this.lng,
    this.errorMessage,
  });

  factory WsMessage.fromJson(Map<String, dynamic> json) => WsMessage(
        type: json['type'] as String,
        room: json['room'] == null
            ? null
            : RoomInfo.fromJson(json['room'] as Map<String, dynamic>),
        members: json['members'] == null
            ? null
            : (json['members'] as List)
                .map((e) => Member.fromJson(e as Map<String, dynamic>))
                .toList(),
        locations: json['locations'] == null
            ? null
            : (json['locations'] as List)
                .map((e) => MemberLocation.fromJson(e as Map<String, dynamic>))
                .toList(),
        clip: json['clip'] == null
            ? null
            : AudioClip.fromJson(json['clip'] as Map<String, dynamic>),
        userId: json['userId'] as String?,
        username: json['username'] as String?,
        lat: (json['lat'] as num?)?.toDouble(),
        lng: (json['lng'] as num?)?.toDouble(),
        errorMessage: json['message'] as String?,
      );
}
