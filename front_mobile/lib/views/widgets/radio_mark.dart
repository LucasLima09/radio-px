import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';

/// Marca do app: as barras de equalizador.
class RadioMark extends StatelessWidget {
  const RadioMark({super.key, this.size = 44});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: const Color(0xFF22212F),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF39354F)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (final height in [10.0, 20.0, 28.0, 20.0, 10.0])
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 1.5),
              width: 3,
              height: height * size / 44,
              decoration: BoxDecoration(
                color: pxAccent,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
        ],
      ),
    );
  }
}
