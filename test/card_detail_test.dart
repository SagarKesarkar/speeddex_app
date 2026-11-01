import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:speeddex/app/providers.dart';
import 'package:speeddex/data/repositories.dart';
import 'package:speeddex/domain/car_card.dart';
import 'package:speeddex/domain/rarity_tier.dart';
import 'package:speeddex/features/cards/application/share_card.dart';
import 'package:speeddex/features/cards/presentation/card_detail_screen.dart';

CarCard _card({required bool owned, bool unlocked = false}) => CarCard(
  id: '2',
  vehicleId: '2',
  serial: 'SDX-00002',
  make: 'Lamborghini',
  model: 'Aventador',
  variant: 'Lamborghini Aventador',
  yearLabel: '2011–2022',
  category: 'Supercar',
  origin: 'Italy',
  bodyStyle: BodyStyle.coupe,
  tier: RarityTier.elite,
  specs: const VehicleSpecs(horsepower: 769),
  hidden: owned || unlocked
      ? const HiddenSpecs(
          drivetrain: 'AWD',
          manufacturer: 'Automobili Lamborghini S.p.A.',
          productionStatus: 'Discontinued',
          cylinders: 12,
        )
      : null,
  capture: owned || unlocked ? const CaptureFacts(color: 'Verde Mantis', aiConfidence: 0.91) : null,
  hiddenUnlocked: unlocked,
  ownedByViewer: owned,
  capturedAt: DateTime(2026, 10, 28),
  locationLabel: 'Pune, India',
);

class _Cards implements CardsRepository {
  _Cards(this.card);
  final CarCard card;
  @override
  Future<List<ModelPhoto>> modelPhotos(String cardId) async => const [];
  @override
  Future<CarCard> detail(String cardId) async => card;
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  Future<void> pump(WidgetTester tester, CarCard card) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [cardsRepositoryProvider.overrideWithValue(_Cards(card))],
        child: const MaterialApp(home: CardDetailScreen(cardId: '2')),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets("hides another spotter's capture record until it is unlocked", (tester) async {
    await pump(tester, _card(owned: false));
    expect(find.text('CAPTURE RECORD'), findsNothing);
    expect(find.text('Pune, India'), findsNothing);
    // The header no longer carries the "#00002" number.
    expect(find.text('#00002'), findsNothing);

    await pump(tester, _card(owned: false, unlocked: true));
    await tester.scrollUntilVisible(find.text('LOCATION'), 200);
    expect(find.text('Pune, India'), findsOneWidget);
  });

  testWidgets('shows the owner their capture record, without a repeated name', (tester) async {
    await pump(tester, _card(owned: true));
    await tester.scrollUntilVisible(find.text('VEHICLE'), 200);
    expect(find.text('Lamborghini Aventador'), findsOneWidget);
  });

  test('lists every detail the catalogue and capture have, and nothing it lacks', () {
    final card = _card(owned: true);
    final capture = {for (final (l, v, _) in captureRows(card)) l: v};
    expect(capture['Colour'], 'Verde Mantis');
    expect(capture['AI match'], '91%');
    expect(capture['Location'], 'Pune, India');
    final vehicle = {for (final (l, v, _) in vehicleRows(card)) l: v};
    expect(vehicle['Manufacturer'], 'Automobili Lamborghini S.p.A.');
    expect(vehicle['Status'], 'Discontinued');
    expect(vehicle['Cylinders'], '12');
    expect(vehicle['Power'], '769 hp');
    expect(vehicle['Drive'], 'AWD');
    expect(vehicle['Rarity'], 'Elite');
    // Figures the catalogue lacks are left out, not shown as 0 or "—".
    expect(vehicle.containsKey('Top speed'), isFalse);
    expect(vehicle.containsKey('Kerb weight'), isFalse);
  });

  testWidgets('offers Share at the end of your own card only', (tester) async {
    await pump(tester, _card(owned: true));
    await tester.scrollUntilVisible(find.byType(ShareCardButton), 300);
    expect(find.byType(ShareCardButton), findsOneWidget);

    await pump(tester, _card(owned: false, unlocked: true));
    await tester.drag(find.byType(ListView), const Offset(0, -5000));
    await tester.pumpAndSettle();
    expect(find.byType(ShareCardButton), findsNothing);
  });

  test('share text names the car without location or owner details', () {
    final text = shareTextFor(_card(owned: true));
    expect(text, contains('Lamborghini Aventador'));
    expect(text, isNot(contains('Pune')));
  });
}
