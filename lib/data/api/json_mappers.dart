import '../../domain/car_card.dart';
import '../../domain/goals.dart';
import '../../domain/profile.dart';
import '../../domain/rarity_tier.dart';
import '../../domain/social.dart';

typedef Json = Map<String, dynamic>;

/// Converts API JSON into domain models. Unknown or missing values fall back
/// conservatively; server-provided text is treated as plain data.
class ApiMappers {
  const ApiMappers(this.rebaseUrl);

  /// Points server-issued media URLs at the client's configured API host.
  final String Function(String) rebaseUrl;

  static int _int(Object? v, [int fallback = 0]) => (v as num?)?.toInt() ?? fallback;
  static int? _intOrNull(Object? v) => (v as num?)?.toInt();
  static double? _doubleOrNull(Object? v) => (v as num?)?.toDouble();
  static DateTime _date(Object? v) =>
      DateTime.tryParse(v as String? ?? '')?.toLocal() ?? DateTime.now();

  static BodyStyle bodyStyle(String? s) =>
      BodyStyle.values.where((b) => b.name == s).firstOrNull ?? BodyStyle.sedan;

  UserSummary user(Json j) => UserSummary(
    id: '${j['userId']}',
    handle: j['username'] as String? ?? '',
    displayName: (j['displayName'] ?? j['username'] ?? '') as String,
    level: _int(j['level'], 1),
  );

  CarCard card(Json j, {String? localImagePath}) {
    final specs = (j['specs'] as Map).cast<String, dynamic>();
    final hidden = (j['hidden'] as Map?)?.cast<String, dynamic>();
    final capture = (j['capture'] as Map?)?.cast<String, dynamic>();
    final id = j['cardId'];
    return CarCard(
      id: id == null ? '' : '$id',
      vehicleId: '${j['vehicleId']}',
      // Cards get a serial when added; the header shows its last segment.
      serial: j['serial'] as String? ?? 'SDX-NEW',
      make: j['make'] as String,
      model: j['model'] as String,
      variant: j['variant'] as String?,
      yearLabel: j['yearLabel'] as String? ?? '',
      category: j['category'] as String? ?? '',
      origin: j['origin'] as String? ?? '',
      bodyStyle: bodyStyle(j['bodyStyle'] as String?),
      tier: RarityTier.tryParse(j['rarity'] as String?) ?? RarityTier.base,
      // Every figure is optional: null means "not in the catalogue", never 0.
      specs: VehicleSpecs(
        topSpeedMph: _intOrNull(specs['topSpeedMph']),
        horsepower: _intOrNull(specs['horsepower']),
        zeroToSixtySeconds: _doubleOrNull(specs['zeroToSixtySeconds']),
        engine: specs['engine'] as String?,
        displacementCc: _intOrNull(specs['displacementCc']),
        fuelType: specs['fuelType'] as String?,
      ),
      hidden: hidden == null
          ? null
          : HiddenSpecs(
              manufacturer: hidden['manufacturer'] as String?,
              parentCompany: hidden['parentCompany'] as String?,
              productionStatus: hidden['productionStatus'] as String?,
              cylinders: _intOrNull(hidden['cylinders']),
              induction: hidden['induction'] as String?,
              torqueNm: _intOrNull(hidden['torqueNm']),
              curbWeightKg: _intOrNull(hidden['curbWeightKg']),
              drivetrain: hidden['drivetrain'] as String?,
              transmission: hidden['transmission'] as String?,
              lengthMm: _intOrNull(hidden['lengthMm']),
              widthMm: _intOrNull(hidden['widthMm']),
              heightMm: _intOrNull(hidden['heightMm']),
              wheelbaseMm: _intOrNull(hidden['wheelbaseMm']),
              seating: _intOrNull(hidden['seating']),
              doors: _intOrNull(hidden['doors']),
              batteryKwh: _doubleOrNull(hidden['batteryKwh']),
              evRangeMiles: _intOrNull(hidden['evRangeMiles']),
              msrp: _doubleOrNull(hidden['msrp']),
            ),
      capture: capture == null
          ? null
          : CaptureFacts(
              color: capture['color'] as String?,
              aiConfidence: _doubleOrNull(capture['aiConfidence']),
              addedAt: capture['addedAt'] == null ? null : _date(capture['addedAt']),
            ),
      about: switch (j['about']) {
        {'summary': final String summary} && final Map a => CarAbout(
          summary: summary,
          sourceUrl: a['sourceUrl'] as String?,
          license: a['license'] as String?,
        ),
        _ => null,
      },
      hiddenUnlocked: j['hiddenUnlocked'] == true,
      ownedByViewer: j['ownedByViewer'] == true,
      capturedAt: _date(j['capturedAt']),
      locationLabel: j['locationLabel'] as String?,
      conditionRating: (j['conditionRating'] as num?)?.toDouble(),
      xp: _int(j['xp']),
      imagePath: localImagePath,
      imageUrl: j['imageUrl'] == null ? null : rebaseUrl(j['imageUrl'] as String),
      thumbUrl: j['thumbUrl'] == null ? null : rebaseUrl(j['thumbUrl'] as String),
      post: switch (j['post']) {
        final Map<String, Object?> p => PostStats(
          postId: '${p['postId']}',
          likeCount: _int(p['likeCount']),
          commentCount: _int(p['commentCount']),
        ),
        _ => null,
      },
    );
  }

