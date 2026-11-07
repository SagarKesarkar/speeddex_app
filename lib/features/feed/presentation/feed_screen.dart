import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../core/errors/app_failure.dart';
import '../../../core/theme/sd_colors.dart';
import '../../../core/theme/sd_tokens.dart';
import '../../../core/theme/sd_typography.dart';
import '../../../core/util/format.dart';
import '../../../core/widgets/sd_primitives.dart';
import '../../../core/widgets/sd_segmented.dart';
import '../../../core/widgets/sd_states.dart';
import '../../../domain/social.dart';
import '../../ads/feed_banner.dart';
import '../../cards/application/unlock_flow.dart';
import '../../cards/presentation/collector_card.dart';
import '../../shell/app_shell.dart';
import '../application/feed_controller.dart';
import 'feed_post_tile.dart';
import 'feed_sheets.dart';

class FeedScreen extends ConsumerWidget {
  const FeedScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(feedControllerProvider);
    final ctrl = ref.read(feedControllerProvider.notifier);

    Widget body;
    if (state.loading) {
      body = const _FeedSkeleton();
    } else if (state.error != null) {
      body = SdErrorState(error: state.error!, onRetry: ctrl.refresh);
    } else if (state.posts.isEmpty) {
      body = SdEmptyState(
        icon: Icons.dynamic_feed_outlined,
        title: 'Quiet on the street',
        message: 'Catches from spotters you follow will show up here.',
        actionLabel: 'Scan a car',
        onAction: () => context.go('/scan'),
      );
    } else {
      body = AnimatedSwitcher(
        duration: SdMotion.medium,
        child: state.mode == FeedMode.list
            ? _FeedList(key: const ValueKey('list'), state: state)
            : _FeedReel(key: const ValueKey('cards'), posts: state.posts, ended: !state.hasMore),
      );
    }

    return SafeArea(
      bottom: false,
      child: Column(
        children: [
          TabHeader(
            title: 'Feed',
            action: RankingButton(onTap: () => context.push('/ranking')),
            trailing: SdSegmented<FeedMode>(
              values: FeedMode.values,
              selected: state.mode,
              labelOf: (m) => m == FeedMode.list ? 'List view' : 'Card view',
              iconOf: (m) => m == FeedMode.list ? Icons.view_agenda_outlined : Icons.style_outlined,
              onChanged: ctrl.setMode,
            ),
          ),
          Expanded(child: body),
        ],
      ),
    );
  }
}

/// Picked once per app run, so ads stay put while the feed grows but land in
/// different places from one session to the next.
final _adSeed = Random().nextInt(1 << 30);

class _FeedList extends ConsumerWidget {
  const _FeedList({super.key, required this.state});
  final FeedState state;

