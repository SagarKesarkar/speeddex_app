import 'dart:math';
import 'dart:typed_data';

import '../core/errors/app_failure.dart';
import '../core/security/token_store.dart';
import '../data/repositories.dart';
import '../domain/car_card.dart';
import '../domain/goals.dart';
import '../domain/premium.dart';
import '../domain/profile.dart';
import '../domain/rarity_tier.dart';
import '../domain/social.dart';
import 'dev_fixtures.dart';

/// In-memory stand-in for the SpeedDex backend, shared by all development
/// repositories so state stays consistent across tabs (e.g. an unlock debits
/// the same wallet the Profile tab shows).
///
/// It mirrors documented server rules — coin debit, garage capacity, daily scan
/// limit, idempotent unlocks — but enforces nothing real. All of these checks
/// must live on the backend (spec §6).
class DevStore {
  DevStore() {
    for (final (i, vid) in ['114', '101', '203', '305', '407', '102'].indexed) {
      final at = DevFixtures.byId(vid).capturedAt.subtract(Duration(minutes: i));
      _garage.add(_register(_instance(vid, 'mine-$vid', owned: true, at: at)));
    }
    _seedFeed();
    // The player's own catches are in the feed too, with a few reactions.
    for (final (i, card) in _garage.indexed) {
      _feed.add(
        FeedPost(
          id: 'mine-p$i',
          author: viewer,
          card: card,
          likeCount: (i * 5) % 13,
          commentCount: i % 4,
          viewerHasLiked: false,
          createdAt: card.capturedAt,
        ),
      );
    }
  }

  static const unlockCost = 5;
  static const scanReward = 3;
  static const dailyScanLimit = 5;
  static const rewardedScansPerDay = 5;
  static const garageCapacity = 100;

  final _rng = Random(7);
  final List<CarCard> _garage = [];
  final List<FeedPost> _feed = [];
  final Map<String, List<FeedComment>> _comments = {};

  /// Every card instance by id: the viewer's and other players'.
  final Map<String, CarCard> _cards = {};
  int _serialSeq = 300;

  /// Spotters the viewer follows.
  final Set<String> _following = {};

  /// Other players' cards the viewer has paid to unlock.
  final Set<String> _unlocked = {'p2-card'};
  final Set<String> _usedIdempotencyKeys = {};
  int _coins = 12;
  int _scansToday = 1;
  int _extraScans = 0;
  int _scanCursor = 0;
  int _captureSeq = 0;
  final Map<String, CarCard> _pendingCaptures = {};

  late UserProfile profile = UserProfile(
    id: 'me',
    handle: 'apex',
    displayName: 'Apex Spotter',
    licenseNo: 'SDX-LIC-30417',
    level: 4,
    xp: 1640,
    xpLevelStart: 1200,
    xpNextLevel: 2400,
    followers: 128,
    following: 87,
    issuedAt: DateTime(2026, 10, 21),
    bio: 'Weekend spotter. Collecting every flat-six I can find.',
    badges: devBadges.where((b) => b.earned).toList(),
    allBadges: devBadges,
  );

  int devLikesToday = 1;

  UserSummary get viewer => UserSummary(
    id: profile.id,
    handle: profile.handle,
    displayName: profile.displayName,
    level: profile.level,
  );

  /// [card] with its feed post's counts, as the API lists Garage cards.
  CarCard _withPost(CarCard card) {
    for (final p in _feed) {
      if (p.card.id == card.id) {
        return card.copyWith(
          post: PostStats(postId: p.id, likeCount: p.likeCount, commentCount: p.commentCount),
        );
      }
    }
    return card;
  }

  Future<void> latency([int ms = 550]) =>
      Future.delayed(Duration(milliseconds: ms + _rng.nextInt(250)));

