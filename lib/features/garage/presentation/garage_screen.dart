import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../core/theme/sd_colors.dart';
import '../../../core/theme/sd_tokens.dart';
import '../../../core/theme/sd_typography.dart';
import '../../../core/util/format.dart';
import '../../../core/widgets/car_visual.dart';
import '../../../core/widgets/sd_button.dart';
import '../../../core/widgets/sd_primitives.dart';
import '../../../core/widgets/sd_segmented.dart';
import '../../../core/widgets/sd_states.dart';
import '../../../data/repositories.dart';
import '../../../domain/car_card.dart';
import '../../../domain/profile.dart';
import '../../../domain/rarity_tier.dart';
import '../../shell/app_shell.dart';
import '../../cards/presentation/card_grid_tile.dart';
import '../../scan/application/scan_controller.dart';
import '../application/garage_providers.dart';

class GarageScreen extends ConsumerWidget {
  const GarageScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = ref.watch(garageSummaryProvider);
    final cards = ref.watch(garageCardsProvider);
    final query = ref.watch(garageQueryProvider);
    final layout = ref.watch(garageLayoutProvider);

    return SafeArea(
      bottom: false,
      child: RefreshIndicator(
        color: SdColors.gold,
        backgroundColor: SdColors.surfaceRaised,
        onRefresh: () async {
          ref.invalidate(garageSummaryProvider);
          await ref.read(garageCardsProvider.future);
        },
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: TabHeader(
                title: 'Garage',
                trailing: SdSegmented<GarageLayout>(
                  values: GarageLayout.values,
                  selected: layout,
                  labelOf: (l) => l == GarageLayout.grid ? 'Grid view' : 'List view',
                  iconOf: (l) =>
                      l == GarageLayout.grid ? Icons.grid_view_rounded : Icons.view_list_rounded,
                  onChanged: ref.read(garageLayoutProvider.notifier).set,
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: SdSpace.gutter),
              sliver: SliverToBoxAdapter(
                child: summary.when(
                  loading: () => const SdSkeleton(height: 132, radius: SdRadius.md),
                  error: (e, _) => SdInlineError(
                    message: 'Couldn’t load your Garage totals.',
                    onRetry: () => ref.invalidate(garageSummaryProvider),
                  ),
                  data: (s) => _SummaryPanel(summary: s),
                ),
              ),
            ),
            const SliverToBoxAdapter(child: _PendingCaptures()),
            const SliverToBoxAdapter(child: SizedBox(height: SdSpace.lg)),
            SliverToBoxAdapter(child: _FilterBar(query: query)),
            const SliverToBoxAdapter(child: SizedBox(height: SdSpace.md)),
            ...cards.when(
              loading: () => [
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.all(SdSpace.xxxl),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                ),
              ],
              error: (e, _) => [
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: SdErrorState(error: e, onRetry: () => ref.invalidate(garageCardsProvider)),
                ),
              ],
              data: (list) {
                if (list.isEmpty) {
                  return [
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: query.isFiltered
                          ? SdEmptyState(
                              icon: Icons.filter_alt_off_outlined,
                              title: 'No matches',
                              message: 'No cards in your Garage match these filters.',
                              actionLabel: 'Clear filters',
                              onAction: ref.read(garageQueryProvider.notifier).clear,
                            )
                          : SdEmptyState(
                              icon: Icons.garage_outlined,
                              title: 'Your Garage is empty',
                              message: 'Scan your first car to start the collection.',
                              actionLabel: 'Scan a car',
                              onAction: () => context.go('/scan'),
                            ),
                    ),
                  ];
                }
                return [
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(
                      SdSpace.gutter,
                      0,
                      SdSpace.gutter,
                      SdSpace.xxxl,
                    ),
                    sliver: layout == GarageLayout.grid
                        ? SliverGrid.builder(
                            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                              maxCrossAxisExtent: 220,
                              mainAxisSpacing: SdSpace.md,
                              crossAxisSpacing: SdSpace.md,
                              childAspectRatio: 0.74,
                            ),
                            itemCount: list.length,
                            itemBuilder: (_, i) => CardGridTile(card: list[i]),
                          )
                        : SliverList.separated(
                            itemCount: list.length,
                            separatorBuilder: (_, _) => const SizedBox(height: SdSpace.sm),
                            itemBuilder: (_, i) => _ListTile(card: list[i]),
                          ),
                  ),
                ];
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _SummaryPanel extends StatelessWidget {
  const _SummaryPanel({required this.summary});
  final GarageSummary summary;

  @override
  Widget build(BuildContext context) {
    final s = summary;
    return SdPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: _Metric('Cars', '${s.totalCards}', sub: 'of ${s.capacity} slots')),
              Container(width: 1, height: 40, color: SdColors.line),
              Expanded(child: _Metric('Total XP', SdFormat.number(s.totalXp), gold: true)),
              Container(width: 1, height: 40, color: SdColors.line),
              Expanded(child: _Metric('Scans', '${s.scansLeftToday}', sub: 'left today')),
            ],
          ),
          const SizedBox(height: SdSpace.lg),
          _TierDistribution(counts: s.tierCounts, total: s.totalCards),
          if (s.isFull) ...[
            const SizedBox(height: SdSpace.md),
            SdInlineError(
              message: 'Your Garage is full. New catches can’t be added until you add slots.',
            ),
          ],
        ],
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric(this.label, this.value, {this.sub, this.gold = false});
  final String label;
  final String value;
  final String? sub;
  final bool gold;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '$label $value ${sub ?? ''}',
      excludeSemantics: true,
      child: Column(
        children: [
          Text(label.toUpperCase(), style: SdType.label.copyWith(fontSize: 10)),
          const SizedBox(height: 4),
          Text(
            value,
            style: SdType.dataLarge.copyWith(color: gold ? SdColors.gold : SdColors.text),
          ),
          if (sub != null) Text(sub!, style: SdType.caption.copyWith(fontSize: 11)),
        ],
      ),
    );
  }
}

