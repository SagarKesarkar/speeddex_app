import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/errors/app_failure.dart';
import '../../../core/theme/sd_colors.dart';
import '../../../core/theme/sd_tokens.dart';
import '../../../core/theme/sd_typography.dart';
import '../../../core/widgets/sd_button.dart';
import '../../../core/widgets/sd_primitives.dart';
import '../../../core/widgets/sd_states.dart';
import '../../../data/repositories.dart';
import '../../../domain/car_card.dart';
import '../../ads/rewarded_flow.dart';

/// Confirms and performs a hidden-detail unlock (spec §4.2).
///
/// One idempotency key is generated per confirmation so a double tap or retry
/// can never debit twice. Returns the unlocked card, or null if cancelled.
Future<CarCard?> runUnlockFlow(BuildContext context, WidgetRef ref, CarCard card) {
  return showModalBottomSheet<CarCard>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _UnlockSheet(card: card),
  );
}

class _UnlockSheet extends ConsumerStatefulWidget {
  const _UnlockSheet({required this.card});
  final CarCard card;

  @override
  ConsumerState<_UnlockSheet> createState() => _UnlockSheetState();
}

class _UnlockSheetState extends ConsumerState<_UnlockSheet> {
  static const cost = 5;
  final _key = '${DateTime.now().microsecondsSinceEpoch}-${Random.secure().nextInt(1 << 32)}';
  bool _busy = false;
  bool _watching = false;
  String? _adError;
  AppFailure? _failure;

  @override
  void initState() {
    super.initState();
    // Always show the current balance, never a cached one from earlier.
    Future.microtask(() => ref.invalidate(walletProvider));
  }

  Future<void> _unlock() async {
    setState(() {
      _busy = true;
      _failure = null;
    });
    try {
      final result = await ref
          .read(cardsRepositoryProvider)
          .unlock(widget.card.id, idempotencyKey: _key);
      ref.invalidate(walletProvider);
      if (mounted) Navigator.of(context).pop(result.card);
    } on AppFailure catch (f) {
      if (mounted) setState(() => _failure = f);
    } catch (_) {
      if (mounted) setState(() => _failure = const UnknownFailure());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _watchAd() async {
    setState(() {
      _watching = true;
      _adError = null;
    });
    final result = await watchRewardedAd(ref, RewardPlacement.cardUnlock, cardId: widget.card.id);
    if (!mounted) return;
    setState(() => _watching = false);
    switch (result) {
      case AdRewardGranted(claim: UnlockRewardGranted(:final card)):
        Navigator.of(context).pop(card);
      case AdRewardGranted():
        setState(() => _adError = 'Something went wrong. Please try again.');
      case AdRewardFailed(:final message):
        setState(() => _adError = message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final wallet = ref.watch(walletProvider);
    // While refreshing, show the balance only once it's current.
    final balance = wallet.isLoading ? null : wallet.value?.coins;
    // The server is the authority on whether the user can pay: the ad option
    // appears only after it answers INSUFFICIENT_COINS, or when the fresh
    // balance is definitely too low.
    final short = switch (_failure) {
      InsufficientCoinsFailure() => true,
      _ => balance != null && balance < cost,
    };
    final shortBy = switch (_failure) {
      InsufficientCoinsFailure(:final required, :final balance) => required - balance,
      _ => cost - (balance ?? 0),
    };

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(SdSpace.gutter, 0, SdSpace.gutter, SdSpace.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('UNLOCK CARD DETAILS', style: SdType.heading),
            const SizedBox(height: SdSpace.sm),
            Text(
              'Reveal the engine, fuel, drivetrain, gearbox, weight, size and photos '
              'of the ${widget.card.displayName}. Unlocks are permanent.',
              style: SdType.body.copyWith(color: SdColors.textMuted),
            ),
            const SizedBox(height: SdSpace.xl),
            SdPanel(
              child: Row(
                children: [
                  Text('COST', style: SdType.label),
                  const Spacer(),
                  const CoinGlyph(),
                  const SizedBox(width: 6),
                  Text(
                    '$cost',
                    style: SdType.dataLarge.copyWith(color: SdColors.gold, fontSize: 18),
                  ),
                  const SizedBox(width: SdSpace.xl),
                  Text('BALANCE', style: SdType.label),
                  const SizedBox(width: SdSpace.sm),
                  Text(balance?.toString() ?? '—', style: SdType.data),
                ],
              ),
            ),
            const SizedBox(height: SdSpace.lg),
            if (_failure != null && _failure is! InsufficientCoinsFailure) ...[
              SdInlineError(message: _failure!.message, onRetry: _unlock),
              const SizedBox(height: SdSpace.lg),
            ],
            if (short) ...[
              Text(
                'You need $shortBy more coins. Earn coins by adding new '
                'cars to your Garage, or watch a rewarded ad.',
                style: SdType.caption.copyWith(color: SdColors.text),
              ),
              const SizedBox(height: SdSpace.lg),
              if (_adError != null) ...[
                SdInlineError(message: _adError!),
                const SizedBox(height: SdSpace.md),
              ],
              // The server grants the unlock only once the ad is confirmed watched.
              SdButton(
                label: 'Watch an ad to unlock free',
                icon: Icons.play_circle_outline_rounded,
                variant: SdButtonVariant.gold,
                loading: _watching,
                onPressed: _watchAd,
              ),
            ] else
              SdButton(
                label: 'Unlock for $cost coins',
                variant: SdButtonVariant.gold,
                loading: _busy || wallet.isLoading,
                onPressed: _unlock,
              ),
            const SizedBox(height: SdSpace.sm),
            SdButton(
              label: 'Not now',
              variant: SdButtonVariant.ghost,
              onPressed: _busy || _watching ? null : () => Navigator.of(context).pop(),
            ),
          ],
        ),
      ),
    );
  }
}
