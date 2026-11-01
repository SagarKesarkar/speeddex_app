import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:speeddex/domain/car_card.dart';
import 'package:speeddex/domain/rarity_tier.dart';
import 'package:speeddex/features/cards/presentation/collector_card.dart';

CarCard _card({
  VehicleSpecs specs = const VehicleSpecs(),
  HiddenSpecs? hidden,
  bool owned = true,
}) => CarCard(
  id: '1',
  vehicleId: '1',
  serial: 'SDX-00001',
  make: 'Maruti Suzuki',
  model: 'Swift',
  variant: 'Fourth generation',
  yearLabel: '2023–present',
  category: 'Hatchback',
  origin: 'India/Japan',
  bodyStyle: BodyStyle.hatch,
  tier: RarityTier.base,
  specs: specs,
  hidden: hidden,
  hiddenUnlocked: hidden != null,
  ownedByViewer: owned,
  capturedAt: DateTime(2026, 10, 28),
);

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  Future<void> pump(WidgetTester tester, CarCard card) => tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: SizedBox(width: 360, child: CollectorCard(card: card)),
        ),
      ),
    ),
  );

  testWidgets('shows only the stats the catalogue has', (tester) async {
    await pump(
      tester,
      _card(specs: const VehicleSpecs(horsepower: 81, displacementCc: 1197, engine: '1.2 L I3')),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('HP'), findsOneWidget);
    expect(find.text('81'), findsOneWidget);
    expect(find.text('CC'), findsOneWidget);
    expect(find.text('1,197'), findsOneWidget);
    // No top speed or 0–60 in the source: no empty or zero bars for them.
    expect(find.textContaining('MPH'), findsNothing);
    expect(find.text('0–60'), findsNothing);
  });

  testWidgets('says so when no performance figures are published', (tester) async {
    await pump(tester, _card());
    expect(tester.takeException(), isNull);
    expect(find.text('Performance figures not published'), findsOneWidget);
  });

  testWidgets('marks missing spec-sheet values with a dash', (tester) async {
    await pump(tester, _card(hidden: const HiddenSpecs(curbWeightKg: 910, drivetrain: 'FWD')));
    expect(tester.takeException(), isNull);
    expect(find.text('910 kg'), findsOneWidget);
    expect(find.text('FWD'), findsOneWidget);
    expect(find.text('—'), findsWidgets); // engine, fuel, gearbox, length unknown
  });
}
