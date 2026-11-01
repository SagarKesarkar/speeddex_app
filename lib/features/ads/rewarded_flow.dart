import 'dart:math';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/ads/ads.dart';
import '../../core/errors/app_failure.dart';
import '../../core/widgets/sd_states.dart';
import '../../data/repositories.dart';

/// How a "watch an ad" attempt ended, for the caller to act on and explain.
sealed class AdReward {
  const AdReward();
}

class AdRewardGranted extends AdReward {
  const AdRewardGranted(this.claim);
  final RewardClaim claim;
}

/// Closed before the end, no ad to show, or the server couldn't confirm it.
class AdRewardFailed extends AdReward {
  const AdRewardFailed(this.message);
  final String message;
}

/// Shows a rewarded ad for [placement] and claims its reward from the server.
///
/// The ad carries a fresh reference in its custom data. AdMob sends that,
/// signed, to the server, and the app then claims the reward by the same
/// reference, retrying for a few seconds while the confirmation arrives.
Future<AdReward> watchRewardedAd(WidgetRef ref, RewardPlacement placement, {String? cardId}) async {
  final String userId;
  try {
    userId = (await ref.read(profileProvider.future)).id;
  } catch (e) {
    return AdRewardFailed(e.userMessage);
  }
  final reference = _reference();
  final customData = [placement.wire, reference, ?cardId].join(':');

  final outcome = await ref
      .read(adsServiceProvider)
      .showRewarded(userId: userId, customData: customData);
  switch (outcome) {
    case RewardedOutcome.unavailable:
      return const AdRewardFailed('No ad is available right now. Try again in a minute.');
    case RewardedOutcome.closedEarly:
      return const AdRewardFailed(
        'The ad was closed before the end, so there’s no reward this time.',
      );
    case RewardedOutcome.earned:
      break;
  }

  final ads = ref.read(adsRepositoryProvider);
  for (var attempt = 0; attempt < 8; attempt++) {
    try {
      final claim = await ads.claim(placement: placement, ref: reference, cardId: cardId);
      if (claim is! RewardPending) return AdRewardGranted(claim);
    } on AppFailure catch (f) {
      if (!f.retryable) return AdRewardFailed(f.message);
    }
    await Future<void>.delayed(const Duration(seconds: 2));
  }
  return const AdRewardFailed(
    'We couldn’t confirm the ad yet. If it doesn’t show up in a minute, try another one.',
  );
}

/// 32 random hex characters: unguessable, and fine in AdMob custom data.
String _reference() {
  final r = Random.secure();
  return List.generate(32, (_) => r.nextInt(16).toRadixString(16)).join();
}

/// Watches an ad for one more scan today. True if it was granted (the caller
/// then carries on with the scan); otherwise the reason has been shown.
Future<bool> earnExtraScan(BuildContext context, WidgetRef ref) async {
  final result = await watchRewardedAd(ref, RewardPlacement.extraScan);
  ref.invalidate(garageSummaryProvider);
  if (!context.mounted) return false;
  switch (result) {
    case AdRewardGranted():
      showSdSnack(context, 'Extra scan unlocked. Thanks for watching!', success: true);
      return true;
    case AdRewardFailed(:final message):
      showSdSnack(context, message);
      return false;
  }
}