class _TierDistribution extends StatelessWidget {
  const _TierDistribution({required this.counts, required this.total});
  final Map<RarityTier, int> counts;
  final int total;

  @override
  Widget build(BuildContext context) {
    final present = RarityTier.values.where((t) => (counts[t] ?? 0) > 0).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: const BorderRadius.all(SdRadius.xs),
          child: SizedBox(
            height: 8,
            child: total == 0
                ? Container(color: SdColors.line)
                : Row(
                    children: [
                      for (final t in present)
                        Expanded(
                          flex: counts[t]!,
                          child: Container(color: t.color),
                        ),
                    ],
                  ),
          ),
        ),
        const SizedBox(height: SdSpace.sm),
        Wrap(
          spacing: SdSpace.md,
          runSpacing: 4,
          children: [
            for (final t in present)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(width: 8, height: 8, color: t.color),
                  const SizedBox(width: 4),
                  Text('${t.label} ${counts[t]}', style: SdType.caption.copyWith(fontSize: 11)),
                ],
              ),
          ],
        ),
      ],
    );
  }
}

class _FilterBar extends ConsumerWidget {
  const _FilterBar({required this.query});
  final GarageQuery query;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ctrl = ref.read(garageQueryProvider.notifier);
    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: SdSpace.gutter),
        children: [
          _SortButton(sort: query.sort, onTap: () => _showFilters(context, ref)),
          const SizedBox(width: SdSpace.sm),
          SdFilterChip(label: 'All', selected: query.tier == null, onTap: () => ctrl.setTier(null)),
          for (final t in RarityTier.values) ...[
            const SizedBox(width: SdSpace.sm),
            SdFilterChip(
              label: t.label,
              color: t.color,
              selected: query.tier == t,
              onTap: () => ctrl.setTier(query.tier == t ? null : t),
            ),
          ],
        ],
      ),
    );
  }

  void _showFilters(BuildContext context, WidgetRef ref) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _FilterSheet(),
    );
  }
}

