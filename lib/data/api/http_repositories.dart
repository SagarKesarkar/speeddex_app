import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import '../../core/errors/app_failure.dart';
import '../../core/security/token_store.dart';
import '../../domain/car_card.dart';
import '../../domain/profile.dart';
import '../../domain/social.dart';
import '../repositories.dart';
import 'api_client.dart';
import 'json_mappers.dart';

Json _j(Object? v) => (v as Map).cast<String, dynamic>();
List<Json> _items(Object? body) => [for (final i in (_j(body)['items'] as List)) _j(i)];

class HttpAuthRepository implements AuthRepository {
  HttpAuthRepository(this._api, this._tokens);
  final ApiClient _api;
  final TokenStore _tokens;

  Future<AuthSession> _start(Object? body) async {
    final b = _j(body);
    await _api.saveSession(b);
    return AuthSession(userId: '${_j(b['user'])['userId']}');
  }

  @override
  Future<AuthSession?> restore() async {
    if (!await _tokens.hasSession()) return null;
    try {
      // Validates the stored session (and refreshes it if needed).
      final s = await _api.get('/auth/session');
      return AuthSession(userId: '${_j(s)['userId']}');
    } on NetworkFailure {
      // Offline at launch: keep the user signed in; calls will retry later.
      return const AuthSession(userId: '');
    } on SessionExpiredFailure {
      return null;
    }
  }

  @override
  Future<AuthSession> signInWithEmail(String email, String password) async =>
      _start(await _api.postPublic('/auth/login', {'email': email, 'password': password}));

  @override
  Future<AuthSession> signInWithGoogle() async {
    // The Google ID token comes from the native Google Sign-In SDK, which is
    // not integrated yet. The API also refuses until GOOGLE_CLIENT_IDS is set.
    throw const ServiceUnavailableFailure('Google sign-in is not available yet.');
  }

  @override
  Future<AuthSession> register({
    required String displayName,
    required String email,
    required String password,
  }) async => _start(
    await _api.postPublic('/auth/register', {
      'fullName': displayName,
      'email': email,
      'password': password,
      // The register screen blocks submission until the box is ticked.
      'acceptTerms': true,
    }),
  );

  @override
  Future<void> requestPasswordReset(String email) async {
    await _api.postPublic('/auth/password/forgot', {'email': email});
  }

  @override
  Future<String> verifyResetCode(String email, String code) async =>
      _j(
            await _api.postPublic('/auth/password/verify-code', {'email': email, 'code': code}),
          )['resetToken']
          as String;

  @override
  Future<void> resetPassword(String resetToken, String newPassword) async {
    await _api.postPublic('/auth/password/reset', {'token': resetToken, 'password': newPassword});
  }

  @override
  Future<void> deleteAccount(String password) async {
    await _api.post('/users/me/delete', {'password': password, 'confirm': 'DELETE'});
    await _tokens.clear();
  }

  @override
  Future<void> signOut() async {
    final refresh = await _tokens.readRefresh();
    try {
      if (refresh != null) await _api.postPublic('/auth/logout', {'refreshToken': refresh});
    } finally {
      await _tokens.clear();
    }
  }
}

class HttpFeedRepository implements FeedRepository {
  HttpFeedRepository(this._api, this._m);
  final ApiClient _api;
  final ApiMappers _m;

  @override
  Future<FeedPage> fetch({String? cursor, int limit = 20}) async {
    final b = await _api.get('/feed', query: {'limit': '$limit', 'cursor': cursor});
    return FeedPage(
      posts: _items(b).map(_m.post).toList(),
      nextCursor: _j(b)['nextCursor'] as String?,
    );
  }

  @override
  Future<void> setLiked(String postId, {required bool liked}) async {
    liked ? await _api.put('/posts/$postId/like') : await _api.delete('/posts/$postId/like');
  }

  @override
  Future<List<FeedComment>> comments(String postId) async =>
      _items(await _api.get('/posts/$postId/comments', query: {'limit': '50'}))
          .map(_m.comment)
          .toList();

  @override
  Future<FeedComment> addComment(String postId, String text) async =>
      _m.comment(_j(await _api.post('/posts/$postId/comments', {'commentText': text})));

