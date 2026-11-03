import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';
import 'package:speeddex/app/providers.dart';
import 'package:speeddex/core/push/push_service.dart';
import 'package:speeddex/data/api/json_mappers.dart';
import 'package:speeddex/dev/dev_fixtures.dart';
import 'package:speeddex/domain/car_card.dart';
import 'package:speeddex/features/cards/presentation/card_grid_tile.dart';
import 'package:speeddex/data/repositories.dart';
import 'package:speeddex/domain/goals.dart';
import 'package:speeddex/domain/profile.dart';
import 'package:speeddex/domain/social.dart';
import 'package:speeddex/features/feed/presentation/feed_sheets.dart';
import 'package:speeddex/features/profile/presentation/badge_case.dart';
import 'package:speeddex/features/profile/presentation/daily_goals_panel.dart';

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  Future<void> pump(WidgetTester tester, Widget child, {List<Object> overrides = const []}) =>
      tester.pumpWidget(
        ProviderScope(
          overrides: overrides.cast(),
          child: MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(child: SizedBox(width: 360, child: child)),
            ),
          ),
        ),
      );

  group('badge case', () {
    final badges = [
      SpotterBadge(
        id: 'first_catch',
        name: 'First Catch',
        description: 'Catch your first car.',
        icon: 'camera',
        earnedAt: DateTime(2026, 10, 21),
      ),
      const SpotterBadge(
        id: 'collector_10',
        name: 'Collector',
        description: 'Have 10 cars in your Garage.',
        icon: 'collection',
        earned: false,
        progress: 6,
        target: 10,
      ),
    ];

    testWidgets('shows earned and locked badges, and explains one when tapped', (tester) async {
      await pump(tester, BadgeCase(badges: badges));
      expect(tester.takeException(), isNull);
      expect(find.text('FIRST CATCH'), findsOneWidget);
      expect(find.text('6 / 10'), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('Collector badge, locked, 6 of 10')), findsOneWidget);

      await tester.tap(find.text('COLLECTOR'));
      await tester.pumpAndSettle();
      expect(find.text('Have 10 cars in your Garage.'), findsOneWidget);
      expect(find.text('6 of 10'), findsOneWidget);
    });

    testWidgets('earned and locked badges both open a full-width sheet', (tester) async {
      await pump(tester, BadgeCase(badges: badges));
      final screen = tester.view.physicalSize.width / tester.view.devicePixelRatio;
      for (final name in ['FIRST CATCH', 'COLLECTOR']) {
        await tester.tap(find.text(name));
        await tester.pumpAndSettle();
        expect(tester.getSize(find.byType(BottomSheet)).width, screen, reason: name);
        Navigator.of(tester.element(find.byType(BottomSheet))).pop();
        await tester.pumpAndSettle();
      }
    });

    testWidgets('says how to earn the first one when there are none', (tester) async {
      await pump(tester, const BadgeCase(badges: []));
      expect(find.textContaining('first catch earns one'), findsOneWidget);
    });
  });

  testWidgets('daily goals show progress, XP and what is done', (tester) async {
    final goals = DailyGoals(
      goals: const [
        DailyGoal(
          id: 'catch',
          title: 'Catch a car',
          description: '',
          progress: 1,
          target: 1,
          xp: 25,
          completed: true,
        ),
        DailyGoal(
          id: 'like',
          title: 'Like 3 catches',
          description: '',
          progress: 2,
          target: 3,
          xp: 10,
          completed: false,
        ),
      ],
      bonusTitle: 'Complete every goal',
      bonusXp: 25,
      bonusCompleted: false,
      xpEarnedToday: 25,
      resetsAt: DateTime.now().add(const Duration(hours: 3, minutes: 5)),
    );
    await pump(
      tester,
      const DailyGoalsPanel(),
      overrides: [dailyGoalsProvider.overrideWith((_) async => goals)],
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('1 of 2 done'), findsOneWidget);
    expect(find.text('2 / 3'), findsOneWidget);
    expect(find.text('25 of 60 XP earned today.'), findsOneWidget);
    expect(find.textContaining('New goals in 3h'), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('Catch a car, 25 XP, done')), findsOneWidget);
  });

  testWidgets('a grid card reveals its likes and comments, and they open the post', (tester) async {
    final opened = <String>[];
    final card = DevFixtures.byId('101')
        .copyWith(post: const PostStats(postId: '31', likeCount: 4, commentCount: 2));
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => Scaffold(
            body: Center(
              child: SizedBox(
                width: 160,
                height: 160 / cardGridAspect,
                child: CardGridTile(card: card),
              ),
            ),
          ),
        ),
        GoRoute(
          path: '/post/:id',
          builder: (_, s) {
            opened.add(s.pathParameters['id']!);
            return const SizedBox();
          },
        ),
      ],
    );
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    expect(tester.takeException(), isNull);
    // Folded away at first: a tab reveals the counts.
    expect(find.text('4'), findsNothing);
    await tester.tap(find.bySemanticsLabel('Show likes and comments'));
    await tester.pumpAndSettle();
    expect(find.text('4'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    // The arrow at the end folds it away again.
    await tester.tap(find.bySemanticsLabel('Hide likes and comments'));
    await tester.pumpAndSettle();
    expect(find.text('4'), findsNothing);
    await tester.tap(find.bySemanticsLabel('Show likes and comments'));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel(RegExp('4 likes, 2 comments')));
    await tester.pumpAndSettle();
    expect(opened, ['31']);
  });

  testWidgets('a new comment shows once, even if the reloaded list has it', (tester) async {
    final repo = _SharedListComments();
    const author = UserSummary(id: '1', handle: 'apex', displayName: 'Apex', level: 1);
    final post = FeedPost(
      id: '9',
      author: author,
      card: DevFixtures.byId('101'),
      likeCount: 0,
      commentCount: 0,
      viewerHasLiked: false,
      createdAt: DateTime(2026),
    );
    await pump(
      tester,
      SizedBox(height: 500, child: CommentsThread(post: post)),
      overrides: [feedRepositoryProvider.overrideWithValue(repo)],
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Clean spot');
    await tester.tap(find.byTooltip('Send comment'));
    await tester.pumpAndSettle();
    expect(find.text('Clean spot'), findsOneWidget);
  });

  test('maps badges and goals from the API', () {
    const m = ApiMappers(_identity);
    final g = m.dailyGoals({
      'date': '2026-11-02',
      'resetsAt': '2026-11-03T00:00:00.000Z',
      'goals': [
        {
          'goalId': 'like',
          'title': 'Like 3 catches',
          'description': 'd',
          'progress': 2,
          'target': 3,
          'xp': 10,
          'completed': false,
        },
      ],
      'bonus': {'goalId': 'all', 'title': 'Complete every goal', 'xp': 25, 'completed': false},
      'xpEarnedToday': 0,
    });
    expect(g.goals.single.fraction, closeTo(2 / 3, 0.001));
    expect(g.xpAvailable, 35);
  });

  test('a push can only open screens the app has', () {
    expect(PushService.safeRoute('/card/12'), '/card/12');
    expect(PushService.safeRoute('/user/7'), '/user/7');
    expect(PushService.safeRoute('/post/31'), '/post/31');
    expect(PushService.safeRoute('/profile'), '/profile');
    expect(PushService.safeRoute('/settings/delete-account'), isNull);
    expect(PushService.safeRoute('https://evil.example'), isNull);
    expect(PushService.safeRoute('/card/12/../../x'), isNull);
    expect(PushService.safeRoute(null), isNull);
  });

  test('a completed goal is a reward; other notifications are not', () {
    expect(const PushEvent(kind: 'goal', opened: false).isReward, isTrue);
    expect(const PushEvent(kind: 'like', route: '/post/3', opened: false).isReward, isFalse);
    // Sent by a server from before `kind`: the goal's destination tells.
    expect(const PushEvent(route: '/profile', opened: false).isReward, isTrue);
  });

  test('push is off without Firebase settings', () {
    expect(PushConfig.fromEnvironment.enabled, isFalse);
  });
}

String _identity(String s) => s;

/// Like the demo backend: posting a comment appends to the very list that
/// [comments] returned.
class _SharedListComments implements FeedRepository {
  final _list = <FeedComment>[];

  @override
  Future<FeedPage> fetch({String? cursor, int limit = 20}) async =>
      const FeedPage(posts: [], nextCursor: null);

  @override
  Future<List<FeedComment>> comments(String postId) async => _list;

  @override
  Future<FeedComment> addComment(String postId, String text) async {
    final c = FeedComment(
      id: 'c${_list.length}',
      author: const UserSummary(id: '1', handle: 'apex', displayName: 'Apex', level: 1),
      text: text,
      createdAt: DateTime(2026),
    );
    _list.add(c);
    return c;
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}