  void _seedFeed() {
    final ids = [
      '711',
      '610',
      '408',
      '509',
      '306',
      '812',
      '315',
      '913',
      '203',
      '305',
      '101',
      '102',
    ];
    for (var i = 0; i < 36; i++) {
      final at = DateTime.now().subtract(Duration(minutes: 7 + i * 41));
      final card = _register(_instance(ids[i % ids.length], 'p$i-card', owned: false, at: at));
      final author = DevFixtures.users[i % DevFixtures.users.length];
      _feed.add(
        FeedPost(
          id: 'p$i',
          author: author,
          card: card,
          likeCount: 3 + (i * 17) % 140,
          commentCount: (i * 7) % 24,
          viewerHasLiked: i % 5 == 1,
          createdAt: DateTime.now().subtract(Duration(minutes: 7 + i * 41)),
        ),
      );
    }
  }

  /// A card instance of catalogue vehicle [vehicleId] with its own id and serial.
  CarCard _instance(
    String vehicleId,
    String id, {
    required bool owned,
    DateTime? at,
    String? imagePath,
  }) => DevFixtures.byId(vehicleId).copyWith(
    id: id,
    serial: 'SDX-${(_serialSeq++).toString().padLeft(5, '0')}',
    ownedByViewer: owned,
    capturedAt: at,
    imagePath: imagePath,
  );

  CarCard _register(CarCard c) => _cards[c.id] = c;

  /// What the API returns to this viewer: owners always get the spec sheet;
  /// anyone else gets it only after an unlock, and otherwise it is withheld.
  CarCard _forViewer(CarCard c) {
    final entitled = c.ownedByViewer || _unlocked.contains(c.id);
    return c.copyWith(hiddenUnlocked: entitled, clearHidden: !entitled);
  }

  CarCard _card(String id) => _cards[id] ?? (throw const NotFoundFailure());
}

class DevAuthRepository implements AuthRepository {
  DevAuthRepository(this._store, this._tokens);

  final DevStore _store;
  final TokenStore _tokens;

  Future<AuthSession> _start() async {
    // Opaque placeholder tokens: the real backend issues short-lived access
    // tokens and rotating refresh tokens.
    await _tokens.save(access: 'dev-access', refresh: 'dev-refresh');
    return AuthSession(userId: _store.profile.id);
  }

  @override
  Future<AuthSession?> restore() async =>
      await _tokens.hasSession() ? AuthSession(userId: _store.profile.id) : null;

  @override
  Future<AuthSession> signInWithEmail(String email, String password) async {
    await _store.latency(700);
    // Dev rule so the error state can be exercised.
    if (password == 'wrongpassword') throw const InvalidCredentialsFailure();
    return _start();
  }

  @override
  Future<AuthSession> signInWithGoogle(String idToken) async {
    await _store.latency(500);
    throw const ServiceUnavailableFailure(
      'Google sign-in is not connected in this development build.',
    );
  }

  @override
  Future<AuthSession> register({
    required String displayName,
    required String email,
    required String password,
  }) async {
    await _store.latency(800);
    _store.profile = _store.profile.copyWith(displayName: displayName);
    return _start();
  }

  @override
  Future<void> requestPasswordReset(String email) => _store.latency(600);

  /// Demo mode: the code is always 123456.
  @override
  Future<String> verifyResetCode(String email, String code) async {
    await _store.latency(500);
    if (code != '123456') {
      throw const RequestFailure(
        "That code isn't right or has expired. In demo mode it is 123456.",
      );
    }
    return 'demo-reset-token';
  }

  @override
  Future<void> resetPassword(String resetToken, String newPassword) => _store.latency(600);

  @override
  Future<void> signOut() async {
    await _store.latency(250);
    await _tokens.clear();
  }

  @override
  Future<void> deleteAccount(String password) async {
    await _store.latency(500);
    if (password == 'wrongpassword') throw const InvalidCredentialsFailure();
    await _tokens.clear();
  }
}

class DevFeedRepository implements FeedRepository {
  DevFeedRepository(this._store);
  final DevStore _store;

  @override
  Future<FeedPage> fetch({String? cursor, int limit = 20}) async {
    await _store.latency();
    final start = cursor == null ? 0 : int.parse(cursor);
    final end = min(start + limit, _store._feed.length);
    final posts = _store._feed
        .sublist(start, end)
        .map((p) => p.copyWith(card: _store._forViewer(p.card)))
        .toList();
    return FeedPage(posts: posts, nextCursor: end < _store._feed.length ? '$end' : null);
  }

