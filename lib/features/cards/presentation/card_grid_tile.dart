import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/sd_colors.dart';
import '../../../core/theme/sd_tokens.dart';
import '../../../core/theme/sd_typography.dart';
import '../../../core/util/format.dart';
import '../../../core/widgets/car_visual.dart';
import '../../../core/widgets/sd_primitives.dart';
import '../../../domain/car_card.dart';

/// Width-to-height of a grid cell: the card plus its likes/comments strip.
const cardGridAspect = 0.64;

/// Compact Car Card for grids (Garage, a spotter's profile). Opens the full
/// card; other spotters' cards show a lock until their spec sheet is unlocked.
/// Below it, the card's likes and comments open its post.
class CardGridTile extends StatelessWidget {
  const CardGridTile({super.key, required this.card, this.onTap});
  final CarCard card;

  /// Defaults to opening the card.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = card.tier;
    final locked = !card.ownedByViewer && !card.hiddenUnlocked;
    final face = Semantics(
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
                        child: CarVisual(card: card, small: true),
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(child: face),
        _Reactions(post: card.post, color: t.color),
      ],
    );
  }
}

/// Under the card: a slim tab that reveals the card's likes and comments;
/// those open its post. Always the same height, so grid rows line up.
class _Reactions extends StatefulWidget {
  const _Reactions({required this.post, required this.color});
  final PostStats? post;
  final Color color;

  @override
  State<_Reactions> createState() => _ReactionsState();
}

class _ReactionsState extends State<_Reactions> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final p = widget.post;
    return SizedBox(
      height: _stripHeight,
      child: p == null
          ? null
          : AnimatedSwitcher(
              duration: SdMotion.fast,
              // Both states hang from the bottom of the card, full width.
              layoutBuilder: (current, previous) => Stack(
                alignment: Alignment.topCenter,
                fit: StackFit.expand,
                children: [...previous, ?current],
              ),
              transitionBuilder: (child, a) => SizeTransition(
                sizeFactor: a,
                alignment: Alignment.topCenter,
                child: FadeTransition(opacity: a, child: child),
              ),
              child: _open ? _counts(context, p) : _tab(),
            ),
    );
  }

  Widget _tab() => Semantics(
    key: const ValueKey('tab'),
    button: true,
    label: 'Show likes and comments',
    excludeSemantics: true,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => setState(() => _open = true),
      // The whole slot under the card is the hit area, not just the slim tab.
      child: Align(
        alignment: Alignment.topCenter,
        child: Container(
          height: 18,
          width: double.infinity,
          margin: const EdgeInsets.symmetric(horizontal: SdSpace.md),
          decoration: const BoxDecoration(
            color: SdColors.surfaceHigh,
            borderRadius: BorderRadius.vertical(bottom: SdRadius.lg),
          ),
          child: const Icon(
            Icons.keyboard_double_arrow_down_rounded,
            size: 16,
            color: SdColors.gold,
          ),
        ),
      ),
    ),
  );

  /// The counts open the post; the arrow at the end folds the strip away.
  Widget _counts(BuildContext context, PostStats p) => Container(
    key: const ValueKey('counts'),
    height: _stripHeight,
    margin: const EdgeInsets.symmetric(horizontal: SdSpace.sm),
    decoration: BoxDecoration(
      color: SdColors.surfaceRaised,
      borderRadius: const BorderRadius.vertical(bottom: SdRadius.md),
      border: Border(
        left: BorderSide(color: widget.color.withValues(alpha: 0.5)),
        right: BorderSide(color: widget.color.withValues(alpha: 0.5)),
        bottom: BorderSide(color: widget.color.withValues(alpha: 0.5)),
      ),
    ),
    child: Stack(
      children: [
        // Counts stay centred on the strip; the arrow sits on top at the end.
        Positioned.fill(
          child: Semantics(
            button: true,
            label: '${p.likeCount} likes, ${p.commentCount} comments. Open post',
            excludeSemantics: true,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => context.push('/post/${p.postId}'),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.local_fire_department_rounded,
                    size: 17,
                    color: p.likeCount > 0 ? SdColors.signal : SdColors.textFaint,
                  ),
                  const SizedBox(width: SdSpace.xs),
                  Text(SdFormat.compact(p.likeCount), style: SdType.dataSmall),
                  const SizedBox(width: SdSpace.xl),
                  const Icon(Icons.mode_comment_outlined, size: 16, color: SdColors.textMuted),
                  const SizedBox(width: SdSpace.xs),
                  Text(SdFormat.compact(p.commentCount), style: SdType.dataSmall),
                ],
              ),
            ),
          ),
        ),
        Positioned(
          right: 0,
          top: 0,
          bottom: 0,
          child: Semantics(
            button: true,
            label: 'Hide likes and comments',
            excludeSemantics: true,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => setState(() => _open = false),
              child: const SizedBox(
                width: 32,
                child: Icon(Icons.keyboard_double_arrow_up_rounded, size: 16, color: SdColors.gold),
              ),
            ),
          ),
        ),
      ],
    ),
  );
}

const _stripHeight = 34.0;
