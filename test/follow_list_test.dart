import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:speeddex/app/providers.dart';
import 'package:speeddex/data/repositories.dart';
import 'package:speeddex/domain/social.dart';
import 'package:speeddex/features/profile/presentation/follow_list_screen.dart';

/// Serves [total] followers, [pageSize] at a time, and records the requests.
class _Users implements UsersRepository {
  _Users(this.total, {this.pageSize = 20});
  final int total;
  final int pageSize;
  final requests = <(FollowList, String?)>[];

  @override
  Future<UserPage> follows(String userId, FollowList list, {String? cursor, int limit = 20}) async {
    requests.add((list, cursor));
    final start = cursor == null ? 0 : int.parse(cursor);
    final end = (start + pageSize).clamp(0, total);
    return UserPage(
      users: [
        for (var i = start; i < end; i++)
          UserSummary(id: 'u$i', handle: 'spotter$i', displayName: 'Spotter $i', level: 3),
      ],
      nextCursor: end < total ? '$end' : null,
    );
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  Future<_Users> pump(WidgetTester tester, _Users users, FollowList list) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [usersRepositoryProvider.overrideWithValue(users)],
        child: MaterialApp(
          home: FollowListScreen(userId: '7', list: list),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return users;
  }

  testWidgets('lists followers with name, handle and level, loading more on scroll', (
    tester,
  ) async {
    final users = await pump(tester, _Users(30, pageSize: 10), FollowList.followers);
    expect(find.text('FOLLOWERS'), findsOneWidget);
    expect(find.text('Spotter 0'), findsOneWidget);
    expect(find.text('@spotter0 · LV 3'), findsOneWidget);

    await tester.scrollUntilVisible(find.text('Spotter 25'), 300);
    expect(users.requests.map((r) => r.$2), [null, '10', '20']);
    expect(users.requests.every((r) => r.$1 == FollowList.followers), isTrue);
  });

  testWidgets('says so when nobody is followed yet', (tester) async {
    await pump(tester, _Users(0), FollowList.following);
    expect(find.text('FOLLOWING'), findsOneWidget);
    expect(find.text('NOT FOLLOWING ANYONE YET'), findsOneWidget);
  });
}