  @override
  Future<FeedPost> post(String postId) async {
    await _store.latency();
    final p = _store._feed.firstWhere(
      (p) => p.id == postId,
      orElse: () => throw const NotFoundFailure('This post is no longer available.'),
    );
    return p.copyWith(card: _store._forViewer(p.card));
  }

  @override
  Future<void> setLiked(String postId, {required bool liked}) async {
    await _store.latency(350);
    final i = _store._feed.indexWhere((p) => p.id == postId);
    if (i < 0) return;
    final p = _store._feed[i];
    if (p.viewerHasLiked == liked) return;
    _store._feed[i] = p.copyWith(viewerHasLiked: liked, likeCount: p.likeCount + (liked ? 1 : -1));
  }

  @override
  Future<List<FeedComment>> comments(String postId) async {
    await _store.latency(450);
    return _store._comments.putIfAbsent(postId, () {
      final post = _store._feed.firstWhere((p) => p.id == postId);
      return List.generate(min(post.commentCount, 4), (i) {
        final author = DevFixtures.users[(i + 2) % DevFixtures.users.length];
        const lines = [
          'Clean spot. That stance is unreal.',
          'Where was this? Been hunting one for weeks.',
          'The colour on this one 👌',
          'Condition looks near perfect.',
        ];
        return FeedComment(
          id: '$postId-c$i',
          author: author,
          text: lines[i % lines.length],
          createdAt: DateTime.now().subtract(Duration(minutes: 3 + i * 19)),
        );
      });
    });
  }

  @override
  Future<FeedComment> addComment(String postId, String text) async {
    await _store.latency(400);
    final c = FeedComment(
      id: '$postId-c${DateTime.now().microsecondsSinceEpoch}',
      author: _store.viewer,
      text: text,
      createdAt: DateTime.now(),
    );
    _store._comments.putIfAbsent(postId, () => []).add(c);
    return c;
  }

  @override
  Future<void> report(String postId, String reason) => _store.latency(400);
}

class DevCardsRepository implements CardsRepository {
  DevCardsRepository(this._store);
  final DevStore _store;

  /// Demo cards are illustrations, not photos, so there are none to show.
  @override
  Future<List<ModelPhoto>> modelPhotos(String cardId) async => const [];

  @override
  Future<CarCard> detail(String cardId) async {
    await _store.latency(300);
    return _store._forViewer(_store._card(cardId));
  }

  @override
  Future<UnlockResult> unlock(String cardId, {required String idempotencyKey}) async {
    await _store.latency(650);
    final card = _store._card(cardId);
    // Owners never pay for their own spec sheet; repeats are free (idempotent).
    if (card.ownedByViewer ||
        _store._unlocked.contains(cardId) ||
        _store._usedIdempotencyKeys.contains(idempotencyKey)) {
      return UnlockResult(card: card.copyWith(hiddenUnlocked: true), coinsCharged: 0);
    }
    if (_store._coins < DevStore.unlockCost) {
      throw InsufficientCoinsFailure(required: DevStore.unlockCost, balance: _store._coins);
    }
    _store._coins -= DevStore.unlockCost;
    _store._unlocked.add(cardId);
    _store._usedIdempotencyKeys.add(idempotencyKey);
    return UnlockResult(
      card: card.copyWith(hiddenUnlocked: true),
      coinsCharged: DevStore.unlockCost,
    );
  }
}

class DevRankingRepository implements RankingRepository {
  DevRankingRepository(this._store);
  final DevStore _store;