  FeedPost post(Json j) => FeedPost(
    id: '${j['postId']}',
    author: user((j['author'] as Map).cast()),
    card: card((j['card'] as Map).cast()),
    likeCount: _int(j['likeCount']),
    commentCount: _int(j['commentCount']),
    viewerHasLiked: j['viewerHasLiked'] == true,
    createdAt: _date(j['createdAt']),
  );

  FeedComment comment(Json j) => FeedComment(
    id: '${j['commentId']}',
    author: user((j['user'] as Map).cast()),
    text: j['commentText'] as String? ?? '',
    createdAt: _date(j['createdAt']),
  );

  LeaderboardEntry entry(Json j) => LeaderboardEntry(
    rank: _int(j['rank']),
    user: user((j['user'] as Map).cast()),
    xp: _int(j['xp']),
    carCount: _int(j['carCount']),
    isViewer: j['isViewer'] == true,
  );

  UserProfile profile(Json j) {
    final region = (j['region'] as Map?)?.cast<String, dynamic>() ?? const {};
    return UserProfile(
      id: '${j['userId']}',
      handle: j['username'] as String? ?? '',
      displayName: j['displayName'] as String? ?? '',
      licenseNo: j['licenseNo'] as String? ?? '',
      bio: j['bio'] as String?,
      email: j['email'] as String?,
      // Older servers don't send it: don't nag about something they can't do.
      emailVerified: j['emailVerified'] != false,
      level: _int(j['level'], 1),
      xp: _int(j['xp']),
      xpLevelStart: _int(j['levelStartXp']),
      xpNextLevel: _int(j['nextLevelXp'], 100),
      followers: _int(j['followers']),
      following: _int(j['following']),
      issuedAt: _date(j['issuedAt'] ?? j['memberSince']),
      region: UserRegion(
        country: region['countryCode'] == null
            ? null
            : Country(
                code: region['countryCode'] as String,
                name: region['countryName'] as String? ?? region['countryCode'] as String,
              ),
        city: region['cityId'] == null
            ? null
            : City(
                id: _int(region['cityId']),
                name: region['city'] as String? ?? '',
                regionName: region['stateName'] as String?,
              ),
      ),
      badges: _badges(j['badges']),
      allBadges: _badges(j['allBadges']),
    );
  }

  static List<SpotterBadge> _badges(Object? list) => [
    for (final b in (list as List?) ?? const [])
      SpotterBadge(
        id: (b as Map)['id'] as String,
        name: b['name'] as String,
        description: b['description'] as String? ?? '',
        icon: b['icon'] as String? ?? '',
        grade: BadgeGrade.parse(b['grade'] as String?),
        earnedAt: b['earnedAt'] == null ? null : DateTime.tryParse(b['earnedAt'] as String),
        earned: b['earned'] as bool? ?? true,
        progress: (b['progress'] as num?)?.toInt() ?? 1,
        target: (b['target'] as num?)?.toInt() ?? 1,
      ),
  ];

  DailyGoals dailyGoals(Json j) {
    final bonus = (j['bonus'] as Map).cast<String, Object?>();
    return DailyGoals(
      goals: [
        for (final g in (j['goals'] as List).cast<Map>())
          DailyGoal(
            id: g['goalId'] as String,
            title: g['title'] as String,
            description: g['description'] as String? ?? '',
            progress: _int(g['progress']),
            target: _int(g['target']),
            xp: _int(g['xp']),
            completed: g['completed'] == true,
          ),
      ],
      bonusTitle: bonus['title'] as String,
      bonusXp: _int(bonus['xp']),
      bonusCompleted: bonus['completed'] == true,
      xpEarnedToday: _int(j['xpEarnedToday']),
      resetsAt: _date(j['resetsAt']),
    );
  }

  PublicProfile publicProfile(Json j) => PublicProfile(
    user: user(j),
    bio: j['bio'] as String?,
    xp: _int(j['xp']),
    followers: _int(j['followers']),
    following: _int(j['following']),
    carCount: _int(j['carCount']),
    viewerFollows: j['viewerFollows'] == true,
    isViewer: j['isViewer'] == true,
    badges: _badges(j['badges']),
  );

  Country country(Json j) => Country(code: j['code'] as String, name: j['name'] as String);

  City city(Json j) => City(
    id: _int(j['cityId']),
    name: j['name'] as String,
    regionName: (j['region'] as Map?)?['name'] as String?,
  );

  GarageSummary garage(Json j) => GarageSummary(
    totalCards: _int(j['totalCards']),
    capacity: _int(j['capacity'], 100),
    totalXp: _int(j['totalXp']),
    tierCounts: {
      for (final e in ((j['tierCounts'] as Map?) ?? const {}).entries)
        ?RarityTier.tryParse(e.key as String): _int(e.value),
    },
    scansToday: _int(j['scansToday']),
    dailyScanLimit: _int(j['dailyScanLimit'], 5),
    rewardedScansLeft: (j['rewardedScansLeft'] as num?)?.toInt(),
  );
}
