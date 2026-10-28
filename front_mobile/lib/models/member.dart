/// Participante conectado ao canal.
///
/// [recording] é mutável de propósito: o servidor avisa quem começou e quem
/// parou de gravar, e a lista é a mesma exibida na tela.
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
