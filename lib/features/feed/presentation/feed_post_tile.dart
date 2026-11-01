import 'package:flutter/material.dart';

import '../../../core/theme/sd_colors.dart';
import '../../../core/theme/sd_tokens.dart';
import '../../../core/theme/sd_typography.dart';
import '../../../core/util/format.dart';
import '../../../core/widgets/car_visual.dart';
import '../../../core/widgets/sd_primitives.dart';
import '../../../domain/social.dart';

/// Active "fire" reaction colour (the app's like action).
const _fire = Color(0xFFFF7A1A);

/// Feed list item: author, capture, vehicle, tier, likes, comments, time
/// (spec §3.3).
class FeedPostTile extends StatelessWidget {
  const FeedPostTile({
    super.key,
    required this.post,
    required this.onOpen,
    required this.onLike,
    required this.onComments,
    required this.onMore,
    required this.onAuthor,
  });

  final FeedPost post;
  final VoidCallback onOpen;
  final VoidCallback onLike;
  final VoidCallback onComments;
  final VoidCallback onMore;

  /// Opens the author's profile.
  final VoidCallback onAuthor;

  @override
  Widget build(BuildContext context) {
    final card = post.card;
    final tier = card.tier;
    return Container(
      decoration: BoxDecoration(
        color: SdColors.surface,
        borderRadius: const BorderRadius.all(SdRadius.md),
        border: Border.all(color: SdColors.line),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(SdSpace.md, SdSpace.md, SdSpace.xs, SdSpace.md),
            child: Row(
              children: [
                Expanded(
                  child: AuthorHeader(
                    author: post.author,
                    meta: [SdFormat.ago(post.createdAt), ?card.locationLabel],
                    onTap: onAuthor,
                  ),
                ),
                IconButton(
                  tooltip: 'More options',
                  onPressed: onMore,
                  icon: const Icon(Icons.more_horiz_rounded, color: SdColors.textMuted),
                ),
              ],
            ),
          ),
          Semantics(
            button: true,
            label: 'Open ${card.displayName} card',
            child: GestureDetector(
              onTap: onOpen,
              child: Stack(
                children: [
                  AspectRatio(
                    aspectRatio: 16 / 10,
                    child: Hero(
                      tag: 'feed-${post.id}',
                      child: CarVisual(card: card),
                    ),
                  ),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(
                        SdSpace.md,
                        SdSpace.xxl,
                        SdSpace.md,
                        SdSpace.md,
                      ),
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Colors.transparent, Color(0xE60B0C0F)],
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  card.make.toUpperCase(),
                                  style: SdType.label.copyWith(color: tier.color, fontSize: 10),
                                ),
                                Text(
                                  '${card.model}${card.variant != null ? ' ${card.variant}' : ''}'
                                      .toUpperCase(),
                                  style: SdType.heading,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                          TierChip(tier),
                        ],
                      ),
                    ),
                  ),
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: Container(height: 2, color: tier.color),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: SdSpace.xs),
            child: Row(
              children: [
                _Action(
                  icon: post.viewerHasLiked
                      ? Icons.local_fire_department_rounded
                      : Icons.local_fire_department_outlined,
                  color: post.viewerHasLiked ? _fire : SdColors.textMuted,
                  label: SdFormat.compact(post.likeCount),
                  semantics: post.viewerHasLiked
                      ? 'Remove fire. ${post.likeCount} fires'
                      : 'Give fire. ${post.likeCount} fires',
                  onTap: onLike,
                ),
                _Action(
                  icon: Icons.mode_comment_outlined,
                  color: SdColors.textMuted,
                  label: SdFormat.compact(post.commentCount),
                  semantics: '${post.commentCount} comments',
                  onTap: onComments,
                ),
                const Spacer(),
                Padding(
                  padding: const EdgeInsets.only(right: SdSpace.md),
                  child: _Specs(post: post),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Specs extends StatelessWidget {
  const _Specs({required this.post});
  final FeedPost post;

  @override
  Widget build(BuildContext context) {
    final s = post.card.specs;
    // Only figures the catalogue has; e.g. "89 HP · 1.2 L I4" or "1.2 L I4".
    final parts = [
      if (s.horsepower != null) '${s.horsepower} HP',
      if (s.zeroToSixtySeconds != null) '${s.zeroToSixtySeconds}s',
      if (s.horsepower == null || s.zeroToSixtySeconds == null) ?s.engine,
    ].take(2);
    return Text(parts.join(' · '), style: SdType.dataSmall);
  }
}

class _Action extends StatelessWidget {
  const _Action({
    required this.icon,
    required this.color,
    required this.label,
    required this.semantics,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final String label;
  final String semantics;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: semantics,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: const BorderRadius.all(SdRadius.sm),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: SdSize.minTouch, minWidth: SdSize.minTouch),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: SdSpace.sm),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedSwitcher(
                  duration: SdMotion.fast,
                  transitionBuilder: (c, a) => ScaleTransition(scale: a, child: c),
                  child: Icon(icon, key: ValueKey(icon), size: 20, color: color),
                ),
                const SizedBox(width: 6),
                Text(label, style: SdType.data.copyWith(fontSize: 13, color: SdColors.textMuted)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Author block used by feed posts: full name, then "@username · LV n · …"
/// in muted text. The whole block opens the author's profile.
class AuthorHeader extends StatelessWidget {
  const AuthorHeader({
    super.key,
    required this.author,
    required this.onTap,
    this.meta = const [],
    this.avatarSize = 34,
  });

  final UserSummary author;
  final VoidCallback onTap;
  final List<String> meta;
  final double avatarSize;

  @override
  Widget build(BuildContext context) {
    final name = author.displayName.trim().isEmpty ? author.handle : author.displayName;
    return Semantics(
      button: true,
      label: 'View $name’s profile, @${author.handle}',
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: const BorderRadius.all(SdRadius.sm),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            children: [
              Monogram(initials: author.initials, size: avatarSize),
              const SizedBox(width: SdSpace.md),
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      name,
                      style: SdType.bodyStrong,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      ['@${author.handle}', 'LV ${author.level}', ...meta].join(' · '),
                      style: SdType.caption.copyWith(
                        color: SdColors.textMuted.withValues(alpha: 0.7),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
