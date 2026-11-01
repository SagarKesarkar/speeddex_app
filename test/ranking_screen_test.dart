import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:speeddex/app/providers.dart';
import 'package:speeddex/data/repositories.dart';
import 'package:speeddex/domain/profile.dart';
import 'package:speeddex/domain/social.dart';
import 'package:speeddex/features/ranking/presentation/ranking_screen.dart';

class _Ranking implements RankingRepository {
  _Ranking(this.entries);
  final List<LeaderboardEntry> entries;

  @override
  Future<LeaderboardPage> fetch(LeaderboardScope scope, LeaderboardPeriod period) async =>
      LeaderboardPage(entries: entries, viewer: entries.where((e) => e.isViewer).firstOrNull);
}

LeaderboardEntry _e(int rank, String handle, int xp, {bool viewer = false}) => LeaderboardEntry(
  rank: rank,
  user: UserSummary(id: '$rank', handle: handle, displayName: handle, level: 1),
  xp: xp,
  carCount: 1,
  isViewer: viewer,
);

class _NoWallet implements ProfileRepository {
  @override
  Future<Wallet> wallet() async => const Wallet(coins: 0, adsWatchedToday: 0);
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  Future<void> pump(WidgetTester tester, List<LeaderboardEntry> entries) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          rankingRepositoryProvider.overrideWithValue(_Ranking(entries)),
          profileRepositoryProvider.overrideWithValue(_NoWallet()),
        ],
        child: const MaterialApp(home: Scaffold(body: RankingScreen())),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('shows every spotter when there are too few for a podium', (tester) async {
    // Regression: with fewer than 3 entries, ranks 1–2 were never rendered.
    await pump(tester, [_e(1, 'meera', 2200), _e(2, 'apex', 1300, viewer: true)]);
    expect(find.text('@meera'), findsOneWidget);
    expect(find.text('@apex'), findsWidgets); // list row + pinned viewer bar
    expect(tester.takeException(), isNull);
  });

  testWidgets('shows an empty state when nobody has XP yet', (tester) async {
    await pump(tester, const []);
    expect(find.text('NO RANKINGS YET'), findsOneWidget);
  });
}
