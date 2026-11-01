import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:speeddex/core/widgets/tilt_card.dart';

void main() {
  Future<void> pump(WidgetTester tester, {bool reduceMotion = false, VoidCallback? onTap}) =>
      tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(disableAnimations: reduceMotion),
            child: Center(
              child: SizedBox(
                width: 300,
                height: 420,
                child: TiltCard(
                  child: GestureDetector(
                    onTap: onTap,
                    child: const ColoredBox(color: Colors.blue, child: SizedBox.expand()),
                  ),
                ),
              ),
            ),
          ),
        ),
      );

  Matrix4 transform(WidgetTester tester) => tester
      .widget<Transform>(
        find.descendant(of: find.byType(TiltCard), matching: find.byType(Transform)),
      )
      .transform;

  bool flat(Matrix4 m) {
    // No rotation left: the x and y axes are unturned (perspective aside).
    final r = Matrix4.copy(m)..setEntry(3, 2, 0);
    return (r.entry(0, 2)).abs() < 1e-3 &&
        (r.entry(1, 2)).abs() < 1e-3 &&
        (r.entry(2, 0)).abs() < 1e-3;
  }

  testWidgets('tilts towards the finger while dragging, then springs back flat', (tester) async {
    await pump(tester);
    expect(flat(transform(tester)), isTrue);

    final card = tester.getRect(find.byType(TiltCard));
    final g = await tester.startGesture(card.bottomRight - const Offset(20, 20));
    await g.moveBy(const Offset(-5, -5));
    await tester.pump(); // starts the press animation
    await tester.pump(const Duration(milliseconds: 200));
    final tilted = transform(tester);
    expect(flat(tilted), isFalse);
    // A light follows the finger while touched.
    final light = find.byWidgetPredicate(
      (w) =>
          w is DecoratedBox &&
          w.decoration is BoxDecoration &&
          (w.decoration as BoxDecoration).gradient is RadialGradient,
    );
    expect(light, findsOneWidget);

    await g.up();
    await tester.pumpAndSettle();
    expect(flat(transform(tester)), isTrue);
    expect(light, findsNothing);
  });

  testWidgets('taps still reach the card', (tester) async {
    var taps = 0;
    await pump(tester, onTap: () => taps++);
    await tester.tap(find.byType(TiltCard));
    await tester.pumpAndSettle();
    expect(taps, 1);
  });

  testWidgets('stays still when the system asks for reduced motion', (tester) async {
    await pump(tester, reduceMotion: true);
    expect(
      find.descendant(of: find.byType(TiltCard), matching: find.byType(Transform)),
      findsNothing,
    );
  });
}
