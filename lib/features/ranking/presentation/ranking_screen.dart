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
import '../../shell/app_shell.dart';

typedef _Query = ({LeaderboardScope scope, LeaderboardPeriod period});

class _RankingQuery extends Notifier<_Query> {
  @override
  _Query build() => (scope: LeaderboardScope.world, period: LeaderboardPeriod.allTime);

  void setScope(LeaderboardScope s) => state = (scope: s, period: state.period);
  void setPeriod(LeaderboardPeriod p) => state = (scope: state.scope, period: p);
}

final _queryProvider = NotifierProvider<_RankingQuery, _Query>(_RankingQuery.new);

final _leaderboardProvider = FutureProvider.autoDispose<LeaderboardPage>((ref) {
  final q = ref.watch(_queryProvider);
  // Regional scopes depend on the profile's region and XP: refetch when the
  // profile changes (the tab stays mounted, so it would otherwise go stale).
  ref.watch(profileProvider);
  return ref.watch(rankingRepositoryProvider).fetch(q.scope, q.period);
});

class RankingScreen extends ConsumerWidget {
  const RankingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final q = ref.watch(_queryProvider);
    final ctrl = ref.read(_queryProvider.notifier);
    final async = ref.watch(_leaderboardProvider);

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            TabHeader(
              leading: IconButton(
                tooltip: 'Back',
                icon: const Icon(Icons.arrow_back_rounded),
                onPressed: () => context.canPop() ? context.pop() : context.go('/feed'),
              ),
              title: 'Ranking',
              subtitle: 'Ranked by XP. Ties go to whoever got there first.',
            ),
            SizedBox(
              height: 40,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: SdSpace.gutter),
                children: [
                  // Nearby stays hidden until the app asks for location: without
                  // it the tab could only ever show "needs location".
                  for (final s in LeaderboardScope.values.where(
                    (s) => s != LeaderboardScope.nearby,
                  ))
                    Padding(
                      padding: const EdgeInsets.only(right: SdSpace.sm),
                      child: SdFilterChip(
                        label: s.label,
                        selected: q.scope == s,
                        onTap: () => ctrl.setScope(s),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: SdSpace.md),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: SdSpace.gutter),
              child: Align(
                alignment: Alignment.centerLeft,
                child: SdSegmented<LeaderboardPeriod>(
                  values: LeaderboardPeriod.values,
                  selected: q.period,
                  labelOf: (p) => p.label,
                  onChanged: ctrl.setPeriod,
                ),
              ),
            ),
            const SizedBox(height: SdSpace.md),
            Expanded(
              child: async.when(
                skipLoadingOnReload: false,
                loading: () => const _RankingSkeleton(),
                error: (e, _) => switch (e) {
                  _ when q.scope == LeaderboardScope.nearby => SdEmptyState(
                    icon: Icons.near_me_disabled_outlined,
                    title: 'Nearby needs location',
                    message:
                        '${e.userMessage} You can still compare yourself by '
                        'country or city.',
                    actionLabel: 'Show world',
                    onAction: () => ctrl.setScope(LeaderboardScope.world),
                  ),
                  RequestFailure(code: 'REGION_REQUIRED') => SdEmptyState(
                    icon: Icons.place_outlined,
                    title: 'Set your region',
                    message: e.userMessage,
                    actionLabel: 'Go to Profile',
                    onAction: () => context.go('/profile'),
                  ),
                  _ => SdErrorState(error: e, onRetry: () => ref.invalidate(_leaderboardProvider)),
                },
                data: (page) => _Board(page: page),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Board extends StatelessWidget {
  const _Board({required this.page});
  final LeaderboardPage page;

  @override
  Widget build(BuildContext context) {
    final entries = page.entries;
    if (entries.isEmpty) {
      return const SdEmptyState(
        icon: Icons.leaderboard_outlined,
        title: 'No rankings yet',
        message: 'Nobody has earned XP in this period. Catch a car to take the lead.',
      );
    }
    // The podium needs three spotters; with fewer, everyone goes in the list.
    final hasPodium = entries.length >= 3;
    final podium = hasPodium ? entries.take(3).toList() : const <LeaderboardEntry>[];
    final rest = hasPodium ? entries.skip(3).toList() : entries;
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(SdSpace.gutter, 0, SdSpace.gutter, SdSpace.lg),
            children: [
              if (hasPodium) ...[_Podium(entries: podium), const SizedBox(height: SdSpace.lg)],
              if (rest.isNotEmpty)
                SdPanel(
                  padding: EdgeInsets.zero,
                  child: Column(
                    children: [
                      for (final (i, e) in rest.indexed)
                        _RankRow(entry: e, divider: i < rest.length - 1, highlight: e.isViewer),
                    ],
                  ),
                ),
            ],
          ),
        ),
        if (page.viewer != null) _ViewerBar(entry: page.viewer!),
      ],
    );
  }
}

