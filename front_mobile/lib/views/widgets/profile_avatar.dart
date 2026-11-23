import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

/// Decodifica o avatar (data URL) para bytes de imagem.
Uint8List? profilePhotoBytes(String? avatar) {
  if (avatar == null || avatar.isEmpty) return null;
  try {
    return base64Decode(avatar.split(',').last);
  } catch (_) {
    return null;
  }
}

/// Avatar do usuário: mostra a foto quando existe, senão a inicial do nome.
class ProfileAvatar extends StatelessWidget {
  const ProfileAvatar({
    super.key,
    required this.name,
    this.avatar,
    this.radius = 24,
  });

  final String name;
  final String? avatar;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final bytes = profilePhotoBytes(avatar);
    final fallback = Center(
      child: Text(
        name.trim().isEmpty ? '?' : name.trim().substring(0, 1).toUpperCase(),
        style: TextStyle(fontSize: radius * .7, fontWeight: FontWeight.w600),
      ),
    );
    return CircleAvatar(
      radius: radius,
      child: bytes == null
          ? fallback
          : ClipOval(
              child: Image.memory(
                bytes,
                width: radius * 2,
                height: radius * 2,
                fit: BoxFit.cover,
                errorBuilder: (_, error, stackTrace) => fallback,
              ),
            ),
    );
  }
}
