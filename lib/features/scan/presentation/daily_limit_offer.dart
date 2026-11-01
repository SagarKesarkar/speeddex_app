import 'package:flutter/material.dart';

import '../../../core/theme/sd_colors.dart';
import '../../../core/theme/sd_tokens.dart';
import '../../../core/theme/sd_typography.dart';
import '../../../core/widgets/sd_button.dart';
import '../../../core/widgets/sd_states.dart';

/// Shown when the daily scan limit stops a car from being identified or
/// added: the bad news, and two ways to keep going today — Premium or a
/// rewarded ad, which earns one more scan.
///
/// Premium needs store billing, which doesn't exist yet, so its button says
/// so. [onWatchAd] shows the ad and carries on with the scan if it's granted.
class DailyLimitOffer extends StatefulWidget {
  const DailyLimitOffer({super.key, this.limit, this.adScansLeft, this.onPremium, this.onWatchAd});

  /// Cars a day on the free plan, if known.
  final int? limit;

  /// Extra scans still to be earned with ads today, if known. At 0 the ad
  /// button is disabled, so nobody watches an ad that can't pay out.
  final int? adScansLeft;
  final VoidCallback? onPremium;
  final Future<void> Function()? onWatchAd;

  @override
  State<DailyLimitOffer> createState() => _DailyLimitOfferState();
}

class _DailyLimitOfferState extends State<DailyLimitOffer> {
  bool _watching = false;

  Future<void> _watch() async {
    setState(() => _watching = true);
    try {
      await widget.onWatchAd!();
    } finally {
      if (mounted) setState(() => _watching = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final limit = widget.limit;
    final onPremium = widget.onPremium;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: SdColors.gold.withValues(alpha: 0.12),
              border: Border.all(color: SdColors.goldDeep),
            ),
            child: const Icon(Icons.timer_outlined, color: SdColors.gold, size: 28),
          ),
        ),
        const SizedBox(height: SdSpace.lg),
        Semantics(
          header: true,
          child: Text(
            'OH NO!',
            textAlign: TextAlign.center,
            style: SdType.hero.copyWith(fontSize: 34),
          ),
        ),
        const SizedBox(height: SdSpace.xs),
        Text(
          'DAILY LIMIT REACHED',
          textAlign: TextAlign.center,
          style: SdType.label.copyWith(color: SdColors.gold, letterSpacing: 2),
        ),
        const SizedBox(height: SdSpace.md),
        Text(
          '${limit == null ? 'You’ve' : 'You’ve added $limit cars today and'} used all of '
          'today’s free scans. Still want this one in your Garage? '
          '${widget.adScansLeft == 0 ? 'Go Premium.' : 'Go Premium or watch a rewarded ad.'}',
          textAlign: TextAlign.center,
          style: SdType.body.copyWith(color: SdColors.text, height: 1.45),
        ),
        const SizedBox(height: SdSpace.xl),
        SdButton(
          label: 'Go Premium',
          icon: Icons.workspace_premium_rounded,
          variant: SdButtonVariant.gold,
          onPressed:
              onPremium ??
              () => showSdSnack(context, 'Premium isn’t available yet. It’s coming soon.'),
        ),
        const SizedBox(height: SdSpace.sm),
        if (widget.adScansLeft == 0)
          const SdButton(
            label: 'No more ad scans today',
            icon: Icons.play_circle_outline_rounded,
            variant: SdButtonVariant.secondary,
            onPressed: null,
          )
        else
          SdButton(
            label: widget.adScansLeft == null
                ? 'Watch reward ad · +1 scan'
                : 'Watch reward ad · +1 scan (${widget.adScansLeft} left)',
            icon: Icons.play_circle_outline_rounded,
            variant: SdButtonVariant.secondary,
            loading: _watching,
            onPressed: widget.onWatchAd == null
                ? () => showSdSnack(
                    context,
                    'Rewarded ads aren’t available yet. They’re coming soon.',
                  )
                : _watch,
          ),
        const SizedBox(height: SdSpace.md),
        Text(
          widget.adScansLeft == 0
              ? 'You’ve used all of today’s extra scans from ads. '
                    '${onPremium == null ? 'Premium is coming soon. ' : ''}Scans reset at midnight UTC.'
              : '${onPremium == null ? 'Premium is coming soon. ' : ''}Free scans reset at midnight UTC.',
          textAlign: TextAlign.center,
          style: SdType.caption.copyWith(color: SdColors.textMuted),
        ),
      ],
    );
  }
}
