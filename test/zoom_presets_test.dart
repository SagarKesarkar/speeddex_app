import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:speeddex/features/scan/presentation/zoom_presets.dart';

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  Future<List<double>> pump(
    WidgetTester tester, {
    required double max,
    required double zoom,
  }) async {
    final picked = <double>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ZoomPresets(min: 1, max: max, zoom: zoom, onSelect: picked.add),
        ),
      ),
    );
    return picked;
  }

  testWidgets('offers the presets the lens supports and zooms to the one tapped', (tester) async {
    final picked = await pump(tester, max: 8, zoom: 1);
    expect(find.text('1×'), findsOneWidget);
    expect(find.text('2×'), findsOneWidget);
    expect(find.text('5×'), findsOneWidget);
    await tester.tap(find.text('2×'));
    await tester.tap(find.text('5×'));
    expect(picked, [2, 5]);
  });

  testWidgets('hides presets beyond the lens and shows the pinched level', (tester) async {
    await pump(tester, max: 4, zoom: 2.6);
    expect(find.text('5×'), findsNothing);
    expect(find.text('2.6×'), findsOneWidget); // on the 2× button
    expect(find.text('1×'), findsOneWidget);
  });
}