  @override
  Future<LeaderboardPage> fetch(LeaderboardScope scope, LeaderboardPeriod period) async {
    await _store.latency();
    if (scope == LeaderboardScope.nearby) {
      throw const ServiceUnavailableFailure(
        'Nearby ranking needs location, which this build does not request yet.',
      );
    }
    final scale = switch (period) {
      LeaderboardPeriod.allTime => 1.0,
      LeaderboardPeriod.monthly => 0.32,
      LeaderboardPeriod.weekly => 0.09,
    };
    final scopeScale = 1.0 - scope.index * 0.18;
    final entries = <LeaderboardEntry>[];
    for (var i = 0; i < 40; i++) {
      final handle = DevFixtures.handles[(i * 5 + scope.index) % DevFixtures.handles.length];
      final xp = ((48000 / pow(i + 1, 0.62)) * scale * scopeScale).round();
      entries.add(
        LeaderboardEntry(
          rank: i + 1,
          user: UserSummary(id: 'r$i', handle: handle, displayName: handle, level: max(1, 40 - i)),
          xp: xp,
          carCount: max(3, (xp / 140).round()),
        ),
      );
    }
    final viewerXp = (_store.profile.xp * scale).round();
    final viewerRank = entries.where((e) => e.xp > viewerXp).length + 1 + (scope.index * 37) + 180;
    return LeaderboardPage(
      entries: entries,
      viewer: LeaderboardEntry(
        rank: viewerRank,
        user: _store.viewer,
        xp: viewerXp,
        carCount: _store._garage.length,
        isViewer: true,
      ),
    );
  }
}

class DevGarageRepository implements GarageRepository {
  DevGarageRepository(this._store);
  final DevStore _store;

  @override
  Future<GarageSummary> summary() async {
    await _store.latency(350);
    final counts = <RarityTier, int>{};
    for (final c in _store._garage) {
      counts[c.tier] = (counts[c.tier] ?? 0) + 1;
    }
    return GarageSummary(
      totalCards: _store._garage.length,
      capacity: DevStore.garageCapacity,
      totalXp: _store._garage.fold(0, (s, c) => s + c.xp),
      tierCounts: counts,
      scansToday: _store._scansToday,
      dailyScanLimit: DevStore.dailyScanLimit + _store._extraScans,
      rewardedScansLeft: DevStore.rewardedScansPerDay - _store._extraScans,
    );
  }

  @override
  Future<List<CarCard>> cards(GarageQuery query) async {
    await _store.latency();
    var list = _store._garage
        .where((c) => query.tier == null || c.tier == query.tier)
        .where((c) => query.make == null || c.make == query.make)
        .map(_store._forViewer)
        .map(_store._withPost)
        .toList();
    int perf(CarCard c) => c.specs.horsepower ?? c.specs.displacementCc ?? 0;
    list.sort(switch (query.sort) {
      GarageSort.newest => (a, b) => b.capturedAt.compareTo(a.capturedAt),
      GarageSort.oldest => (a, b) => a.capturedAt.compareTo(b.capturedAt),
      GarageSort.xp => (a, b) => b.xp.compareTo(a.xp),
      GarageSort.performance => (a, b) => perf(b).compareTo(perf(a)),
      GarageSort.rarity => (a, b) => b.tier.index.compareTo(a.tier.index),
    });
    return list;
  }

  @override
  Future<List<String>> makes() async {
    final set = _store._garage.map((c) => c.make).toSet().toList()..sort();
    return set;
  }
}

class DevCaptureRepository implements CaptureRepository {
  DevCaptureRepository(this._store);
  final DevStore _store;

  /// Deterministic sequence so every outcome path can be exercised:
  /// confident new card, duplicate, cautious low-confidence result.
  static const _sequence = [('306', 0.93), ('101', 0.95), ('610', 0.79), ('711', 0.91)];

  @override
  Future<IdentifyOutcome> identify(
    Uint8List jpegBytes, {
    required String localPath,
    Uint8List? thumbnail,
  }) async {
    await _store.latency(2200);
    if (_store._scansToday >= DevStore.dailyScanLimit + _store._extraScans) {
      throw const DailyScanLimitFailure();
    }
    final (vehicleId, confidence) = _sequence[_store._scanCursor % _sequence.length];
    _store._scanCursor++;
    final captureId = 'cap${_store._captureSeq++}';
    // The viewer's own capture: the full spec sheet is visible without unlocking.
    final candidate = _store._instance(
      vehicleId,
      'mine-$captureId',
      owned: true,
      at: DateTime.now(),
      imagePath: localPath,
    );
    _store._pendingCaptures[captureId] = candidate;
    final copies = _store._garage.where((c) => c.vehicleId == vehicleId).toList().reversed.toList();
    return Identified(
      captureId: captureId,
      candidate: candidate,
      confidence: confidence,
      duplicateOf: copies.firstOrNull,
      duplicates: copies,
    );
  }

