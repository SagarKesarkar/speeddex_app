import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:speeddex/core/widgets/sd_button.dart';

void main() {
  // Tests run offline; fall back to the default font instead of fetching.
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  Future<void> pump(WidgetTester tester, Widget child) => tester.pumpWidget(
    MaterialApp(
      home: Scaffold(body: SizedBox(width: 360, child: child)),
    ),
  );

  testWidgets('a non-expanding SdButton hugs its label inside a ListTile', (tester) async {
    // Regression: an aligned Container expanded to fill the trailing slot,
    // which ListTile rejects and which blanked the whole Garage screen.
    await pump(
      tester,
      ListTile(
        title: const Text('Porsche 911 GT3'),
        trailing: SdButton(label: 'Review', compact: true, expand: false, onPressed: () {}),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(tester.getSize(find.byType(SdButton)).width, lessThan(200));
  });

  testWidgets('an expanding SdButton fills its parent and reports semantics', (tester) async {
    var taps = 0;
    await pump(tester, SdButton(label: 'Add to Garage', onPressed: () => taps++));
    expect(tester.getSize(find.byType(SdButton)).width, 360);
    await tester.tap(find.byType(SdButton));
    expect(taps, 1);
    expect(find.bySemanticsLabel('Add to Garage'), findsOneWidget);
  });

  testWidgets('a disabled SdButton ignores taps', (tester) async {
    await pump(tester, const SdButton(label: 'Store · not available yet', onPressed: null));
    await tester.tap(find.byType(SdButton));
    expect(tester.takeException(), isNull);
  });
}
