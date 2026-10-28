import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';

/// Botão de falar: pressionar e soltar (ou tocar) para gravar.
class RecordButton extends StatelessWidget {
  const RecordButton({
    super.key,
    required this.connected,
    required this.active,
    required this.label,
    required this.onPressed,
    required this.onReleased,
  });

  final bool connected;

  /// Verdadeiro enquanto a gravação está em andamento.
  final bool active;

  final String label;
  final VoidCallback onPressed;
  final VoidCallback onReleased;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Listener(
        onPointerDown: connected ? (_) => onPressed() : null,
        onPointerUp: connected ? (_) => onReleased() : null,
        onPointerCancel: connected ? (_) => onReleased() : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          width: 144,
          height: 144,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: active
                ? const Color(0xFF9B4540)
                : connected
                    ? pxAccent
                    : const Color(0xFF25282C),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                active ? Icons.mic : Icons.mic_none,
                size: 36,
                color: connected && !active ? pxOnAccent : Colors.white,
              ),
              const SizedBox(height: 8),
              Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: connected && !active ? pxOnAccent : Colors.white,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