  @override
  Future<AddResult> addToGarage(
    String captureId, {
    bool replace = false,
    String? replaceCardId,
    bool keepBoth = false,
  }) async {
    await _store.latency(700);
    final card = _store._pendingCaptures.remove(captureId);
    if (card == null) throw const UnknownFailure();
    final existing = replaceCardId != null
        ? _store._garage.indexWhere((c) => c.id == replaceCardId)
        : _store._garage.lastIndexWhere((c) => c.vehicleId == card.vehicleId);
    final repeat = keepBoth && _store._garage.any((c) => c.vehicleId == card.vehicleId);
    if (existing >= 0 && replace) {
      _store._garage[existing] = _store._register(card);
    } else {
      if (_store._garage.length >= DevStore.garageCapacity) throw const GarageFullFailure();
      _store._garage.insert(0, _store._register(card));
      // New catches are shared to the feed (spec §4.1).
      _store._feed.insert(
        0,
        FeedPost(
          id: 'post-$captureId',
          author: _store.viewer,
          card: card,
          likeCount: 0,
          commentCount: 0,
          viewerHasLiked: false,
          createdAt: DateTime.now(),
        ),
      );
    }
    // Only new cards use up the daily limit, as on the server.
    if (!replace) _store._scansToday++;
    // Replacements and repeats earn no reward, so a card cannot be farmed (spec §12).
    final coins = replace || repeat ? 0 : DevStore.scanReward;
    final xp = replace || repeat ? 0 : card.xp;
    _store._coins += coins;
    _store.profile = _store.profile.copyWith(xp: _store.profile.xp + xp);
    return AddResult(
      card: card,
      coinsAwarded: coins,
      xpAwarded: xp,
      replaced: replace && existing >= 0,
    );
  }

  @override
  Future<void> discard(String captureId) async {
    _store._pendingCaptures.remove(captureId);
  }

  @override
  Future<void> reportMismatch(String captureId) => _store.latency(400);

  @override
  Future<List<IdentifyOutcome>> pending() async => const [];
}

class DevProfileRepository implements ProfileRepository {
  DevProfileRepository(this._store);
  final DevStore _store;

  @override
  Future<UserProfile> me() async {
    await _store.latency(350);
    return _store.profile;
  }

  @override
  Future<bool> resendVerification() async {
    await _store.latency(400);
    return _store.profile.emailVerified;
  }

  @override
  Future<UserProfile> update({
    required String displayName,
    String? bio,
    Country? country,
    City? city,
  }) async {
    await _store.latency(500);
    _store.profile = _store.profile.copyWith(
      displayName: displayName,
      bio: bio,
      region: UserRegion(country: country, city: country == null ? null : city),
    );
    return _store.profile;
  }

  @override
  Future<Wallet> wallet() async {
    await _store.latency(250);
    return Wallet(coins: _store._coins, adsWatchedToday: 0);
  }

  @override
  Future<DailyGoals> dailyGoals() async {
    await _store.latency(250);
    final catches = _store._scansToday.clamp(0, 1);
    final likes = _store.devLikesToday.clamp(0, 3);
    final goals = [
      DailyGoal(
        id: 'catch',
        title: 'Catch a car',
        description: 'Add a new car to your Garage.',
        progress: catches,
        target: 1,
        xp: 25,
        completed: catches >= 1,
      ),
      DailyGoal(
        id: 'like',
        title: 'Like 3 catches',
        description: "Like other players' cars in the feed.",
        progress: likes,
        target: 3,
        xp: 10,
        completed: likes >= 3,
      ),
      const DailyGoal(
        id: 'comment',
        title: 'Leave a comment',
        description: "Comment on another player's car.",
        progress: 0,
        target: 1,
        xp: 10,
        completed: false,
      ),
    ];
    final now = DateTime.now().toUtc();
    return DailyGoals(
      goals: goals,
      bonusTitle: 'Complete every goal',
      bonusXp: 25,
      bonusCompleted: goals.every((g) => g.completed),
      xpEarnedToday: goals.where((g) => g.completed).fold(0, (n, g) => n + g.xp),
      resetsAt: DateTime.utc(now.year, now.month, now.day + 1),
    );
  }

