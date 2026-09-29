class PublicUser {
  final String id;
  final String username;

  const PublicUser({required this.id, required this.username});

  factory PublicUser.fromJson(Map<String, dynamic> json) => PublicUser(
        id: json['id'] as String,
        username: json['username'] as String,
      );

  Map<String, dynamic> toJson() => {'id': id, 'username': username};

  @override
  bool operator ==(Object other) =>
      other is PublicUser && other.id == id && other.username == username;

  @override
  int get hashCode => Object.hash(id, username);
}

class AuthSession {
  final String accessToken;
  final String refreshToken;
  final int expiresAt;
  final PublicUser user;

  const AuthSession({
    required this.accessToken,
    required this.refreshToken,
    required this.expiresAt,
    required this.user,
  });

  factory AuthSession.fromJson(Map<String, dynamic> json) => AuthSession(
        accessToken: json['accessToken'] as String,
        refreshToken: json['refreshToken'] as String,
        expiresAt: json['expiresAt'] as int,
        user: PublicUser.fromJson(json['user'] as Map<String, dynamic>),
      );

  Map<String, dynamic> toJson() => {
        'accessToken': accessToken,
        'refreshToken': refreshToken,
        'expiresAt': expiresAt,
        'user': user.toJson(),
      };
}

class Channel {
  final String id;
  final String name;
  final bool isPrivate;
  final String ownerId;
  final int members;

  const Channel({
    required this.id,
    required this.name,
    required this.isPrivate,
    required this.ownerId,
    required this.members,
  });

  factory Channel.fromJson(Map<String, dynamic> json) => Channel(
        id: json['id'] as String,
        name: json['name'] as String,
        isPrivate: json['isPrivate'] as bool,
        ownerId: json['ownerId'] as String,
        members: json['members'] as int,
      );
}

class RoomInfo {
  final String id;
  final String name;

  const RoomInfo({required this.id, required this.name});

  factory RoomInfo.fromJson(Map<String, dynamic> json) => RoomInfo(
        id: json['id'] as String,
        name: json['name'] as String,
      );
}

class Member {
  final String userId;
  final String username;
  bool recording;

  Member({
    required this.userId,
    required this.username,
    this.recording = false,
  });

  factory Member.fromJson(Map<String, dynamic> json) => Member(
        userId: json['userId'] as String,
        username: json['username'] as String,
        recording: json['recording'] as bool? ?? false,
      );
}

/// Metadata of an audio clip received from the queue. The binary payload
/// arrives right after the `clip_new` message that carries this metadata.
class AudioClip {
  final String clipId;
  final String userId;
  final String username;
  final String mime;
  final int durationMs;
  final int seq;
  final int size;

  const AudioClip({
    required this.clipId,
    required this.userId,
    required this.username,
    required this.mime,
    required this.durationMs,
    required this.seq,
    required this.size,
  });

  factory AudioClip.fromJson(Map<String, dynamic> json) => AudioClip(
        clipId: json['clipId'] as String,
        userId: json['userId'] as String,
        username: json['username'] as String? ?? '',
        mime: json['mime'] as String? ?? 'audio/mp4',
        durationMs: (json['durationMs'] as num?)?.toInt() ?? 0,
        seq: (json['seq'] as num?)?.toInt() ?? 0,
        size: (json['size'] as num?)?.toInt() ?? 0,
      );
}

class MemberLocation {
  final String userId;
  final String username;
  final double lat;
  final double lng;

  const MemberLocation({
    required this.userId,
    required this.username,
    required this.lat,
    required this.lng,
  });

  factory MemberLocation.fromJson(Map<String, dynamic> json) => MemberLocation(
        userId: json['userId'] as String,
        username: json['username'] as String? ?? '',
        lat: (json['lat'] as num).toDouble(),
        lng: (json['lng'] as num).toDouble(),
      );

  @override
  bool operator ==(Object other) =>
      other is MemberLocation &&
      other.userId == userId &&
      other.lat == lat &&
      other.lng == lng;

  @override
  int get hashCode => Object.hash(userId, lat, lng);
}

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