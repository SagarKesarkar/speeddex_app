import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/sd_colors.dart';
import '../../../core/theme/sd_tokens.dart';
import '../../../core/theme/sd_typography.dart';
import '../../../core/util/format.dart';
import '../../../core/widgets/car_visual.dart';
import '../../../core/widgets/sd_primitives.dart';
import '../../../domain/car_card.dart';

/// Compact Car Card for grids (Garage, a spotter's profile). Opens the full
/// card; other spotters' cards show a lock until their spec sheet is unlocked.
class CardGridTile extends StatelessWidget {
  const CardGridTile({super.key, required this.card, this.onTap});
  final CarCard card;

  /// Defaults to opening the card.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = card.tier;
    final locked = !card.ownedByViewer && !card.hiddenUnlocked;
    return Semantics(
      button: true,
      label:
          '${card.displayName}, ${t.label}, caught ${SdFormat.date(card.capturedAt)}'
          '${locked ? ', details locked' : ''}',
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap ?? () => context.push('/card/${card.id}'),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: const BorderRadius.all(SdRadius.md),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: t.isFoil
                  ? [t.color, t.deep, t.color]
                  : [t.color.withValues(alpha: 0.7), t.deep],
            ),
          ),
          padding: const EdgeInsets.all(2),
          child: Container(
            decoration: const BoxDecoration(
              color: SdColors.surface,
              borderRadius: BorderRadius.all(Radius.circular(8)),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Hero(
                        tag: 'card-${card.id}',
                        child: CarVisual(card: card),
                      ),
                      Positioned(top: 6, right: 6, child: TierChip(t, dense: true)),
                      if (locked)
                        Positioned(
                          top: 6,
                          left: 6,
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: SdColors.ink.withValues(alpha: 0.75),
                              borderRadius: const BorderRadius.all(SdRadius.sm),
                            ),
                            child: const Icon(Icons.lock_rounded, size: 13, color: SdColors.gold),
                          ),
                        ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    SdSpace.sm,
                    SdSpace.sm,
                    SdSpace.sm,
                    SdSpace.sm,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        card.make.toUpperCase(),
                        style: SdType.label.copyWith(fontSize: 9, color: t.color),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        card.model.toUpperCase(),
                        style: SdType.subheading,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              card.variant ?? card.yearLabel,
                              style: SdType.caption.copyWith(fontSize: 11),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Text(
                            SdFormat.date(card.capturedAt).substring(5),
                            style: SdType.dataSmall.copyWith(fontSize: 10),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