  @override
  Future<void> report(String postId, String reason) async {
    await _api.post('/reports', {
      'targetType': 'post',
      'targetId': int.parse(postId),
      'reason': reason,
    });
  }
}

class HttpCardsRepository implements CardsRepository {
  HttpCardsRepository(this._api, this._m);
  final ApiClient _api;
  final ApiMappers _m;

  @override
  Future<CarCard> detail(String cardId) async => _m.card(_j(await _api.get('/cards/$cardId')));

  @override
  Future<List<ModelPhoto>> modelPhotos(String cardId) async => [
    for (final p
        in (_j(await _api.get('/cards/$cardId/model-photos'))['items'] as List? ?? const []))
      ModelPhoto(
        view: (p as Map)['view'] as String? ?? '',
        imageUrl: p['imageUrl'] == null ? null : _m.rebaseUrl(p['imageUrl'] as String),
        credit: p['credit'] as String?,
      ),
  ];

  @override
  Future<UnlockResult> unlock(String cardId, {required String idempotencyKey}) async {
    // The server keys the entitlement on (viewer, card), so repeats never charge twice.
    final b = _j(await _api.post('/cards/$cardId/unlock', {'paymentMethod': 'coins'}));
    return UnlockResult(
      card: _m.card(_j(b['card'])),
      coinsCharged: (b['coinsCharged'] as num).toInt(),
    );
  }
}

class HttpAdsRepository implements AdsRepository {
  HttpAdsRepository(this._api, this._m);
  final ApiClient _api;
  final ApiMappers _m;

  @override
  Future<RewardClaim> claim({
    required RewardPlacement placement,
    required String ref,
    String? cardId,
  }) async {
    final b = _j(
      await _api.post('/ads/reward/verify', {
        'placement': placement.wire,
        'ref': ref,
        if (cardId != null) 'cardId': int.parse(cardId),
      }),
    );
    if (b['status'] != 'granted') return const RewardPending();
    return switch (placement) {
      RewardPlacement.extraScan => ScanRewardGranted(
        scansToday: (b['scansToday'] as num).toInt(),
        dailyScanLimit: (b['dailyScanLimit'] as num).toInt(),
      ),
      RewardPlacement.cardUnlock => UnlockRewardGranted(_m.card(_j(b['card']))),
    };
  }
}

class HttpRankingRepository implements RankingRepository {
  HttpRankingRepository(this._api, this._m);
  final ApiClient _api;
  final ApiMappers _m;

  static const _period = {
    LeaderboardPeriod.allTime: 'all_time',
    LeaderboardPeriod.weekly: 'weekly',
    LeaderboardPeriod.monthly: 'monthly',
  };

  @override
  Future<LeaderboardPage> fetch(LeaderboardScope scope, LeaderboardPeriod period) async {
    if (scope == LeaderboardScope.nearby) {
      // POST /leaderboards/nearby exists on the API; the app doesn't request
      // location permission yet, so there's nothing to send.
      throw const ServiceUnavailableFailure(
        'Nearby ranking needs location, which this build does not request yet.',
      );
    }
    final b = _j(
      await _api.get('/leaderboards', query: {'scope': scope.name, 'period': _period[period]}),
    );
    if (b['regionRequired'] == true) {
      throw RequestFailure(
        'Add your country${scope == LeaderboardScope.country ? '' : ' and city'} in Profile → Edit profile to see this ranking.',
        code: 'REGION_REQUIRED',
      );
    }
    return LeaderboardPage(
      entries: _items(b).map(_m.entry).toList(),
      viewer: b['viewer'] == null ? null : _m.entry(_j(b['viewer'])),
    );
  }
}

class HttpGarageRepository implements GarageRepository {
  HttpGarageRepository(this._api, this._m);
  final ApiClient _api;
  final ApiMappers _m;

  @override
  Future<GarageSummary> summary() async => _m.garage(_j(await _api.get('/garage/summary')));

