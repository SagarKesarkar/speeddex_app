import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';

/// Tilts [child] in 3D towards the finger, like holding a real card up to
/// the light: the touched side dips away, with perspective, and a soft light
/// follows the finger. On release it springs back flat.
///
/// Taps still reach the child (the unlock button, for example). Does nothing
/// when the system asks for reduced motion.
class TiltCard extends StatefulWidget {
  const TiltCard({
    super.key,
    required this.child,
    this.maxTilt = 8 * math.pi / 180,
    this.borderRadius = BorderRadius.zero,
  });

  final Widget child;

  /// Largest rotation, reached with the finger at an edge.
  final double maxTilt;

  /// Shape of the light overlay; match the card's corners.
  final BorderRadius borderRadius;

  @override
  State<TiltCard> createState() => _TiltCardState();
}

class _TiltCardState extends State<TiltCard> with SingleTickerProviderStateMixin {
  /// Where the finger is, from (-1, -1) top-left to (1, 1) bottom-right.
  Offset _pointer = Offset.zero;

  /// 1 while touched; springs to 0 (with a little overshoot) on release.
  late final AnimationController _hold = AnimationController.unbounded(vsync: this, value: 0)
    ..addListener(() => setState(() {}));

  static const _spring = SpringDescription(mass: 1, stiffness: 170, damping: 13);

  @override
  void dispose() {
    _hold.dispose();
    super.dispose();
  }

  void _track(Offset local, Size size) {
    if (size.isEmpty) return;
    setState(() {
      _pointer = Offset(
        (local.dx / size.width * 2 - 1).clamp(-1.0, 1.0),
        (local.dy / size.height * 2 - 1).clamp(-1.0, 1.0),
      );
    });
  }

  void _press(Offset local, Size size) {
    _track(local, size);
    _hold
      ..stop()
      ..animateTo(1, duration: const Duration(milliseconds: 140), curve: Curves.easeOut);
  }

  void _release() {
    HapticFeedback.selectionClick();
    _hold.animateWith(SpringSimulation(_spring, _hold.value, 0, _hold.velocity));
  }

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.of(context).disableAnimations) return widget.child;
    final t = _hold.value;
    // Pressing the right edge pushes it away: turn about the vertical axis
    // towards the finger, and about the horizontal axis likewise.
    final rotateY = -_pointer.dx * widget.maxTilt * t;
    final rotateX = _pointer.dy * widget.maxTilt * t;
    final glare = t.clamp(0.0, 1.0) * (0.10 + 0.12 * _pointer.distance.clamp(0.0, 1.0));

    return LayoutBuilder(
      builder: (context, constraints) {
        Size size() => context.size ?? constraints.biggest;
        // Raw pointer events follow the finger from the first touch. The pan
        // recogniser does nothing itself: it claims drags that start on the
        // card, so the page doesn't scroll while the card is being tilted.
        return Listener(
          onPointerDown: (e) => _press(e.localPosition, size()),
          onPointerMove: (e) => _track(e.localPosition, size()),
          onPointerUp: (_) => _release(),
          onPointerCancel: (_) => _release(),
          child: GestureDetector(
            onPanStart: (_) {},
            onPanUpdate: (_) {},
            child: Transform(
              alignment: Alignment.center,
              transform: Matrix4.identity()
                ..setEntry(3, 2, 0.001) // perspective
                ..rotateX(rotateX)
                ..rotateY(rotateY)
                ..scaleByDouble(1 + 0.01 * t, 1 + 0.01 * t, 1, 1),
              child: Stack(
                children: [
                  widget.child,
                  if (glare > 0.001)
                    Positioned.fill(
                      child: IgnorePointer(
                        child: ClipRRect(
                          borderRadius: widget.borderRadius,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: RadialGradient(
                                center: Alignment(_pointer.dx, _pointer.dy),
                                radius: 0.9,
                                colors: [
                                  Colors.white.withValues(alpha: glare),
                                  Colors.white.withValues(alpha: glare * 0.35),
                                  Colors.white.withValues(alpha: 0),
                                ],
                                stops: const [0, 0.35, 1],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
