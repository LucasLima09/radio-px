import 'package:flutter/material.dart';

const pxAccent = Color(0xFFB9B2FF);
const pxMuted = Color(0xFF999BA8);
const pxBorder = Color(0xFF2B2D36);

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

class PageHeading extends StatelessWidget {
  const PageHeading({super.key, required this.title, required this.subtitle});
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(
          fontSize: 30, fontWeight: FontWeight.w600, letterSpacing: -1,
          color: Color(0xFFF0F0F5), height: 1.2,
        )),
        const SizedBox(height: 10),
        Text(subtitle, style: const TextStyle(
          color: pxMuted, fontSize: 14, height: 1.5,
        )),
      ],
    );
  }
}

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