  @override
  Future<void> registerPushToken(String token, {required String platform}) async {}

  @override
  Future<void> unregisterPushToken(String token) async {}

  @override
  Future<SubscriptionInfo> subscriptionInfo() async {
    await _store.latency(250);
    // No store behind the built-in demo data.
    return const SubscriptionInfo(
      productIds: ['speeddex_pro_monthly'],
      onGooglePlay: false,
      onAppStore: false,
      accountToken: '',
      premium: Premium.none,
    );
  }

  @override
  Future<Premium> verifySubscription({
    required String platform,
    required String productId,
    required String purchaseRef,
  }) async => throw const ServiceUnavailableFailure('Subscriptions need the real server.');
}

/// A small built-in location list for development mode; the real API serves
/// every country and every city over 15,000 people (GeoNames).
class DevGeoRepository implements GeoRepository {
  DevGeoRepository(this._store);
  final DevStore _store;

  static const _countries = [
    Country(code: 'AE', name: 'United Arab Emirates'),
    Country(code: 'GB', name: 'United Kingdom'),
    Country(code: 'IN', name: 'India'),
    Country(code: 'JP', name: 'Japan'),
    Country(code: 'US', name: 'United States'),
  ];

  static const _cities = {
    'IN': [
      City(id: 1275339, name: 'Mumbai', regionName: 'Maharashtra'),
      City(id: 1273294, name: 'Delhi', regionName: 'Delhi'),
      City(id: 1277333, name: 'Bengaluru', regionName: 'Karnataka'),
      City(id: 1259229, name: 'Pune', regionName: 'Maharashtra'),
      City(id: 1261481, name: 'Nashik', regionName: 'Maharashtra'),
    ],
    'AE': [City(id: 292223, name: 'Dubai', regionName: 'Dubai')],
    'GB': [City(id: 2643743, name: 'London', regionName: 'England')],
    'JP': [City(id: 1850147, name: 'Tokyo', regionName: 'Tokyo')],
    'US': [City(id: 5128581, name: 'New York City', regionName: 'New York')],
  };

  bool _match(String name, String? q) =>
      q == null || q.isEmpty || name.toLowerCase().startsWith(q.toLowerCase());

  @override
  Future<List<Country>> countries({String? search}) async {
    await _store.latency(150);
    return _countries
        .where((c) => _match(c.name, search) || c.code == search?.toUpperCase())
        .toList();
  }

  @override
  Future<List<City>> cities(String countryCode, {String? search}) async {
    await _store.latency(150);
    return (_cities[countryCode] ?? const []).where((c) => _match(c.name, search)).toList();
  }
}

class DevUsersRepository implements UsersRepository {
  DevUsersRepository(this._store);
  final DevStore _store;

  UserSummary _user(String id) =>
      DevFixtures.users.where((u) => u.id == id).firstOrNull ??
      (id == _store.profile.id
          ? _store.viewer
          : throw const NotFoundFailure('This spotter is no longer available.'));

  int _followers(String id) => 40 + id.hashCode % 200 + (_store._following.contains(id) ? 1 : 0);

  @override
  Future<PublicProfile> publicProfile(String userId) async {
    await _store.latency(300);
    final u = _user(userId);
    final cars = _store._feed.where((p) => p.author.id == userId).length;
    return PublicProfile(
      user: u,
      bio: userId == _store.profile.id ? _store.profile.bio : 'Spotting since day one.',
      xp: u.level * 900,
      followers: _followers(userId),
      following: 30 + userId.hashCode % 90,
      carCount: cars,
      viewerFollows: _store._following.contains(userId),
      isViewer: userId == _store.profile.id,
    );
  }