  Future<void> _like(BuildContext context, WidgetRef ref, FeedPost p) async {
    final ok = await ref.read(feedControllerProvider.notifier).toggleLike(p.id);
    if (!ok && context.mounted) showSdSnack(context, 'Couldn’t update like. Try again.');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ctrl = ref.read(feedControllerProvider.notifier);
    final posts = state.posts;
    // One banner in every block of 20 posts, after a random one of them.
    final adsAfter = (ref.read(adsServiceProvider).config.enabled && !ref.watch(isProProvider))
        ? feedAdSlots(posts.length, seed: _adSeed, ended: !state.hasMore).toSet()
        : const <int>{};
    final items = <int?>[
      for (var i = 0; i < posts.length; i++) ...[i, if (adsAfter.contains(i + 1)) null],
    ];
    return RefreshIndicator(
      color: SdColors.gold,
      backgroundColor: SdColors.surfaceRaised,
      onRefresh: ctrl.refresh,
      child: NotificationListener<ScrollNotification>(
        onNotification: (n) {
          if (n.metrics.extentAfter < 600) ctrl.loadMore();
          return false;
        },
        child: ListView.separated(
          padding: const EdgeInsets.fromLTRB(SdSpace.gutter, 0, SdSpace.gutter, SdSpace.xxxl),
          itemCount: items.length + 1,
          separatorBuilder: (_, _) => const SizedBox(height: SdSpace.lg),
          itemBuilder: (context, index) {
            if (index == items.length) {
              if (state.pageError != null) {
                return SdInlineError(message: state.pageError!.userMessage, onRetry: ctrl.loadMore);
              }
              if (state.loadingMore) {
                return const Padding(
                  padding: EdgeInsets.all(SdSpace.lg),
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              return Padding(
                padding: const EdgeInsets.all(SdSpace.lg),
                child: Center(
                  child: Text(state.hasMore ? '' : 'YOU’RE ALL CAUGHT UP', style: SdType.label),
                ),
              );
            }
            final i = items[index];
            if (i == null) return FeedBannerAd(key: ValueKey('ad-$index'));
            final p = posts[i];
            return ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: SdSize.maxContentWidth),
              child: FeedPostTile(
                post: p,
                onOpen: () => context.push('/card/${p.card.id}'),
                onLike: () => _like(context, ref, p),
                onComments: () => showCommentsSheet(context, p),
                onMore: () => showReportSheet(context, ref, p),
                onAuthor: () => openAuthor(context, p),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// A sponsored page in card view: a 300×250 ad where a Car Card would be.
class _ReelAdPage extends StatelessWidget {
  const _ReelAdPage({super.key, required this.last});
  final bool last;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(SdSpace.gutter, 0, SdSpace.gutter, SdSpace.md),
      child: Column(
        children: [
          Expanded(
            child: Center(
              child: FeedBannerAd(
                large: true,
                placeholder: (failed) => SizedBox(
                  width: 300,
                  height: 280,
                  child: SdPanel(
                    child: Center(
                      child: failed
                          ? Text(
                              'Nothing to show here.\nSwipe up for the next car.',
                              textAlign: TextAlign.center,
                              style: SdType.body.copyWith(color: SdColors.textMuted),
                            )
                          : const CircularProgressIndicator(),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: SdSpace.sm),
          Text(
            last ? 'END OF FEED' : 'SWIPE UP FOR NEXT',
            style: SdType.label.copyWith(fontSize: 10, color: SdColors.textFaint),
          ),
        ],
      ),
    );
  }
}

/// Card/reel mode: one full Car Card at a time, swipe vertically (spec §3.3).
class _FeedReel extends ConsumerStatefulWidget {
  const _FeedReel({super.key, required this.posts, required this.ended});
  final List<FeedPost> posts;

  /// No more pages to load: a short feed still gets its ad page.
  final bool ended;

  @override
  ConsumerState<_FeedReel> createState() => _FeedReelState();
}

class _FeedReelState extends ConsumerState<_FeedReel> {
  final Set<String> _unlocking = {};

  Future<void> _unlock(FeedPost p) async {
    setState(() => _unlocking.add(p.card.id));
    final card = await runUnlockFlow(context, ref, p.card);
    if (!mounted) return;
    setState(() => _unlocking.remove(p.card.id));
    if (card != null) {
      ref.read(feedControllerProvider.notifier).applyCard(card);
      showSdSnack(context, 'Card unlocked.', success: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final posts = widget.posts;
    // Same placement as the list: one ad page in every block of 20 cards.
    final adsAfter = (ref.read(adsServiceProvider).config.enabled && !ref.watch(isProProvider))
        ? feedAdSlots(posts.length, seed: _adSeed, ended: widget.ended).toSet()
        : const <int>{};
    final items = <int?>[
      for (var i = 0; i < posts.length; i++) ...[i, if (adsAfter.contains(i + 1)) null],
    ];
    return PageView.builder(
      scrollDirection: Axis.vertical,
      itemCount: items.length,
      onPageChanged: (page) {
        if (page >= items.length - 3) ref.read(feedControllerProvider.notifier).loadMore();
      },
      itemBuilder: (context, page) {
        final i = items[page];
        if (i == null) {
          return _ReelAdPage(key: ValueKey('ad-$page'), last: page == items.length - 1);
        }
        final p = posts[i];
        // No inner scroll view: it would capture vertical drags whenever a card
        // is taller than the page (e.g. while the unlock bar is showing) and
        // block paging. The card is scaled down to fit the page instead.
        return Padding(
          padding: const EdgeInsets.fromLTRB(SdSpace.gutter, 0, SdSpace.gutter, SdSpace.md),
          child: Column(
            children: [
              AuthorHeader(
                author: p.author,
                meta: [SdFormat.ago(p.createdAt)],
                avatarSize: 30,
                onTap: () => openAuthor(context, p),
              ),
              const SizedBox(height: SdSpace.sm),
              Expanded(
                child: Center(
                  // Every card gets the same frame, and the frame is what's
                  // scaled to the page: so all cards show at the same width,
                  // however many rows each has. A card taller than the frame
                  // (rare) is scaled down inside it.
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: SizedBox(
                      width: _reelCardWidth,
                      height: _reelCardHeight,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: SizedBox(
                          width: _reelCardWidth,
                          child: GestureDetector(
                            onTap: () => context.push('/card/${p.card.id}'),
                            child: CollectorCard(
                              card: p.card,
                              unlocking: _unlocking.contains(p.card.id),
                              onUnlock: () => _unlock(p),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: SdSpace.sm),
              Text(
                page < items.length - 1 ? 'SWIPE UP FOR NEXT' : 'END OF FEED',
                style: SdType.label.copyWith(fontSize: 10, color: SdColors.textFaint),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _FeedSkeleton extends StatelessWidget {
  const _FeedSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: SdSpace.gutter),
      children: List.generate(3, (_) {
        return Padding(
          padding: const EdgeInsets.only(bottom: SdSpace.lg),
          child: SdPanel(
            padding: const EdgeInsets.all(SdSpace.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                Row(
                  children: [
                    SdSkeleton(height: 34, width: 34),
                    SizedBox(width: SdSpace.md),
                    SdSkeleton(height: 14, width: 120),
                  ],
                ),
                SizedBox(height: SdSpace.md),
                AspectRatio(aspectRatio: 16 / 10, child: SdSkeleton()),
                SizedBox(height: SdSpace.md),
                SdSkeleton(height: 14, width: 160),
              ],
            ),
          ),
        );
      }),
    );
  }
}

/// The viewer's own posts open their Profile tab; anyone else's open the
/// public profile with a follow button.
void openAuthor(BuildContext context, FeedPost post) {
  if (post.card.ownedByViewer) {
    context.go('/profile');
  } else {
    context.push('/user/${post.author.id}');
  }
}

/// The frame every card is laid out in, in card view. Cards measure about
/// 655 points at this width, 687 with the unlock button.
const _reelCardWidth = 360.0;
const _reelCardHeight = 690.0;
