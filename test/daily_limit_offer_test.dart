import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:speeddex/features/scan/presentation/daily_limit_offer.dart';

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  Future<void> pump(WidgetTester tester, Widget offer) => tester.pumpWidget(
    MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: offer)),
    ),
  );

  testWidgets('explains the limit and offers Premium and a rewarded ad', (tester) async {
    await pump(tester, const DailyLimitOffer(limit: 5));
    expect(find.text('OH NO!'), findsOneWidget);
    expect(find.text('DAILY LIMIT REACHED'), findsOneWidget);
    expect(find.textContaining('added 5 cars today'), findsOneWidget);
    expect(find.textContaining('Get SpeedDex Pro or watch a rewarded ad'), findsOneWidget);

    // Neither exists yet, so tapping says so rather than pretending to work.
    await tester.tap(find.text('GET SPEEDDEX PRO'));
    await tester.pump();
    expect(find.text('SpeedDex Pro isn’t available yet. It’s coming soon.'), findsOneWidget);
  });

  testWidgets('hands both choices to the callers once they exist', (tester) async {
    final taps = <String>[];
    await pump(
      tester,
      DailyLimitOffer(onPremium: () => taps.add('premium'), onWatchAd: () async => taps.add('ad')),
    );
    await tester.tap(find.text('GET SPEEDDEX PRO'));
    await tester.tap(find.text('WATCH REWARD AD · +1 SCAN'));
    expect(taps, ['premium', 'ad']);
    await tester.pump();
    expect(find.textContaining('coming soon'), findsNothing);
  });

  testWidgets('shows how many ad scans are left, and disables the ad once they are used', (
    tester,
  ) async {
    var watched = 0;
    await pump(tester, DailyLimitOffer(limit: 5, adScansLeft: 2, onWatchAd: () async => watched++));
    expect(find.text('WATCH REWARD AD · +1 SCAN (2 LEFT)'), findsOneWidget);

    await pump(tester, DailyLimitOffer(limit: 5, adScansLeft: 0, onWatchAd: () async => watched++));
    expect(find.text('NO MORE AD SCANS TODAY'), findsOneWidget);
    await tester.tap(find.text('NO MORE AD SCANS TODAY'));
    await tester.pump();
    expect(watched, 0, reason: 'no ad is shown that could not pay out');
    expect(find.textContaining('used all of today’s extra scans from ads'), findsOneWidget);
  });
}
