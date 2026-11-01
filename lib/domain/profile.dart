import 'rarity_tier.dart';
import 'social.dart';

/// How prestigious a badge is; drives its medal colour.
enum BadgeGrade {
  bronze,
  silver,
  gold,
  platinum;

  static BadgeGrade parse(String? raw) =>
      values.firstWhere((g) => g.name == raw, orElse: () => BadgeGrade.bronze);
}

class SpotterBadge {
  const SpotterBadge({
    required this.id,
    required this.name,
    this.earnedAt,
    this.description = '',
    this.icon = '',
    this.grade = BadgeGrade.bronze,
    this.earned = true,
    this.progress = 0,
    this.target = 1,
  });

  final String id;
  final String name;

  /// Null when the server can't tell when it was earned (likes, followers).
  final DateTime? earnedAt;

  /// How to earn it, e.g. "Have 10 cars in your Garage."
  final String description;

  /// Icon key from the server: camera, collection, crown, gem, flame, star,
  /// globe, heart or people.
  final String icon;
  final BadgeGrade grade;
  final bool earned;

  /// Towards [target]; equal to it once earned.
  final int progress;
  final int target;

  double get fraction => target <= 0 ? 1 : (progress / target).clamp(0, 1).toDouble();
}

/// A country from the location picker (ISO 3166-1 alpha-2 code).
class Country {
  const Country({required this.code, required this.name});
  final String code;
  final String name;

  @override
  bool operator ==(Object other) => other is Country && other.code == code;
  @override
  int get hashCode => code.hashCode;
}

/// A city from the location picker. [regionName] is its state or province.
class City {
  const City({required this.id, required this.name, this.regionName});
  final int id;
  final String name;
  final String? regionName;

  String get label => regionName == null ? name : '$name, $regionName';

  @override
  bool operator ==(Object other) => other is City && other.id == id;
  @override
  int get hashCode => id.hashCode;
}

/// The user's location, as chosen from the country → city picker.
class UserRegion {
  const UserRegion({this.country, this.city});
  final Country? country;
  final City? city;
}

class UserProfile {
  const UserProfile({
    required this.id,
    required this.handle,
    required this.displayName,
    required this.licenseNo,
    required this.level,
    required this.xp,
    required this.xpLevelStart,
    required this.xpNextLevel,
    required this.followers,
    required this.following,
    required this.issuedAt,
    this.bio,
    this.email,
    this.emailVerified = true,
    this.region = const UserRegion(),
    this.badges = const [],
    this.allBadges = const [],
  });

  final String id;
  final String handle;
  final String displayName;
  final String licenseNo;

  /// The signed-in player's own address; only present on their own profile.
  final String? email;

  /// False until the player opens the link in the confirmation email.
  final bool emailVerified;
  final String? bio;
  final int level;
  final int xp;
  final int xpLevelStart;
  final int xpNextLevel;
  final int followers;
  final int following;
  final DateTime issuedAt;

  /// Location used for country/state/city rankings. Set in Edit profile.
  final UserRegion region;

  /// Earned badges, newest first.
  final List<SpotterBadge> badges;

  /// Every badge, earned first, with progress on the rest. Falls back to
  /// [badges] for a server that doesn't send the full list.
  final List<SpotterBadge> allBadges;

  List<SpotterBadge> get badgeCase => allBadges.isEmpty ? badges : allBadges;

  double get levelProgress {
    final span = xpNextLevel - xpLevelStart;
    if (span <= 0) return 1;
    return ((xp - xpLevelStart) / span).clamp(0, 1).toDouble();
  }

  UserProfile copyWith({String? displayName, String? bio, int? xp, UserRegion? region}) =>
      UserProfile(
        id: id,
        handle: handle,
        displayName: displayName ?? this.displayName,
        licenseNo: licenseNo,
        bio: bio ?? this.bio,
        level: level,
        xp: xp ?? this.xp,
        xpLevelStart: xpLevelStart,
        xpNextLevel: xpNextLevel,
        followers: followers,
        following: following,
        issuedAt: issuedAt,
        email: email,
        emailVerified: emailVerified,
        region: region ?? this.region,
        badges: badges,
        allBadges: allBadges,
      );
}

/// Another spotter's public profile, as seen by the viewer.
class PublicProfile {
  const PublicProfile({
    required this.user,
    required this.xp,
    required this.followers,
    required this.following,
    required this.carCount,
    required this.viewerFollows,
    required this.isViewer,
    this.bio,
    this.badges = const [],
  });

  final UserSummary user;
  final String? bio;
  final int xp;
  final int followers;
  final int following;
  final int carCount;
  final bool viewerFollows;
  final bool isViewer;
  final List<SpotterBadge> badges;

  PublicProfile copyWith({bool? viewerFollows, int? followers}) => PublicProfile(
    user: user,
    bio: bio,
    xp: xp,
    followers: followers ?? this.followers,
    following: following,
    carCount: carCount,
    viewerFollows: viewerFollows ?? this.viewerFollows,
    isViewer: isViewer,
    badges: badges,
  );
}

class Wallet {
  const Wallet({required this.coins, required this.adsWatchedToday});

  final int coins;
  final int adsWatchedToday;

  Wallet copyWith({int? coins, int? adsWatchedToday}) =>
      Wallet(coins: coins ?? this.coins, adsWatchedToday: adsWatchedToday ?? this.adsWatchedToday);
}

class GarageSummary {
  const GarageSummary({
    required this.totalCards,
    required this.capacity,
    required this.totalXp,
    required this.tierCounts,
    required this.scansToday,
    required this.dailyScanLimit,
    this.rewardedScansLeft,
  });

  final int totalCards;
  final int capacity;
  final int totalXp;
  final Map<RarityTier, int> tierCounts;
  final int scansToday;
  final int dailyScanLimit;

  /// Extra scans still to be earned with rewarded ads today; null if the
  /// server doesn't say (older versions).
  final int? rewardedScansLeft;

  bool get isFull => totalCards >= capacity;
  int get scansLeftToday => (dailyScanLimit - scansToday).clamp(0, 999);
}
