import 'dart:typed_data';

import '../domain/car_card.dart';
import '../domain/goals.dart';
import '../domain/profile.dart';
import '../domain/rarity_tier.dart';
import '../domain/social.dart';

/// Integration boundary between the UI and the SpeedDex API (spec §5).
///
/// Each method maps to one documented endpoint. Implementations: HTTP
/// (`lib/data/api/`) when API_BASE_URL is set, otherwise the labelled
/// development backend (`lib/dev/`).

class AuthSession {
  const AuthSession({required this.userId});
  final String userId;
}

abstract interface class AuthRepository {
  /// Restores a session from secure storage, refreshing if needed.
  Future<AuthSession?> restore();

  /// POST /v1/auth/login
  Future<AuthSession> signInWithEmail(String email, String password);

  /// POST /v1/auth/google
  Future<AuthSession> signInWithGoogle();

  /// POST /v1/auth/register
  Future<AuthSession> register({
    required String displayName,
    required String email,
    required String password,
  });

  /// POST /v1/auth/password/forgot — emails a 6-digit code if the account
  /// exists. Always completes neutrally.
  Future<void> requestPasswordReset(String email);

  /// POST /v1/auth/password/verify-code — exchanges the emailed code for a
  /// short-lived token that allows setting a new password.
  Future<String> verifyResetCode(String email, String code);

  /// POST /v1/auth/password/reset — sets the new password. Signs the account
  /// out everywhere; the player then signs in with the new password.
  Future<void> resetPassword(String resetToken, String newPassword);

  /// POST /v1/auth/logout — revokes the refresh session server-side.
  Future<void> signOut();

  /// POST /v1/users/me/delete — deletes the account for good and ends every
  /// session. Throws [InvalidCredentialsFailure] for a wrong password.
  Future<void> deleteAccount(String password);
}

/// One page of Car Cards with an opaque cursor for the next.
class CardPage {
  const CardPage({required this.cards, required this.nextCursor});
  final List<CarCard> cards;
  final String? nextCursor;
}

class UserPage {
  const UserPage({required this.users, required this.nextCursor});
  final List<UserSummary> users;
  final String? nextCursor;
}

/// Which side of a follow relationship a list shows.
enum FollowList { followers, following }

class FeedPage {
  const FeedPage({required this.posts, required this.nextCursor});
  final List<FeedPost> posts;
  final String? nextCursor;
}

abstract interface class FeedRepository {
  /// GET /v1/feed?limit=20&cursor=...
  Future<FeedPage> fetch({String? cursor, int limit = 20});

  /// PUT/DELETE /v1/posts/{postId}/like
  Future<void> setLiked(String postId, {required bool liked});

  /// GET /v1/posts/{postId}/comments
  Future<List<FeedComment>> comments(String postId);

  /// POST /v1/posts/{postId}/comments
  Future<FeedComment> addComment(String postId, String text);

  /// POST /v1/reports
  Future<void> report(String postId, String reason);
}

/// A reference photo of a card's generation (front, left, right or rear),
/// from the catalogue.
class ModelPhoto {
  const ModelPhoto({required this.view, required this.imageUrl, this.credit});
  final String view;

  /// Null while the card is locked: the server only says which views exist.
  final String? imageUrl;
  final String? credit;

  bool get locked => imageUrl == null;

  /// "Front", "Left side", "Right side", "Rear".
  String get viewLabel => switch (view) {
    'front' => 'Front',
    'left' => 'Left side',
    'right' => 'Right side',
    'rear' => 'Rear',
    _ => view,
  };
}

class UnlockResult {
  const UnlockResult({required this.card, required this.coinsCharged});
  final CarCard card;
  final int coinsCharged;
}

abstract interface class CardsRepository {
  /// GET /v1/cards/{cardId}/public-details or /v1/garage/cards/{cardId}
  Future<CarCard> detail(String cardId);

  /// POST /v1/cards/{cardId}/unlock — idempotent on [idempotencyKey].
  Future<UnlockResult> unlock(String cardId, {required String idempotencyKey});

  /// GET /v1/cards/{cardId}/model-photos — the generation's reference photos:
  /// front, left side, right side, rear (any may be missing).
  Future<List<ModelPhoto>> modelPhotos(String cardId);
}

abstract interface class RankingRepository {
  /// GET /v1/leaderboards?scope=&period=
  Future<LeaderboardPage> fetch(LeaderboardScope scope, LeaderboardPeriod period);
}

enum GarageSort {
  newest('Newest'),
  oldest('Oldest'),
  xp('XP'),
  performance('Performance'),
  rarity('Rarity');

  const GarageSort(this.label);
  final String label;
}

class GarageQuery {
  const GarageQuery({this.tier, this.make, this.sort = GarageSort.newest});

  final RarityTier? tier;
  final String? make;
  final GarageSort sort;

  bool get isFiltered => tier != null || make != null;

  GarageQuery copyWith({
    RarityTier? Function()? tier,
    String? Function()? make,
    GarageSort? sort,
  }) => GarageQuery(
    tier: tier != null ? tier() : this.tier,
    make: make != null ? make() : this.make,
    sort: sort ?? this.sort,
  );
}

abstract interface class GarageRepository {
  /// GET /v1/garage/summary
  Future<GarageSummary> summary();

  /// GET /v1/garage/cards?limit=20&cursor=&tier=&makeId=&sort=
  Future<List<CarCard>> cards(GarageQuery query);

  /// Makes present in the user's Garage, for filtering.
  Future<List<String>> makes();
}

/// Outcome of the identify step (spec §2.2 capture states).
sealed class IdentifyOutcome {
  const IdentifyOutcome();
}

