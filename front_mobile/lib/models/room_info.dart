/// Identificação da sala aberta no WebSocket.
class RoomInfo {
  final String id;
  final String name;

  const RoomInfo({required this.id, required this.name});

  factory RoomInfo.fromJson(Map<String, dynamic> json) => RoomInfo(
        id: json['id'] as String,
        name: json['name'] as String,
      );
}
