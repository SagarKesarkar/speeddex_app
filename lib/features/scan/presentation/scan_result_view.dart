import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../core/errors/app_failure.dart';
import '../../../core/theme/sd_colors.dart';
import '../../../core/theme/sd_tokens.dart';
import '../../../core/theme/sd_typography.dart';
import '../../../core/util/format.dart';
import '../../../core/widgets/brand.dart';
import '../../../core/widgets/sd_button.dart';
import '../../../core/widgets/sd_primitives.dart';
import '../../../core/widgets/sd_states.dart';
import '../../ads/rewarded_flow.dart';
import '../../cards/application/share_card.dart';
import '../../cards/presentation/collector_card.dart';
import '../application/scan_controller.dart';
import 'daily_limit_offer.dart';
import 'duplicate_sheet.dart';

/// Candidate card after identification, and the confirmation after adding.
class ScanResultView extends ConsumerWidget {
  const ScanResultView({super.key});

  Future<void> _add(BuildContext context, WidgetRef ref, ScanResult s) async {
    final ctrl = ref.read(scanControllerProvider.notifier);
    final copies = s.outcome.copies;
    if (copies.isEmpty) return ctrl.addToGarage();
    final choice = await showDuplicateSheet(
      context,
      candidate: s.outcome.candidate,
      copies: copies,
    );
    switch (choice) {
      case KeepBoth():
        await ctrl.addToGarage(keepBoth: true);
      case ReplaceCard(:final cardId):
        await ctrl.addToGarage(replace: true, replaceCardId: cardId);
      case DiscardScan():
        await ctrl.retake();
      case null:
        break; // dismissed: stay on the result
    }
  }

  Future<void> _report(BuildContext context, WidgetRef ref, ScanResult s) async {
    try {
      await ref.read(captureRepositoryProvider).reportMismatch(s.outcome.captureId);
      if (context.mounted) {
        showSdSnack(context, 'Thanks. A reviewer will check this match.', success: true);
      }
    } catch (e) {
      if (context.mounted) showSdSnack(context, e.userMessage);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(scanControllerProvider);
    return SafeArea(
      bottom: false,
      child: Stack(
        children: [
          const Positioned.fill(child: Pinstripe(opacity: 0.025)),
          switch (state) {
            ScanResult() => _Candidate(
              state: state,
              onAdd: () => _add(context, ref, state),
              // Granted: add the card the limit stopped.
              onWatchAd: () async {
                if (await earnExtraScan(context, ref) && context.mounted) {
                  await _add(context, ref, state);
                }
              },
              onSkip: ref.read(scanControllerProvider.notifier).retake,
              onReport: () => _report(context, ref, state),
              devSample: ref.watch(appConfigProvider).usesDevData,
              dailyLimit: ref.watch(garageSummaryProvider).value?.dailyScanLimit,
              adScansLeft: ref.watch(garageSummaryProvider).value?.rewardedScansLeft,
            ),
            ScanAdded() => _Added(state: state),
            _ => const SizedBox.shrink(),
          },
        ],
      ),
    );
  }
}

class _Candidate extends StatelessWidget {
  const _Candidate({
    required this.state,
    required this.onAdd,
    required this.onWatchAd,
    required this.onSkip,
    required this.onReport,
    this.devSample = false,
    this.dailyLimit,
    this.adScansLeft,
  });

  final ScanResult state;
  final VoidCallback onAdd;
  final Future<void> Function() onWatchAd;
  final VoidCallback onSkip;
  final VoidCallback onReport;

  /// True when no recognition service is connected and the result is a fixture.
  final bool devSample;

  /// Cars a day on the free plan, for the limit message.
  final int? dailyLimit;

  /// Extra scans still to be earned with ads today.
  final int? adScansLeft;

