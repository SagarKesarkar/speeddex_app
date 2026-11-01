import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

/// Which ads the build shows, from `--dart-define=ADS_MODE=`:
/// - `test` (default): Google's sample ad units. Always use these while
///   developing and testing: clicking your own live ads can get the AdMob
///   account suspended.
/// - `live`: SpeedDex's own ad units. Only for store builds.
/// - `off`: no ads at all.
enum AdsMode { test, live, off }

class AdsConfig {
  const AdsConfig._(this.mode);

  factory AdsConfig.fromEnvironment() =>
      AdsConfig._(switch (const String.fromEnvironment('ADS_MODE')) {
        'live' => AdsMode.live,
        'off' => AdsMode.off,
        _ => AdsMode.test,
      });

  final AdsMode mode;

  /// Ads run on Android only for now: there is no iOS AdMob app yet.
  bool get enabled =>
      mode != AdsMode.off && !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// Banner shown between Feed posts.
  String get feedBannerUnit => mode == AdsMode.live
      ? 'ca-app-pub-1566668211654188/3613905313'
      : 'ca-app-pub-3940256099942544/9214589741'; // Google's sample adaptive banner

  /// Rewarded ad for an extra scan or a spec-sheet unlock.
  String get rewardedUnit => mode == AdsMode.live
      ? 'ca-app-pub-1566668211654188/7536391340'
      : 'ca-app-pub-3940256099942544/5224354917'; // Google's sample rewarded ad
}

/// Starts the Mobile Ads SDK once consent allows it.
///
/// Consent comes first: Google's User Messaging Platform shows the consent
/// form where the law requires one (EEA, UK, Switzerland) and nowhere else.
/// Ads are requested only if [ConsentInformation.canRequestAds] says so.
class AdsService {
  AdsService(this.config);
  final AdsConfig config;

  Future<bool>? _ready;

  /// True once ads may be requested. Safe to call many times.
  Future<bool> ready() => _ready ??= _start();

  Future<bool> _start() async {
    if (!config.enabled) return false;
    try {
      final updated = Completer<void>();
      ConsentInformation.instance.requestConsentInfoUpdate(
        ConsentRequestParameters(),
        () => updated.complete(),
        (_) => updated.complete(), // Offline or unconfigured: fall back to the stored state.
      );
      await updated.future;
      final dismissed = Completer<void>();
      await ConsentForm.loadAndShowConsentFormIfRequired((_) => dismissed.complete());
      await dismissed.future;
      if (!await ConsentInformation.instance.canRequestAds()) return false;
      await MobileAds.instance.initialize();
      return true;
    } catch (_) {
      // Ads are optional: the app works without them.
      _ready = null;
      return false;
    }
  }
}

/// How a rewarded ad ended.
enum RewardedOutcome { earned, closedEarly, unavailable }

extension RewardedAds on AdsService {
  /// Loads and shows one rewarded ad. [userId] and [customData] travel to
  /// AdMob's server-side verification callback, which is how the server
  /// knows the ad was really watched.
  Future<RewardedOutcome> showRewarded({required String userId, required String customData}) async {
    if (!await ready()) return RewardedOutcome.unavailable;
    final loaded = Completer<RewardedAd?>();
    await RewardedAd.load(
      adUnitId: config.rewardedUnit,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: loaded.complete,
        onAdFailedToLoad: (_) => loaded.complete(null),
      ),
    );
    final ad = await loaded.future.timeout(const Duration(seconds: 20), onTimeout: () => null);
    if (ad == null) return RewardedOutcome.unavailable;

    var earned = false;
    final closed = Completer<void>();
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (a) {
        a.dispose();
        if (!closed.isCompleted) closed.complete();
      },
      onAdFailedToShowFullScreenContent: (a, _) {
        a.dispose();
        if (!closed.isCompleted) closed.complete();
      },
    );
    await ad.setServerSideOptions(
      ServerSideVerificationOptions(userId: userId, customData: customData),
    );
    await ad.show(onUserEarnedReward: (_, _) => earned = true);
    await closed.future;
    return earned ? RewardedOutcome.earned : RewardedOutcome.closedEarly;
  }
}
