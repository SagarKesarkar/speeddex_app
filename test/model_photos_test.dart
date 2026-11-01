import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:speeddex/app/providers.dart';
import 'package:speeddex/data/repositories.dart';
import 'package:speeddex/features/cards/presentation/model_photos.dart';

class _Cards implements CardsRepository {
  _Cards(this.photos);
  final List<ModelPhoto> photos;
  @override
  Future<List<ModelPhoto>> modelPhotos(String cardId) async => photos;
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

ModelPhoto _photo(String view) =>
    ModelPhoto(view: view, imageUrl: 'https://example.com/$view.jpg', credit: 'Press kit');

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  Future<void> pump(WidgetTester tester, List<ModelPhoto> photos) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [cardsRepositoryProvider.overrideWithValue(_Cards(photos))],
        child: const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: ModelPhotosStrip(cardId: '1', modelName: 'Maruti Suzuki Swift'),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('shows the photos in one row and opens them full screen', (tester) async {
    await pump(tester, [_photo('front'), _photo('left'), _photo('right'), _photo('rear')]);
    expect(find.text('PHOTOS'), findsOneWidget);
    for (final l in ['Front', 'Left side', 'Right side', 'Rear']) {
      expect(find.text(l), findsOneWidget);
    }
    final thumbs = find.bySemanticsLabel(RegExp(r'photo of the Maruti Suzuki Swift$'));
    expect(thumbs, findsNWidgets(4));
    // All in one row, the same size.
    final a = tester.getRect(thumbs.at(0));
    final c = tester.getRect(thumbs.at(3));
    expect(a.top, c.top);
    expect(a.size, c.size);

    await tester.tap(find.bySemanticsLabel('Left side photo of the Maruti Suzuki Swift'));
    await tester.pumpAndSettle();
    expect(find.text('2 / 4'), findsOneWidget);
    expect(find.text('Left side · Maruti Suzuki Swift'), findsOneWidget);
    expect(find.text('Photo: Press kit'), findsOneWidget);

    await tester.fling(find.byType(PageView), const Offset(-400, 0), 1000);
    await tester.pumpAndSettle();
    expect(find.text('3 / 4'), findsOneWidget);

    // A short, quick flick turns the page too (it used to be taken by the zoom).
    await tester.fling(find.byType(PageView), const Offset(-120, 0), 3000);
    await tester.pumpAndSettle();
    expect(find.text('4 / 4'), findsOneWidget);

    // Double-tap zooms; while zoomed, a drag pans instead of turning the page.
    final photo = find.byType(PageView);
    await tester.tap(photo);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(photo);
    await tester.pumpAndSettle();
    await tester.fling(photo, const Offset(400, 0), 1000);
    await tester.pumpAndSettle();
    expect(find.text('4 / 4'), findsOneWidget);
    // Double-tap again to zoom out; then swiping works again.
    await tester.tap(photo);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(photo);
    await tester.pumpAndSettle();
    await tester.fling(photo, const Offset(400, 0), 1000);
    await tester.pumpAndSettle();
    expect(find.text('3 / 4'), findsOneWidget);

    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    expect(find.byType(PageView), findsNothing);
  });

  testWidgets('locked photos show a lock and start the unlock, never a photo', (tester) async {
    var unlocks = 0;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          cardsRepositoryProvider.overrideWithValue(
            _Cards(const [
              ModelPhoto(view: 'front', imageUrl: null),
              ModelPhoto(view: 'rear', imageUrl: null),
            ]),
          ),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: ModelPhotosStrip(
                cardId: '1',
                modelName: 'Maruti Suzuki Swift',
                onUnlock: () => unlocks++,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(Image), findsNothing);
    expect(find.text('Front'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel(RegExp('^Rear photo, locked')));
    await tester.pumpAndSettle();
    expect(unlocks, 1);
    expect(find.byType(PageView), findsNothing);
  });

  testWidgets('shows nothing when the generation has no photos yet', (tester) async {
    await pump(tester, const []);
    expect(find.text('PHOTOS'), findsNothing);
  });
}
