import 'package:flutter/material.dart';

import '../theme/sd_colors.dart';
import '../theme/sd_typography.dart';

/// SpeedDex wordmark: "SPEED" in ivory, "DEX" in gold, speed-line underscore.
class SdWordmark extends StatelessWidget {
  const SdWordmark({super.key, this.size = 22});
  final double size;

  @override
  Widget build(BuildContext context) {
    final style = SdType.title.copyWith(fontSize: size, letterSpacing: size * 0.04);
    return Semantics(
      label: 'SpeedDex',
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text.rich(
            TextSpan(
              children: [
                TextSpan(text: 'SPEED', style: style),
                TextSpan(
                  text: 'DEX',
                  style: style.copyWith(color: SdColors.gold),
                ),
              ],
            ),
          ),
          SizedBox(height: size * 0.12),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(width: size * 2.4, height: 2, color: SdColors.signal),
              SizedBox(width: size * 0.15),
              Container(
                width: size * 0.7,
                height: 2,
                color: SdColors.signal.withValues(alpha: 0.6),
              ),
              SizedBox(width: size * 0.15),
              Container(
                width: size * 0.3,
                height: 2,
                color: SdColors.signal.withValues(alpha: 0.3),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Subtle diagonal pinstripe used behind hero areas.
class Pinstripe extends StatelessWidget {
  const Pinstripe({super.key, this.opacity = 0.035});
  final double opacity;

  @override
  Widget build(BuildContext context) =>
      CustomPaint(painter: _PinstripePainter(opacity), size: Size.infinite);
}

class _PinstripePainter extends CustomPainter {
  _PinstripePainter(this.opacity);
  final double opacity;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = Colors.white.withValues(alpha: opacity)
      ..strokeWidth = 1;
    for (double x = -size.height; x < size.width; x += 14) {
      canvas.drawLine(Offset(x, size.height), Offset(x + size.height, 0), p);
    }
  }

  @override
  bool shouldRepaint(covariant _PinstripePainter old) => old.opacity != opacity;
}
