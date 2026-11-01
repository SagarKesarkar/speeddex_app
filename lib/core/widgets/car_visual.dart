import 'dart:io';

import 'package:flutter/material.dart';

import '../../domain/car_card.dart';
import '../../domain/rarity_tier.dart';
import '../theme/sd_colors.dart';

/// Shows the capture photo when one exists, otherwise a studio-lit vector
/// silhouette for the car's body style. No third-party car artwork is bundled.
class CarVisual extends StatelessWidget {
  const CarVisual({super.key, required this.card, this.fit = BoxFit.cover});

  final CarCard card;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    final fallback = CarSilhouette(body: card.bodyStyle, tier: card.tier);
    Widget image;
    if (card.imagePath != null) {
      image = Image.file(File(card.imagePath!), fit: fit, errorBuilder: (_, _, _) => fallback);
    } else if (card.imageUrl != null) {
      image = Image.network(
        card.imageUrl!,
        fit: fit,
        errorBuilder: (_, _, _) => fallback,
        loadingBuilder: (c, child, progress) => progress == null ? child : fallback,
      );
    } else {
      image = fallback;
    }
    return Semantics(image: true, label: 'Photo of ${card.displayName}', child: image);
  }
}

class CarSilhouette extends StatelessWidget {
  const CarSilhouette({super.key, required this.body, required this.tier});

  final BodyStyle body;
  final RarityTier tier;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: const Alignment(0, -0.2),
          radius: 1.1,
          colors: [
            Color.lerp(SdColors.surfaceHigh, tier.color, 0.22)!,
            SdColors.surface,
            SdColors.ink,
          ],
          stops: const [0, 0.65, 1],
        ),
      ),
      child: CustomPaint(painter: _CarPainter(body, tier), size: Size.infinite),
    );
  }
}

class _Shape {
  const _Shape(this.body, this.glass, this.frontWheel, this.rearWheel);
  final List<Offset> body;
  final List<Offset> glass;
  final double frontWheel;
  final double rearWheel;
}

List<Offset> _o(List<double> v) => [for (var i = 0; i < v.length; i += 2) Offset(v[i], v[i + 1])];

final _shapes = <BodyStyle, _Shape>{
  BodyStyle.coupe: _Shape(
    _o([
      .03,
      .80,
      .04,
      .57,
      .12,
      .51,
      .30,
      .45,
      .42,
      .26,
      .52,
      .22,
      .64,
      .24,
      .80,
      .41,
      .95,
      .47,
      .98,
      .58,
      .97,
      .80,
    ]),
    _o([.40, .42, .47, .29, .53, .265, .63, .28, .73, .42]),
    .20,
    .80,
  ),
  BodyStyle.sedan: _Shape(
    _o([
      .02,
      .80,
      .03,
      .55,
      .10,
      .50,
      .27,
      .46,
      .37,
      .28,
      .47,
      .23,
      .66,
      .23,
      .78,
      .42,
      .95,
      .46,
      .98,
      .56,
      .97,
      .80,
    ]),
    _o([.36, .44, .44, .30, .50, .27, .64, .27, .73, .44]),
    .20,
    .80,
  ),
  BodyStyle.hatch: _Shape(
    _o([
      .03,
      .80,
      .04,
      .55,
      .12,
      .49,
      .28,
      .45,
      .40,
      .25,
      .50,
      .21,
      .86,
      .22,
      .95,
      .40,
      .97,
      .56,
      .96,
      .80,
    ]),
    _o([.38, .43, .47, .29, .52, .26, .84, .27, .90, .43]),
    .21,
    .79,
  ),
  BodyStyle.suv: _Shape(
    _o([
      .02,
      .80,
      .03,
      .48,
      .10,
      .42,
      .25,
      .39,
      .34,
      .18,
      .42,
      .14,
      .90,
      .14,
      .95,
      .30,
      .97,
      .50,
      .96,
      .80,
    ]),
    _o([.32, .37, .40, .20, .45, .185, .88, .185, .92, .37]),
    .20,
    .80,
  ),
  BodyStyle.van: _Shape(
    _o([
      .02,
      .80,
      .03,
      .46,
      .08,
      .38,
      .22,
      .31,
      .32,
      .14,
      .40,
      .11,
      .92,
      .11,
      .96,
      .21,
      .97,
      .50,
      .96,
      .80,
    ]),
    _o([.30, .30, .38, .16, .43, .15, .90, .15, .93, .32]),
    .19,
    .81,
  ),
  BodyStyle.pickup: _Shape(
    _o([
      .02,
      .80,
      .03,
      .48,
      .10,
      .42,
      .26,
      .39,
      .34,
      .18,
      .40,
      .14,
      .56,
      .14,
      .58,
      .40,
      .97,
      .40,
      .98,
      .50,
      .96,
      .80,
    ]),
    _o([.33, .37, .39, .20, .43, .18, .54, .18, .55, .37]),
    .20,
    .81,
  ),
};