  @override
  Widget build(BuildContext context) {
    final o = state.outcome;
    final pct = (o.confidence * 100).round();
    final confident = state.isConfident;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            SdSpace.gutter,
            SdSpace.xl,
            SdSpace.gutter,
            SdSpace.xxl,
          ),
          children: [
            Text(
              confident ? 'CAUGHT!' : 'LIKELY MATCH',
              textAlign: TextAlign.center,
              style: SdType.hero.copyWith(color: confident ? SdColors.text : SdColors.warning),
            ),
            const SizedBox(height: SdSpace.sm),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  confident ? Icons.verified_rounded : Icons.help_outline_rounded,
                  size: 16,
                  color: confident ? SdColors.gold : SdColors.warning,
                ),
                const SizedBox(width: 6),
                Text(
                  o.reviewerConfirmed
                      ? 'CONFIRMED BY REVIEWER'
                      : '${confident ? 'IDENTIFIED' : 'UNCONFIRMED'} · AI $pct%',
                  style: SdType.label.copyWith(color: confident ? SdColors.gold : SdColors.warning),
                ),
                if (o.duplicateOf == null) ...[
                  const SizedBox(width: SdSpace.md),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    color: SdColors.gold,
                    child: Text(
                      'NEW',
                      style: SdType.label.copyWith(
                        color: SdColors.ink,
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ],
            ),
            if (!confident) ...[
              const SizedBox(height: SdSpace.lg),
              SdPanel(
                accent: SdColors.warning,
                padding: const EdgeInsets.all(SdSpace.md),
                child: Text(
                  'We’re not fully certain about this one. Check the make and model '
                  'before adding, or report a bad match.',
                  style: SdType.caption.copyWith(color: SdColors.text),
                ),
              ),
            ],
            if (devSample) ...[
              const SizedBox(height: SdSpace.lg),
              SdPanel(
                accent: SdColors.warning,
                padding: const EdgeInsets.all(SdSpace.md),
                child: Text(
                  'Development sample. No recognition service is connected, so this '
                  'vehicle and confidence score were not derived from your photo.',
                  style: SdType.caption.copyWith(color: SdColors.warning),
                ),
              ),
            ],
            const SizedBox(height: SdSpace.xl),
            RepaintBoundary(
              key: _shareKey,
              child: CollectorCard(card: o.candidate, footerNote: '+${o.candidate.xp} XP'),
            ),
            const SizedBox(height: SdSpace.lg),
            // The limit can also be reached between identifying and adding.
            if (state.error is DailyScanLimitFailure) ...[
              SdPanel(
                accent: SdColors.gold,
                child: DailyLimitOffer(
                  limit: dailyLimit,
                  adScansLeft: adScansLeft,
                  onWatchAd: onWatchAd,
                ),
              ),
              const SizedBox(height: SdSpace.lg),
            ] else if (state.error != null) ...[
              SdInlineError(
                message: state.error!.userMessage,
                onRetry: state.error is AppFailure && (state.error as AppFailure).retryable
                    ? onAdd
                    : null,
              ),
              const SizedBox(height: SdSpace.lg),
            ],
            Row(
              children: [
                Expanded(
                  child: SdButton(
                    label: 'Skip',
                    variant: SdButtonVariant.secondary,
                    onPressed: state.adding ? null : onSkip,
                  ),
                ),
                const SizedBox(width: SdSpace.md),
                Expanded(
                  flex: 2,
                  child: SdButton(
                    label: 'Add to Garage',
                    icon: Icons.garage_rounded,
                    loading: state.adding,
                    onPressed: onAdd,
                  ),
                ),
              ],
            ),
            const SizedBox(height: SdSpace.md),
            ShareCardButton(boundary: _shareKey, card: o.candidate),
            const SizedBox(height: SdSpace.sm),
            Center(
              child: TextButton(
                onPressed: state.adding ? null : onReport,
                child: Text(
                  'WRONG CAR? REPORT A BAD MATCH',
                  style: SdType.label.copyWith(fontSize: 11),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Added extends ConsumerWidget {
  const _Added({required this.state});
  final ScanAdded state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final r = state.result;
    final replaced = r.replaced;
    // A kept repeat of a car already collected earns nothing.
    final repeat = !replaced && r.coinsAwarded == 0 && r.xpAwarded == 0;
    final ctrl = ref.read(scanControllerProvider.notifier);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            SdSpace.gutter,
            SdSpace.xl,
            SdSpace.gutter,
            SdSpace.xxl,
          ),
          children: [
            Text(
              replaced ? 'CARD REPLACED' : 'IN THE GARAGE',
              textAlign: TextAlign.center,
              style: SdType.hero.copyWith(fontSize: 34),
            ),
            const SizedBox(height: SdSpace.lg),
            if (replaced || repeat)
              Text(
                replaced
                    ? 'Replacements keep your history and earn no new rewards.'
                    : 'Another one for your collection. Repeats earn no coins or XP.',
                textAlign: TextAlign.center,
                style: SdType.caption,
              )
            else
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _Reward(icon: const CoinGlyph(size: 18), text: '+${r.coinsAwarded}'),
                  const SizedBox(width: SdSpace.lg),
                  _Reward(
                    icon: const Icon(Icons.bolt_rounded, color: SdColors.gold, size: 20),
                    text: '+${SdFormat.number(r.xpAwarded)} XP',
                  ),
                ],
              ),
            const SizedBox(height: SdSpace.xl),
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0.92, end: 1),
              duration: SdMotion.slow,
              curve: Curves.easeOutBack,
              builder: (context, v, child) => Transform.scale(scale: v, child: child),
              child: RepaintBoundary(
                key: _addedShareKey,
                child: CollectorCard(card: r.card, showSpecSheet: false),
              ),
            ),
            const SizedBox(height: SdSpace.lg),
            Row(
              children: [
                Expanded(
                  child: SdButton(
                    label: 'View Garage',
                    variant: SdButtonVariant.secondary,
                    onPressed: () {
                      ctrl.reset();
                      context.go('/garage');
                    },
                  ),
                ),
                const SizedBox(width: SdSpace.md),
                Expanded(
                  child: SdButton(label: 'Scan next', onPressed: ctrl.reset),
                ),
              ],
            ),
            // Same place on every card screen: right under the main actions.
            const SizedBox(height: SdSpace.md),
            ShareCardButton(boundary: _addedShareKey, card: r.card),
          ],
        ),
      ),
    );
  }
}

class _Reward extends StatelessWidget {
  const _Reward({required this.icon, required this.text});
  final Widget icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: SdSpace.lg, vertical: SdSpace.sm),
      decoration: BoxDecoration(
        borderRadius: const BorderRadius.all(SdRadius.sm),
        border: Border.all(color: SdColors.goldDeep),
        color: SdColors.gold.withValues(alpha: 0.08),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          icon,
          const SizedBox(width: SdSpace.sm),
          Text(text, style: SdType.dataLarge.copyWith(fontSize: 18, color: SdColors.gold)),
        ],
      ),
    );
  }
}

// One card is on screen at a time, so each view can keep a single key.
final _shareKey = GlobalKey(debugLabel: 'share-candidate');
final _addedShareKey = GlobalKey(debugLabel: 'share-added');