  @override
  Future<List<CarCard>> cards(GarageQuery query) async {
    final out = <CarCard>[];
    String? cursor;
    // The Garage screen shows the whole collection; fetch pages of 50.
    do {
      final b = _j(
        await _api.get(
          '/garage/cards',
          query: {
            'limit': '50',
            'cursor': cursor,
            'sort': query.sort.name,
            'rarity': query.tier?.name,
            'make': query.make,
          },
        ),
      );
      out.addAll(_items(b).map(_m.card));
      cursor = b['nextCursor'] as String?;
    } while (cursor != null && out.length < 1000);
    return out;
  }

  @override
  Future<List<String>> makes() async => [
    for (final m in (_j(await _api.get('/garage/makes'))['items'] as List)) m as String,
  ];
}

class HttpCaptureRepository implements CaptureRepository {
  HttpCaptureRepository(this._api, this._m);
  final ApiClient _api;
  final ApiMappers _m;
  final _rng = Random.secure();

  /// Maps server rejection reasons to user-facing copy.
  static const _rejections = {
    'spoof_suspected': 'This looks like a photo of a screen, print or model. Scan a real car.',
    'no_vehicle_found': 'We couldn’t find a car in that photo. Frame the whole car and try again.',
    'repeated_image': 'This photo was already used. Take a new one.',
    'moderator_rejected': 'A reviewer couldn’t accept this capture.',
  };

  String _nonce() => List.generate(24, (_) => _rng.nextInt(36).toRadixString(36)).join();

  /// Photos already uploaded, by local path, until they get a result. A retry
  /// after a network error continues that capture instead of uploading the
  /// photo again as a new one.
  final _uploaded = <String, String>{};

  @override
  Future<IdentifyOutcome> identify(Uint8List jpegBytes, {required String localPath}) async {
    var captureId = _uploaded[localPath];
    if (captureId == null) {
      final session = _j(
        await _api.post('/captures/upload-session', {
          'capturedAt': DateTime.now().toUtc().toIso8601String(),
          'cameraSource': 'native_camera',
          'clientNonce': _nonce(),
        }),
      );
      captureId = '${session['captureId']}';
      final upload = _j(session['upload']);
      await _api.putBytes(_api.rebase(upload['url'] as String), jpegBytes);
      _uploaded[localPath] = captureId;
    }
    try {
      await _api.post('/captures/$captureId/identify');
    } on RequestFailure catch (f) {
      // Already identified (the earlier answer was lost on the way): read it.
      if (f.code != 'CAPTURE_STATE_CONFLICT') rethrow;
    }
    final outcome = await _poll(captureId, localPath);
    _uploaded.remove(localPath);
    return outcome;
  }

  Future<IdentifyOutcome> _poll(String captureId, String localPath) async {
    // Recognition runs in the background on the server; poll with backoff.
    // The server gives up within about a minute (fallback models included).
    final deadline = DateTime.now().add(const Duration(seconds: 100));
    var delay = const Duration(milliseconds: 700);
    while (true) {
      final c = _j(await _api.get('/captures/$captureId'));
      if (c['status'] == 'failed') {
        throw const ServiceUnavailableFailure('We couldn’t process that photo. Please try again.');
      }
      if (_outcome(c, localImagePath: localPath) case final done?) return done;
      if (DateTime.now().isAfter(deadline)) {
        throw const ServiceUnavailableFailure(
          'Identification is taking longer than usual. Check your Garage later.',
        );
      }
      await Future<void>.delayed(delay);
      delay = Duration(milliseconds: min(delay.inMilliseconds * 2, 3000));
    }
  }

  @override
  Future<AddResult> addToGarage(
    String captureId, {
    bool replace = false,
    String? replaceCardId,
    bool keepBoth = false,
  }) async {
    final b = _j(
      await _api.post('/captures/$captureId/add-to-garage', {
        'replace': replace,
        if (replace && replaceCardId != null) 'replaceCardId': int.parse(replaceCardId),
        if (keepBoth) 'keepBoth': true,
      }),
    );
    final rewards = _j(b['rewards']);
    return AddResult(
      card: _m.card(_j(b['card'])),
      coinsAwarded: (rewards['coins'] as num).toInt(),
      xpAwarded: (rewards['xp'] as num).toInt(),
      replaced: b['status'] == 'replaced',
    );
  }