class _CarPainter extends CustomPainter {
  _CarPainter(this.style, this.tier);

  final BodyStyle style;
  final RarityTier tier;

  @override
  void paint(Canvas canvas, Size size) {
    // Fit a 2.4:1 car box inside the canvas with breathing room.
    final w = (size.width * 0.84).clamp(0.0, size.height * 0.62 * 2.4);
    final h = w / 2.4;
    final ox = (size.width - w) / 2;
    final oy = size.height * 0.5 - h * 0.55;
    Offset p(Offset n) => Offset(ox + n.dx * w, oy + n.dy * h);

    final shape = _shapes[style]!;
    final wheelR = h * 0.215;
    final wheelY = oy + h * 0.78;

    // Floor reflection + contact shadow.
    final floorY = wheelY + wheelR;
    canvas.drawLine(
      Offset(0, floorY + 1),
      Offset(size.width, floorY + 1),
      Paint()
        ..shader = LinearGradient(
          colors: [Colors.transparent, tier.color.withValues(alpha: 0.35), Colors.transparent],
        ).createShader(Rect.fromLTWH(0, floorY, size.width, 1))
        ..strokeWidth = 1,
    );
    canvas.drawOval(
      Rect.fromCenter(center: Offset(ox + w / 2, floorY), width: w * 0.95, height: h * 0.1),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.65)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
    );

    final body = Path()..addPolygon(shape.body.map(p).toList(), true);
    final arches = Path()
      ..addOval(
        Rect.fromCircle(center: Offset(ox + shape.frontWheel * w, wheelY), radius: wheelR * 1.14),
      )
      ..addOval(
        Rect.fromCircle(center: Offset(ox + shape.rearWheel * w, wheelY), radius: wheelR * 1.14),
      );
    final carved = Path.combine(PathOperation.difference, body, arches);

    final bounds = carved.getBounds();
    canvas.drawPath(
      carved,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color.lerp(tier.color, Colors.white, 0.18)!, tier.color, tier.deep],
          stops: const [0, 0.45, 1],
        ).createShader(bounds),
    );

    // Shoulder highlight.
    final y = oy + h * 0.5;
    canvas.save();
    canvas.clipPath(carved);
    canvas.drawRect(
      Rect.fromLTWH(ox, y, w, h * 0.025),
      Paint()..color = Colors.white.withValues(alpha: 0.22),
    );
    canvas.restore();

    final glass = Path()..addPolygon(shape.glass.map(p).toList(), true);
    canvas.drawPath(
      glass,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [const Color(0xFF3A4150), SdColors.ink],
        ).createShader(glass.getBounds()),
    );

    for (final x in [shape.frontWheel, shape.rearWheel]) {
      final c = Offset(ox + x * w, wheelY);
      canvas.drawCircle(c, wheelR, Paint()..color = const Color(0xFF07080A));
      canvas.drawCircle(
        c,
        wheelR * 0.62,
        Paint()
          ..shader = RadialGradient(colors: [const Color(0xFF9A9FA8), const Color(0xFF3B3F47)])
              .createShader(Rect.fromCircle(center: c, radius: wheelR * 0.62)),
      );
      canvas.drawCircle(c, wheelR * 0.2, Paint()..color = const Color(0xFF1A1C20));
    }
  }

  @override
  bool shouldRepaint(covariant _CarPainter old) => old.style != style || old.tier != tier;
}