  @override
  Future<int> follow(String userId) async {
    await _store.latency(250);
    if (userId == _store.profile.id) throw const RequestFailure('You cannot follow yourself.');
    _store._following.add(userId);
    return _followers(userId);
  }

  @override
  Future<int> unfollow(String userId) async {
    await _store.latency(250);
    _store._following.remove(userId);
    return _followers(userId);
  }

  @override
  Future<UserPage> follows(String userId, FollowList list, {String? cursor, int limit = 20}) async {
    await _store.latency(300);
    final others = DevFixtures.users.where((u) => u.id != userId);
    final all = switch (list) {
      // The viewer's own following list is real; everything else is sample data.
      FollowList.following when userId == _store.profile.id =>
        others.where((u) => _store._following.contains(u.id)).toList(),
      FollowList.followers when _store._following.contains(userId) => [_store.viewer, ...others],
      _ => others.toList(),
    };
    final start = cursor == null ? 0 : int.parse(cursor);
    final end = min(start + limit, all.length);
    return UserPage(users: all.sublist(start, end), nextCursor: end < all.length ? '$end' : null);
  }

  @override
  Future<CardPage> cards(String userId, {String? cursor, int limit = 12}) async {
    await _store.latency();
    final all = _store._feed.where((p) => p.author.id == userId).toList();
    final start = cursor == null ? 0 : int.parse(cursor);
    final end = min(start + limit, all.length);
    return CardPage(
      cards: [for (final p in all.sublist(start, end)) _store._forViewer(p.card)],
      nextCursor: end < all.length ? '$end' : null,
    );
  }
}

/// Demo mode: every watched ad is granted at once.
class DevAdsRepository implements AdsRepository {
  DevAdsRepository(this._store);
  final DevStore _store;

  @override
  Future<RewardClaim> claim({
    required RewardPlacement placement,
    required String ref,
    String? cardId,
  }) async {
    await _store.latency(400);
    switch (placement) {
      case RewardPlacement.extraScan:
        if (_store._extraScans >= DevStore.rewardedScansPerDay) {
          throw const AdRewardLimitFailure(
            'You’ve used all 5 extra scans from ads today. More tomorrow.',
          );
        }
        _store._extraScans++;
        return ScanRewardGranted(
          scansToday: _store._scansToday,
          dailyScanLimit: DevStore.dailyScanLimit + _store._extraScans,
        );
      case RewardPlacement.cardUnlock:
        _store._unlocked.add(cardId!);
        return UnlockRewardGranted(_store._card(cardId).copyWith(hiddenUnlocked: true));
    }
  }
}

/// Sample badge case for development mode: a few earned, the rest in progress.
final devBadges = [
  SpotterBadge(
    id: 'royal_court',
    name: 'Royal Court',
    description: 'Catch a Royal car or rarer.',
    icon: 'crown',
    grade: BadgeGrade.silver,
    earnedAt: DateTime(2026, 10, 24),
  ),
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
  const SpotterBadge(
    id: 'rare_hunter',
    name: 'Rare Hunter',
    description: 'Catch a Rare car or rarer.',
    icon: 'gem',
    grade: BadgeGrade.silver,
    earned: false,
  ),
  const SpotterBadge(
    id: 'living_legend',
    name: 'Living Legend',
    description: 'Catch a Legendary or Mythic car.',
    icon: 'flame',
    grade: BadgeGrade.gold,
    earned: false,
  ),
  const SpotterBadge(
    id: 'myth_maker',
    name: 'Myth Maker',
    description: 'Catch a Mythic car.',
    icon: 'star',
    grade: BadgeGrade.platinum,
    earned: false,
  ),
  const SpotterBadge(
    id: 'brand_explorer',
    name: 'Brand Explorer',
    description: 'Catch cars from 10 different brands.',
    icon: 'globe',
    grade: BadgeGrade.silver,
    earned: false,
    progress: 4,
    target: 10,
  ),
  const SpotterBadge(
    id: 'crowd_favourite',
    name: 'Crowd Favourite',
    description: 'Get 50 likes on your catches.',
    icon: 'heart',
    grade: BadgeGrade.gold,
    earned: false,
    progress: 31,
    target: 50,
  ),
];
