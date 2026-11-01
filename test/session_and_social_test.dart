import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:speeddex/app/providers.dart';
import 'package:speeddex/core/errors/app_failure.dart';
import 'package:speeddex/core/widgets/sd_search_picker.dart';
import 'package:speeddex/data/api/json_mappers.dart';
import 'package:speeddex/data/repositories.dart';
import 'package:speeddex/domain/profile.dart';
import 'package:speeddex/domain/social.dart';
import 'package:speeddex/features/auth/application/auth_controller.dart';
import 'package:speeddex/features/feed/presentation/feed_post_tile.dart';

/// Fails like a signed-out request until [signedIn] is set.
class _Profiles implements ProfileRepository {
  bool signedIn = false;

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);

  @override
  Future<UserProfile> me() async {
    if (!signedIn) throw const SessionExpiredFailure();
    return UserProfile(
      id: '1',
      handle: 'apex',
      displayName: 'Apex',
      licenseNo: 'L',
      level: 1,
      xp: 0,
      xpLevelStart: 0,
      xpNextLevel: 100,
      followers: 0,
      following: 0,
      issuedAt: DateTime(2026),
    );
  }

  @override
  Future<bool> resendVerification() async => false;

  @override
  Future<Wallet> wallet() async {
    if (!signedIn) throw const SessionExpiredFailure();
    return const Wallet(coins: 15, adsWatchedToday: 0);
  }

  @override
  Future<UserProfile> update({
    required String displayName,
    String? bio,
    Country? country,
    City? city,
  }) => throw UnimplementedError();
}

class _Auth implements AuthRepository {
  _Auth(this.profiles);
  final _Profiles profiles;

  @override
  Future<AuthSession?> restore() async => null;
  @override
  Future<AuthSession> signInWithEmail(String email, String password) async {
    profiles.signedIn = true;
    return const AuthSession(userId: '1');
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  test('signing in replaces account data cached while signed out', () async {
    // Regression: Profile and Garage showed "Couldn't load" after login
    // because an error cached during sign-out was never cleared.
    final profiles = _Profiles();
    final c = ProviderContainer(
      overrides: [
        profileRepositoryProvider.overrideWithValue(profiles),
        authRepositoryProvider.overrideWithValue(_Auth(profiles)),
      ],
      retry: (_, _) => null,
    );
    addTearDown(c.dispose);
    final sub = c.listen(profileProvider, (_, _) {});
    final wallet = c.listen(walletProvider, (_, _) {});
    await expectLater(c.read(profileProvider.future), throwsA(isA<SessionExpiredFailure>()));
    await expectLater(c.read(walletProvider.future), throwsA(isA<SessionExpiredFailure>()));

    await c.read(authControllerProvider.notifier).signIn('a@b.co', 'redline99');

    expect((await c.read(profileProvider.future)).handle, 'apex');
    expect((await c.read(walletProvider.future)).coins, 15); // not a stale balance
    expect(c.read(authControllerProvider), AuthStatus.signedIn);
    sub.close();
    wallet.close();
  });

  group('location picker', () {
    const countries = [Country(code: 'IN', name: 'India'), Country(code: 'JP', name: 'Japan')];

    Future<List<Country?>> pump(WidgetTester tester, {Country? selected}) async {
      final changes = <Country?>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(16),
              child: Form(
                child: SdSearchPicker<Country>(
                  label: 'Country',
                  selected: selected,
                  search: (q) async => countries
                      .where((c) => c.name.toLowerCase().startsWith(q.toLowerCase()))
                      .toList(),
                  displayOf: (c) => c.name,
                  onChanged: changes.add,
                ),
              ),
            ),
          ),
        ),
      );
      return changes;
    }

    testWidgets('typing shows matching options and picking one selects it', (tester) async {
      final changes = await pump(tester);
      await tester.enterText(find.byType(TextFormField), 'ja');
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
      expect(find.text('Japan'), findsOneWidget);
      expect(find.text('India'), findsNothing);
      await tester.tap(find.text('Japan'));
      await tester.pumpAndSettle();
      expect(changes.last, countries[1]);
    });

    testWidgets('editing a picked value clears it, so free text is never saved', (tester) async {
      final changes = await pump(tester, selected: countries[0]);
      await tester.enterText(find.byType(TextFormField), 'Indiaa');
      await tester.pump(const Duration(milliseconds: 300));
      expect(changes.last, isNull);
    });
  });

  testWidgets('feed author header shows full name, muted username, and opens the profile', (
    tester,
  ) async {
    var opened = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AuthorHeader(
            author: const UserSummary(
              id: '7',
              handle: 'nightshift',
              displayName: 'Meera Kulkarni',
              level: 14,
            ),
            meta: const ['7m', 'Pune'],
            onTap: () => opened = true,
          ),
        ),
      ),
    );
    expect(find.text('Meera Kulkarni'), findsOneWidget);
    expect(find.text('@nightshift · LV 14 · 7m · Pune'), findsOneWidget);
    await tester.tap(find.byType(AuthorHeader));
    expect(opened, isTrue);
  });

  test('maps profile location and public profiles', () {
    const m = ApiMappers(_identity);
    final p = m.profile({
      'userId': 1,
      'username': 'apex',
      'displayName': 'Apex',
      'level': 1,
      'xp': 0,
      'region': {
        'countryCode': 'IN',
        'countryName': 'India',
        'stateName': 'Maharashtra',
        'cityId': 1259229,
        'city': 'Pune',
      },
    });
    expect(p.region.country, const Country(code: 'IN', name: 'India'));
    expect(p.region.city!.label, 'Pune, Maharashtra');

    final pub = m.publicProfile({
      'userId': 7,
      'username': 'nightshift',
      'displayName': 'Meera',
      'level': 3,
      'xp': 900,
      'followers': 4,
      'following': 2,
      'carCount': 1,
      'viewerFollows': true,
      'isViewer': false,
      'badges': [],
    });
    expect(pub.viewerFollows, isTrue);
    expect(pub.user.displayName, 'Meera');
  });
}

String _identity(String s) => s;