class Identified extends IdentifyOutcome {
  const Identified({
    required this.captureId,
    required this.candidate,
    required this.confidence,
    this.duplicateOf,
    this.duplicates = const [],
    this.reviewerConfirmed = false,
  });

  final String captureId;
  final CarCard candidate;

  /// 0–1 AI score. Below 0.85 the UI must present the result cautiously.
  final double confidence;

  /// A moderator confirmed the vehicle; this supersedes the AI score.
  final bool reviewerConfirmed;

  /// Set when the backend flags a likely duplicate in the user's Garage.
  final CarCard? duplicateOf;

  /// Every card of this exact car the player already has, oldest first.
  final List<CarCard> duplicates;

  /// The copies to offer in the duplicate choice.
  List<CarCard> get copies => duplicates.isNotEmpty ? duplicates : [?duplicateOf];
}

class ReviewRequired extends IdentifyOutcome {
  const ReviewRequired(this.captureId);
  final String captureId;
}

class Rejected extends IdentifyOutcome {
  const Rejected(this.reason);
  final String reason;
}

class AddResult {
  const AddResult({
    required this.card,
    required this.coinsAwarded,
    required this.xpAwarded,
    this.replaced = false,
  });

  final CarCard card;
  final int coinsAwarded;
  final int xpAwarded;

  /// The photo went onto an existing card rather than a new one.
  final bool replaced;
}

abstract interface class CaptureRepository {
  /// POST /v1/captures/upload-session → PUT signed URL → POST identify.
  /// [thumbnail], the small copy for Garage grids, is uploaded too when
  /// given; a failed thumbnail upload doesn't stop the scan.
  Future<IdentifyOutcome> identify(
    Uint8List jpegBytes, {
    required String localPath,
    Uint8List? thumbnail,
  });

  /// POST /v1/captures/{id}/add-to-garage (or replace-card when [replace]).
  ///
  /// For a car the player already has: [keepBoth] adds another card (no
  /// rewards); [replace] puts the new photo on a copy, [replaceCardId] when
  /// there are several (default: the oldest).
  Future<AddResult> addToGarage(
    String captureId, {
    bool replace = false,
    String? replaceCardId,
    bool keepBoth = false,
  });

  /// POST /v1/captures/{id}/discard
  Future<void> discard(String captureId);

  /// POST /v1/reports — flags a wrong identification for moderator review.
  Future<void> reportMismatch(String captureId);

  /// GET /v1/captures — the user's captures still awaiting action: ready to
  /// add ([Identified], e.g. approved by a reviewer) or still [ReviewRequired].
  Future<List<IdentifyOutcome>> pending();
}

abstract interface class ProfileRepository {
  /// GET /v1/users/me
  Future<UserProfile> me();

  /// PATCH /v1/users/me. The location is a picked [Country] and optional
  /// [City]; the server derives the state from the city.
  Future<UserProfile> update({
    required String displayName,
    String? bio,
    Country? country,
    City? city,
  });

  /// GET /v1/wallet
  Future<Wallet> wallet();

  /// POST /v1/auth/email/verify/resend — emails a new confirmation link.
  /// Returns true if the address turned out to be confirmed already.
  Future<bool> resendVerification();

  /// GET /v1/goals/today
  Future<DailyGoals> dailyGoals();

  /// POST /v1/notifications/device-token — this install receives pushes.
  Future<void> registerPushToken(String token, {required String platform});

  /// DELETE /v1/notifications/device-token — on sign-out.
  Future<void> unregisterPushToken(String token);
}

abstract interface class GeoRepository {
  /// GET /v1/geo/countries?search=
  Future<List<Country>> countries({String? search});

  /// GET /v1/geo/countries/{code}/cities?search= — largest cities first.
  Future<List<City>> cities(String countryCode, {String? search});
}

abstract interface class UsersRepository {
  /// GET /v1/users/{id}/public-profile
  Future<PublicProfile> publicProfile(String userId);

  /// POST /v1/users/{id}/follow — returns the new follower count.
  Future<int> follow(String userId);

  /// DELETE /v1/users/{id}/follow — returns the new follower count.
  Future<int> unfollow(String userId);

  /// GET /v1/users/{id}/cards?limit=&cursor= — newest first; other spotters'
  /// cards come back with the spec sheet locked.
  Future<CardPage> cards(String userId, {String? cursor, int limit = 12});

  /// GET /v1/users/{id}/followers or /following?limit=&cursor= — most
  /// recent follow first.
  Future<UserPage> follows(String userId, FollowList list, {String? cursor, int limit = 20});
}

/// What a watched rewarded ad was for.
enum RewardPlacement {
  /// One more car today beyond the daily limit.
  extraScan('extra_scan'),

  /// Another spotter's spec sheet, without spending coins.
  cardUnlock('card_unlock');

  const RewardPlacement(this.wire);
  final String wire;
}

/// The server's answer to a reward claim.
sealed class RewardClaim {
  const RewardClaim();
}

/// AdMob's confirmation hasn't reached the server yet: ask again shortly.
class RewardPending extends RewardClaim {
  const RewardPending();
}

class ScanRewardGranted extends RewardClaim {
  const ScanRewardGranted({required this.scansToday, required this.dailyScanLimit});
  final int scansToday;
  final int dailyScanLimit;
}

class UnlockRewardGranted extends RewardClaim {
  const UnlockRewardGranted(this.card);
  final CarCard card;
}

abstract interface class AdsRepository {
  /// POST /v1/ads/reward/verify — claims the reward for an ad shown with
  /// [ref] in its custom data. Granted once; repeating returns the same result.
  Future<RewardClaim> claim({
    required RewardPlacement placement,
    required String ref,
    String? cardId,
  });
}
