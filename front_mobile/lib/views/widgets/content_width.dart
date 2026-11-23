import 'package:flutter/material.dart';

/// Limita a largura do conteúdo em telas largas.
class ContentWidth extends StatelessWidget {
  const ContentWidth({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Center(
        heightFactor: 1,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: SizedBox(width: double.infinity, child: child),
        ),
      );
}