class _Podium extends StatelessWidget {
  const _Podium({required this.entries});
  final List<LeaderboardEntry> entries;

  @override
  Widget build(BuildContext context) {
    const medals = [SdColors.gold, Color(0xFFC9CDD4), Color(0xFFC0814A)];
    final order = [1, 0, 2];
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        for (final i in order)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: SdSpace.xs),
              child: Semantics(
                label: 'Rank ${entries[i].rank}, ${entries[i].user.handle}, ${entries[i].xp} XP',
                excludeSemantics: true,
                child: Column(
                  children: [
                    Monogram(
                      initials: entries[i].user.handle.substring(0, 2).toUpperCase(),
                      size: i == 0 ? 54 : 44,
                      color: medals[i],
                    ),
                    const SizedBox(height: SdSpace.sm),
                    Text(
                      '@${entries[i].user.handle}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: SdType.bodyStrong.copyWith(fontSize: 13),
                    ),
                    Text(
                      '${SdFormat.number(entries[i].xp)} XP',
                      style: SdType.dataSmall.copyWith(color: medals[i]),
                    ),
                    const SizedBox(height: SdSpace.sm),
                    Container(
                      height: i == 0 ? 72 : (i == 1 ? 54 : 42),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            medals[i].withValues(alpha: 0.28),
                            medals[i].withValues(alpha: 0.04),
                          ],
                        ),
                        border: Border(top: BorderSide(color: medals[i], width: 2)),
                      ),
                      child: Text(
                        '${entries[i].rank}',
                        style: SdType.title.copyWith(color: medals[i]),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _RankRow extends StatelessWidget {
  const _RankRow({required this.entry, required this.divider, this.highlight = false});
  final LeaderboardEntry entry;
  final bool divider;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label:
          'Rank ${entry.rank}, ${entry.user.handle}, level ${entry.user.level}, '
          '${entry.xp} XP',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: SdSpace.lg, vertical: SdSpace.md),
        decoration: BoxDecoration(
          border: divider ? const Border(bottom: BorderSide(color: SdColors.line)) : null,
        ),
        child: Row(
          children: [
            SizedBox(
              width: 44,
              child: Text(
                '${entry.rank}',
                style: SdType.data.copyWith(color: highlight ? SdColors.gold : SdColors.textMuted),
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('@${entry.user.handle}', style: SdType.bodyStrong),
                  Text(
                    'LV ${entry.user.level} · ${entry.carCount} ${entry.carCount == 1 ? 'car' : 'cars'}',
                    style: SdType.caption,
                  ),
                ],
              ),
            ),
            Text(
              '${SdFormat.number(entry.xp)} XP',
              style: SdType.data.copyWith(color: SdColors.gold, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}

/// Viewer's own rank, pinned even when outside the loaded page (spec §3.4).
class _ViewerBar extends StatelessWidget {
  const _ViewerBar({required this.entry});
  final LeaderboardEntry entry;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: SdColors.surfaceRaised,
        border: Border(top: BorderSide(color: SdColors.goldDeep)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: SdSpace.xs),
      child: Row(
        children: [
          Container(width: 3, height: 44, color: SdColors.gold),
          Expanded(child: _RankRow(entry: entry, divider: false, highlight: true)),
        ],
      ),
    );
  }
}

class _RankingSkeleton extends StatelessWidget {
  const _RankingSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: SdSpace.gutter),
      children: [
        const SdSkeleton(height: 150),
        const SizedBox(height: SdSpace.lg),
        for (var i = 0; i < 6; i++) ...[
          const SdSkeleton(height: 48),
          const SizedBox(height: SdSpace.sm),
        ],
      ],
    );
  }
}
