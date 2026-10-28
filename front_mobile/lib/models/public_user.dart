/// Dados públicos de um usuário do Radio PX.
class PublicUser {
  final String id;
  final String username;
  final String? avatar;

  const PublicUser({required this.id, required this.username, this.avatar});

  factory PublicUser.fromJson(Map<String, dynamic> json) => PublicUser(
    id: json['id'] as String,
    username: json['username'] as String,
    avatar: json['avatar'] as String?,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'username': username,
    'avatar': avatar,
  };

  @override
  bool operator ==(Object other) =>
      other is PublicUser &&
      other.id == id &&
      other.username == username &&
      other.avatar == avatar;

  @override
  int get hashCode => Object.hash(id, username, avatar);
}
