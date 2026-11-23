/// Posição reportada por um participante do canal.
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
