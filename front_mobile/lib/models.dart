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

class WsIceCandidate {
  final String candidate;
  final String? sdpMid;
  final int? sdpMLineIndex;

  const WsIceCandidate({
    required this.candidate,
    this.sdpMid,
    this.sdpMLineIndex,
  });

  factory WsIceCandidate.fromJson(Map<String, dynamic> json) => WsIceCandidate(
        candidate: json['candidate'] as String? ?? '',
        sdpMid: json['sdpMid'] as String?,
        sdpMLineIndex: json['sdpMLineIndex'] as int?,
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
  bool talking;

  Member({required this.userId, required this.username, this.talking = false});

  factory Member.fromJson(Map<String, dynamic> json) => Member(
        userId: json['userId'] as String,
        username: json['username'] as String,
        talking: json['talking'] as bool? ?? false,
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
  final String? target;
  final String? sdp;
  final WsIceCandidate? candidate;
  final RoomInfo? room;
  final List<Member>? members;
  final List<MemberLocation>? locations;
  final String? userId;
  final String? username;
  final double? lat;
  final double? lng;
  final String? errorMessage;

  const WsMessage({
    required this.type,
    this.target,
    this.sdp,
    this.candidate,
    this.room,
    this.members,
    this.locations,
    this.userId,
    this.username,
    this.lat,
    this.lng,
    this.errorMessage,
  });

  factory WsMessage.fromJson(Map<String, dynamic> json) => WsMessage(
        type: json['type'] as String,
        target: json['target'] as String?,
        sdp: json['sdp'] as String?,
        candidate: json['candidate'] == null
            ? null
            : WsIceCandidate.fromJson(json['candidate'] as Map<String, dynamic>),
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
        userId: json['userId'] as String?,
        username: json['username'] as String?,
        lat: (json['lat'] as num?)?.toDouble(),
        lng: (json['lng'] as num?)?.toDouble(),
        errorMessage: json['message'] as String?,
      );
}