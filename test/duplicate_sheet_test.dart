import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:speeddex/data/repositories.dart';
import 'package:speeddex/domain/car_card.dart';
import 'package:speeddex/domain/rarity_tier.dart';
import 'package:speeddex/features/scan/presentation/duplicate_sheet.dart';

CarCard _swift(String id, {String? color, int day = 1}) => CarCard(
  id: id,
  vehicleId: '3',
  serial: 'SDX-0000$id',
  make: 'Maruti Suzuki',
  model: 'Swift',
  yearLabel: '2023–present',
  category: 'Hatchback',
  origin: 'India',
  bodyStyle: BodyStyle.hatch,
  tier: RarityTier.base,
  specs: const VehicleSpecs(horsepower: 81),
  capture: CaptureFacts(color: color),
  ownedByViewer: true,
  capturedAt: DateTime(2026, 10, day),
);

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  Future<DuplicateChoice?> Function() open(WidgetTester tester, List<CarCard> copies) {
    DuplicateChoice? picked;
    var done = false;
    return () async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                picked = await showDuplicateSheet(context, candidate: _swift('9'), copies: copies);
                done = true;
              },
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      return done ? picked : null;
    };
  }

  Future<DuplicateChoice?> choose(WidgetTester tester, List<CarCard> copies, Finder tap) async {
    // A phone-sized screen, so the whole sheet fits.
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    DuplicateChoice? picked;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async =>
                picked = await showDuplicateSheet(context, candidate: _swift('9'), copies: copies),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(tap);
    await tester.tap(tap);
    await tester.pumpAndSettle();
    return picked;
  }

  final three = [
    _swift('1', color: 'white', day: 2),
    _swift('2', color: 'red', day: 5),
    _swift('3', day: 9),
  ];

  testWidgets('offers keep, a choice of copy to replace, and discard', (tester) async {
    await open(tester, three)();
    expect(find.text('ALREADY IN YOUR GARAGE'), findsOneWidget);
    expect(find.textContaining('3 cards of the Maruti Suzuki Swift'), findsOneWidget);
    expect(find.text('KEEP THIS ONE TOO'), findsOneWidget);
    expect(find.text('REPLACE'), findsNWidgets(3));
    expect(find.text('White'), findsOneWidget);
    expect(find.text('Red'), findsOneWidget);
    expect(find.textContaining('Caught'), findsNWidgets(3));
  });

  testWidgets('keeping both', (tester) async {
    expect(await choose(tester, three, find.text('KEEP THIS ONE TOO')), isA<KeepBoth>());
  });

  testWidgets('replacing the copy tapped', (tester) async {
    final c = await choose(tester, three, find.text('SDX-00002'));
    expect(c, isA<ReplaceCard>().having((r) => r.cardId, 'card', '2'));
  });

  testWidgets('discarding', (tester) async {
    expect(await choose(tester, three, find.text('DISCARD THIS PHOTO')), isA<DiscardScan>());
  });

  testWidgets('one copy reads naturally', (tester) async {
    await open(tester, [three.first])();
    expect(find.textContaining('You already have a Maruti Suzuki Swift'), findsOneWidget);
    expect(find.text('OR REPLACE THE PHOTO'), findsOneWidget);
  });

  test('older servers send only duplicateOf; it still offers that copy', () {
    final o = Identified(
      captureId: '1',
      candidate: _swift('9'),
      confidence: 0.9,
      duplicateOf: three.first,
    );
    expect(o.copies.map((c) => c.id), ['1']);
    expect(Identified(captureId: '1', candidate: _swift('9'), confidence: 0.9).copies, isEmpty);
  });
}
