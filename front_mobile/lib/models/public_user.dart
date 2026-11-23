/// Dados públicos de um usuário do Radio PX.
class PublicUser {
  final String id;
  final String username;
  final String? firstName;
  final String? lastName;
  final String? vehiclePlate;
  final String? phone;
  final String? avatar;

  const PublicUser({
    required this.id,
    required this.username,
    this.firstName,
    this.lastName,
    this.vehiclePlate,
    this.phone,
    this.avatar,
  });

  factory PublicUser.fromJson(Map<String, dynamic> json) => PublicUser(
    id: json['id'] as String,
    username: json['username'] as String,
    firstName: json['firstName'] as String?,
    lastName: json['lastName'] as String?,
    vehiclePlate: json['vehiclePlate'] as String?,
    phone: json['phone'] as String?,
    avatar: json['avatar'] as String?,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'username': username,
    'firstName': firstName,
    'lastName': lastName,
    'vehiclePlate': vehiclePlate,
    'phone': phone,
    'avatar': avatar,
  };

  @override
  bool operator ==(Object other) =>
      other is PublicUser &&
      other.id == id &&
      other.username == username &&
      other.firstName == firstName &&
      other.lastName == lastName &&
      other.vehiclePlate == vehiclePlate &&
      other.phone == phone &&
      other.avatar == avatar;

  @override
  int get hashCode => Object.hash(
    id,
    username,
    firstName,
    lastName,
    vehiclePlate,
    phone,
    avatar,
  );
}
