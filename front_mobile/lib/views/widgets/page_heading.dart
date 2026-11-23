import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';

/// Título e subtítulo no topo das telas de entrada.
class PageHeading extends StatelessWidget {
  const PageHeading({super.key, required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 30,
            fontWeight: FontWeight.w600,
            letterSpacing: -1,
            color: pxText,
            height: 1.2,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          subtitle,
          style: const TextStyle(
            color: pxMuted,
            fontSize: 14,
            height: 1.5,
          ),
        ),
      ],
    );
  }
}
