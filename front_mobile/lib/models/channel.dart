/// Canal de rádio onde as pessoas se encontram para conversar.
class Channel {
  final String id;
  final String name;
  final bool isPrivate;
  final String ownerId;
  final int members;
  final int online;

  const Channel({
    required this.id,
    required this.name,
    required this.isPrivate,
    required this.ownerId,
    required this.members,
    this.online = 0,
  });

  factory Channel.fromJson(Map<String, dynamic> json) => Channel(
        id: json['id'] as String,
        name: json['name'] as String,
        isPrivate: json['isPrivate'] as bool,
        ownerId: json['ownerId'] as String,
        members: json['members'] as int,
        online: json['online'] as int? ?? 0,
      );
}