  /// Maps a capture's server status to an outcome; null while still processing.
  IdentifyOutcome? _outcome(Json c, {String? localImagePath}) {
    final id = '${c['captureId']}';
    return switch (c['status']) {
      'identified' => Identified(
        captureId: id,
        candidate: _m.card(_j(c['candidate']), localImagePath: localImagePath),
        confidence: (c['confidence'] as num?)?.toDouble() ?? 0,
        duplicateOf: c['duplicateOf'] == null ? null : _m.card(_j(c['duplicateOf'])),
        duplicates: [for (final d in (c['duplicates'] as List?) ?? const []) _m.card(_j(d))],
        reviewerConfirmed: c['reviewerConfirmed'] == true,
      ),
      'review_required' => ReviewRequired(id),
      'rejected' => Rejected(
        _rejections[c['statusReason']] ?? 'This capture couldn’t be accepted.',
      ),
      _ => null,
    };
  }

  @override
  Future<List<IdentifyOutcome>> pending() async => [
    for (final c in _items(await _api.get('/captures'))) ?_outcome(c),
  ];

  @override
  Future<void> discard(String captureId) async {
    await _api.post('/captures/$captureId/discard');
  }

  @override
  Future<void> reportMismatch(String captureId) async {
    await _api.post('/captures/$captureId/report-mismatch');
  }
}

class HttpProfileRepository implements ProfileRepository {
  HttpProfileRepository(this._api, this._m);
  final ApiClient _api;
  final ApiMappers _m;

  @override
  Future<UserProfile> me() async => _m.profile(_j(await _api.get('/users/me')));

  @override
  Future<UserProfile> update({
    required String displayName,
    String? bio,
    Country? country,
    City? city,
  }) async => _m.profile(
    _j(
      await _api.patch('/users/me', {
        'fullName': displayName,
        'bio': ?bio,
        // A null country clears the location; the server derives the state.
        'countryCode': country?.code,
        'cityId': city?.id,
      }),
    ),
  );

  @override
  Future<bool> resendVerification() async =>
      _j(await _api.post('/auth/email/verify/resend'))['alreadyVerified'] == true;

  @override
  Future<Wallet> wallet() async {
    final b = _j(await _api.get('/wallet'));
    return Wallet(
      coins: (b['coins'] as num).toInt(),
      adsWatchedToday: (b['adsWatchedToday'] as num).toInt(),
    );
  }
}

class HttpGeoRepository implements GeoRepository {
  HttpGeoRepository(this._api, this._m);
  final ApiClient _api;
  final ApiMappers _m;

  @override
  Future<List<Country>> countries({String? search}) async =>
      _items(await _api.get('/geo/countries', query: {'search': search})).map(_m.country).toList();

  @override
  Future<List<City>> cities(String countryCode, {String? search}) async => _items(
    await _api.get('/geo/countries/$countryCode/cities', query: {'search': search, 'limit': '20'}),
  ).map(_m.city).toList();
}

class HttpUsersRepository implements UsersRepository {
  HttpUsersRepository(this._api, this._m);
  final ApiClient _api;
  final ApiMappers _m;

  @override
  Future<PublicProfile> publicProfile(String userId) async =>
      _m.publicProfile(_j(await _api.get('/users/$userId/public-profile')));

  @override
  Future<int> follow(String userId) async =>
      (_j(await _api.post('/users/$userId/follow'))['followerCount'] as num).toInt();

  @override
  Future<int> unfollow(String userId) async =>
      (_j(await _api.delete('/users/$userId/follow'))['followerCount'] as num).toInt();

  @override
  Future<CardPage> cards(String userId, {String? cursor, int limit = 12}) async {
    final b = _j(
      await _api.get('/users/$userId/cards', query: {'limit': '$limit', 'cursor': cursor}),
    );
    return CardPage(cards: _items(b).map(_m.card).toList(), nextCursor: b['nextCursor'] as String?);
  }

  @override
  Future<UserPage> follows(String userId, FollowList list, {String? cursor, int limit = 20}) async {
    final b = _j(
      await _api.get('/users/$userId/${list.name}', query: {'limit': '$limit', 'cursor': cursor}),
    );
    return UserPage(users: _items(b).map(_m.user).toList(), nextCursor: b['nextCursor'] as String?);
  }
}