class _SortButton extends StatelessWidget {
  const _SortButton({required this.sort, required this.onTap});
  final GarageSort sort;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Sort and filter. Sorted by ${sort.label}',
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: const BorderRadius.all(SdRadius.xl),
        child: Container(
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: SdSpace.md),
          decoration: BoxDecoration(
            color: SdColors.surfaceHigh,
            borderRadius: const BorderRadius.all(SdRadius.xl),
            border: Border.all(color: SdColors.lineStrong),
          ),
          child: Row(
            children: [
              const Icon(Icons.tune_rounded, size: 16, color: SdColors.text),
              const SizedBox(width: 6),
              Text(
                sort.label.toUpperCase(),
                style: SdType.label.copyWith(fontSize: 11, color: SdColors.text),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FilterSheet extends ConsumerWidget {
  const _FilterSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final q = ref.watch(garageQueryProvider);
    final ctrl = ref.read(garageQueryProvider.notifier);
    final makes = ref.watch(garageMakesProvider).value ?? const [];
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(SdSpace.gutter, 0, SdSpace.gutter, SdSpace.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('SORT & FILTER', style: SdType.heading),
            const SizedBox(height: SdSpace.xl),
            const SdSectionLabel('Sort by'),
            const SizedBox(height: SdSpace.md),
            Wrap(
              spacing: SdSpace.sm,
              runSpacing: SdSpace.sm,
              children: [
                for (final s in GarageSort.values)
                  SdFilterChip(label: s.label, selected: q.sort == s, onTap: () => ctrl.setSort(s)),
              ],
            ),
            const SizedBox(height: SdSpace.xl),
            const SdSectionLabel('Make'),
            const SizedBox(height: SdSpace.md),
            Wrap(
              spacing: SdSpace.sm,
              runSpacing: SdSpace.sm,
              children: [
                SdFilterChip(
                  label: 'Any',
                  selected: q.make == null,
                  onTap: () => ctrl.setMake(null),
                ),
                for (final m in makes)
                  SdFilterChip(label: m, selected: q.make == m, onTap: () => ctrl.setMake(m)),
              ],
            ),
            const SizedBox(height: SdSpace.xxl),
            Row(
              children: [
                Expanded(
                  child: SdButton(
                    label: 'Reset',
                    variant: SdButtonVariant.secondary,
                    onPressed: q.isFiltered || q.sort != GarageSort.newest
                        ? () {
                            ctrl.clear();
                            ctrl.setSort(GarageSort.newest);
                          }
                        : null,
                  ),
                ),
                const SizedBox(width: SdSpace.md),
                Expanded(
                  child: SdButton(label: 'Done', onPressed: () => Navigator.pop(context)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ListTile extends StatelessWidget {
  const _ListTile({required this.card});
  final CarCard card;

  @override
  Widget build(BuildContext context) {
    final t = card.tier;
    return SdPanel(
      padding: const EdgeInsets.all(SdSpace.sm),
      onTap: () => context.push('/card/${card.id}'),
      child: Row(
        children: [
          Container(
            width: 104,
            height: 68,
            decoration: BoxDecoration(
              borderRadius: const BorderRadius.all(SdRadius.sm),
              border: Border.all(color: t.color, width: 1.5),
            ),
            clipBehavior: Clip.antiAlias,
            child: CarVisual(card: card),
          ),
          const SizedBox(width: SdSpace.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  card.displayName,
                  style: SdType.bodyStrong,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  '${card.variant ?? card.category} · ${SdFormat.date(card.capturedAt)}',
                  style: SdType.caption,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 6),
                TierChip(t, dense: true),
              ],
            ),
          ),
          Text('+${card.xp}', style: SdType.dataLarge.copyWith(fontSize: 17, color: SdColors.gold)),
          const SizedBox(width: SdSpace.sm),
        ],
      ),
    );
  }
}

/// Captures that need the user: approved ones can be added, others are in review.
class _PendingCaptures extends ConsumerWidget {
  const _PendingCaptures();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(pendingCapturesProvider).value ?? const [];
    final ready = items.whereType<Identified>().toList();
    final inReview = items.whereType<ReviewRequired>().length;
    if (ready.isEmpty && inReview == 0) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(SdSpace.gutter, SdSpace.lg, SdSpace.gutter, 0),
      child: SdPanel(
        accent: SdColors.gold,
        padding: const EdgeInsets.all(SdSpace.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (ready.isNotEmpty) ...[
              Text(
                'READY TO ADD · ${ready.length}',
                style: SdType.label.copyWith(color: SdColors.gold),
              ),
              const SizedBox(height: SdSpace.sm),
              for (final r in ready)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(r.candidate.displayName, style: SdType.bodyStrong),
                  subtitle: Text('Confirmed by a reviewer', style: SdType.caption),
                  trailing: SdButton(
                    label: 'Review',
                    compact: true,
                    expand: false,
                    onPressed: () {
                      ref.read(scanControllerProvider.notifier).resume(r);
                      context.go('/scan');
                    },
                  ),
                ),
            ],
            if (inReview > 0)
              Padding(
                padding: EdgeInsets.only(top: ready.isEmpty ? 0 : SdSpace.sm),
                child: Row(
                  children: [
                    const Icon(Icons.hourglass_top_rounded, size: 16, color: SdColors.textMuted),
                    const SizedBox(width: SdSpace.sm),
                    Expanded(
                      child: Text(
                        '$inReview ${inReview == 1 ? 'car is' : 'cars are'} waiting for a reviewer.',
                        style: SdType.caption,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
