import 'package:flutter/material.dart';

/// The SpeedDex logo: gauge, car and wordmark, drawn for dark backgrounds.
/// Sized by height (headers) or width (splash). The image is
/// `assets/brand/logo.png`, made by tool/brand_assets.dart.
class SdLogo extends StatelessWidget {
  const SdLogo({super.key, this.height, this.width});
  final double? height;
  final double? width;

  /// Width / height of the logo image.
  static const aspect = 1000 / 404;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'SpeedDex',
      image: true,
      excludeSemantics: true,
      child: Image.asset(
        'assets/brand/logo.png',
        height: height,
        width: width,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.medium,
        // Decoded at the size it's shown, not the full 1000 px.
        cacheWidth: ((width ?? (height ?? 40) * aspect) * MediaQuery.devicePixelRatioOf(context))
            .round(),
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
