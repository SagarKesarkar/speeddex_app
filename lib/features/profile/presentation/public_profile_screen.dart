import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../core/errors/app_failure.dart';
import '../../../core/theme/sd_colors.dart';
import '../../../core/theme/sd_tokens.dart';
import '../../../core/theme/sd_typography.dart';
import '../../../core/util/format.dart';
import '../../../core/widgets/sd_button.dart';
import '../../../core/widgets/sd_primitives.dart';
import '../../../core/widgets/sd_states.dart';
import '../../../domain/car_card.dart';
import '../../../domain/profile.dart';
import '../../cards/presentation/card_grid_tile.dart';

final publicProfileProvider = FutureProvider.autoDispose.family<PublicProfile, String>(
  (ref, userId) => ref.watch(usersRepositoryProvider).publicProfile(userId),
);

/// Another spotter's profile, opened from their name in the feed: who they
/// are, a follow button, badges, and their cars (loaded a page at a time).
class PublicProfileScreen extends ConsumerStatefulWidget {
  const PublicProfileScreen({super.key, required this.userId});
  final String userId;

  @override
  ConsumerState<PublicProfileScreen> createState() => _PublicProfileScreenState();
}

class _PublicProfileScreenState extends ConsumerState<PublicProfileScreen> {
  /// Local follow state, applied optimistically on top of the loaded profile.
  bool? _follows;
  int? _followers;
  bool _busy = false;

  // Cars, paged.
  final List<CarCard> _cars = [];
  String? _cursor;
  bool _done = false;
  bool _loadingCars = false;
  Object? _carsError;

  @override
  void initState() {
    super.initState();
    _loadMore();
  }

  Future<void> _loadMore() async {
    if (_loadingCars || _done) return;
    setState(() {
      _loadingCars = true;
      _carsError = null;
    });
    try {
      final page = await ref.read(usersRepositoryProvider).cards(widget.userId, cursor: _cursor);
      if (!mounted) return;
      setState(() {
        _cars.addAll(page.cards);
        _cursor = page.nextCursor;
        _done = page.nextCursor == null;
      });
    } catch (e) {
      if (mounted) setState(() => _carsError = e);
    } finally {
      if (mounted) setState(() => _loadingCars = false);
    }
  }

  /// Opens a card; on return, refreshes it so an unlock made there shows here.
  Future<void> _open(CarCard card) async {
    await context.push('/card/${card.id}');
    if (!mounted || card.ownedByViewer || card.hiddenUnlocked) return;
    try {
      final fresh = await ref.read(cardsRepositoryProvider).detail(card.id);
      final i = _cars.indexWhere((c) => c.id == card.id);
      if (mounted && i >= 0) setState(() => _cars[i] = fresh);
    } catch (_) {
      // Keep the list as it was; the card screen already reported any error.
    }
  }

  Future<void> _toggle(PublicProfile p) async {
    final following = _follows ?? p.viewerFollows;
    final before = (_follows, _followers);
    setState(() {
      _busy = true;
      _follows = !following;
      _followers = (_followers ?? p.followers) + (following ? -1 : 1);
    });
    try {
      final repo = ref.read(usersRepositoryProvider);
      final count = following ? await repo.unfollow(p.user.id) : await repo.follow(p.user.id);
      if (mounted) setState(() => _followers = count);
      // The viewer's own "following" count changed.
      ref.invalidate(profileProvider);
    } catch (e) {
      if (mounted) {
        setState(() {
          _follows = before.$1;
          _followers = before.$2;
        });
        showSdSnack(context, e.userMessage);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(publicProfileProvider(widget.userId));
    return Scaffold(
      appBar: AppBar(title: Text(async.value == null ? 'SPOTTER' : '@${async.value!.user.handle}')),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => SdErrorState(
          error: e,
          onRetry: () => ref.invalidate(publicProfileProvider(widget.userId)),
        ),
        data: (p) => NotificationListener<ScrollNotification>(
          // Load the next page when the user nears the end of the list.
          onNotification: (n) {
            if (n.metrics.extentAfter < 600) _loadMore();
            return false;
          },
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: SdSize.maxContentWidth),
              child: CustomScrollView(
                slivers: [
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(
                      SdSpace.gutter,
                      SdSpace.lg,
                      SdSpace.gutter,
                      0,
                    ),
                    sliver: SliverList.list(children: _header(p)),
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: SdSpace.gutter),
                    sliver: SliverGrid.builder(
                      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                        maxCrossAxisExtent: 220,
                        mainAxisSpacing: SdSpace.md,
                        crossAxisSpacing: SdSpace.md,
                        childAspectRatio: 0.74,
                      ),
                      itemCount: _cars.length,
                      itemBuilder: (_, i) =>
                          CardGridTile(card: _cars[i], onTap: () => _open(_cars[i])),
                    ),
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(
                      SdSpace.gutter,
                      SdSpace.lg,
                      SdSpace.gutter,
                      SdSpace.huge,
                    ),
                    sliver: SliverToBoxAdapter(child: _carsFooter()),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _header(PublicProfile p) {
    final follows = _follows ?? p.viewerFollows;
    return [
      Row(
        children: [
          Monogram(initials: p.user.initials, size: 72),
          const SizedBox(width: SdSpace.lg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  p.user.displayName,
                  style: SdType.heading,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  '@${p.user.handle} · LV ${p.user.level}',
                  style: SdType.body.copyWith(color: SdColors.textMuted),
                ),
              ],
            ),
          ),
        ],
      ),
      if (p.bio != null && p.bio!.isNotEmpty) ...[
        const SizedBox(height: SdSpace.lg),
        Text(p.bio!, style: SdType.body.copyWith(color: SdColors.textMuted)),
      ],
      const SizedBox(height: SdSpace.xl),
      if (!p.isViewer)
        SdButton(
          label: follows ? 'Following' : 'Follow',
          icon: follows ? Icons.check_rounded : Icons.person_add_alt_1_rounded,
          variant: follows ? SdButtonVariant.secondary : SdButtonVariant.primary,
          loading: _busy,
          onPressed: () => _toggle(p),
        ),
      const SizedBox(height: SdSpace.xl),
      Row(
        children: [
          Expanded(
            child: _Stat(
              'Followers',
              SdFormat.compact(_followers ?? p.followers),
              onTap: () => context.push('/followers/${p.user.id}'),
            ),
          ),
          const SizedBox(width: SdSpace.sm),
          Expanded(
            child: _Stat(
              'Following',
              SdFormat.compact(p.following),
              onTap: () => context.push('/following/${p.user.id}'),
            ),
          ),
          const SizedBox(width: SdSpace.sm),
          Expanded(child: _Stat('Cars', '${p.carCount}')),
          const SizedBox(width: SdSpace.sm),
          Expanded(child: _Stat('XP', SdFormat.compact(p.xp))),
        ],
      ),
      if (p.badges.isNotEmpty) ...[
        const SizedBox(height: SdSpace.xxl),
        const SdSectionLabel('Badges'),
        const SizedBox(height: SdSpace.md),
        Wrap(
          spacing: SdSpace.sm,
          runSpacing: SdSpace.sm,
          children: [
            for (final b in p.badges)
              Chip(
                avatar: const Icon(Icons.military_tech_rounded, size: 16, color: SdColors.gold),
                label: Text(b.name.toUpperCase(), style: SdType.label.copyWith(fontSize: 10)),
                backgroundColor: SdColors.surface,
                side: const BorderSide(color: SdColors.line),
              ),
          ],
        ),
      ],
      const SizedBox(height: SdSpace.xxl),
      const SdSectionLabel('Cars'),
      const SizedBox(height: SdSpace.md),
    ];
  }

  Widget _carsFooter() {
    if (_carsError != null) {
      return Column(
        children: [
          Text(_carsError!.userMessage, textAlign: TextAlign.center, style: SdType.caption),
          TextButton(onPressed: _loadMore, child: const Text('Try again')),
        ],
      );
    }
    if (_loadingCars) {
      return const Center(
        child: SizedBox.square(dimension: 24, child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    if (_done && _cars.isEmpty) {
      return Text('No cars caught yet.', style: SdType.caption, textAlign: TextAlign.center);
    }
    return const SizedBox.shrink();
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.label, this.value, {this.onTap});
  final String label;
  final String value;

  /// Opens the list behind the number (followers, following), if any.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '$value $label',
      button: onTap != null,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: const BorderRadius.all(SdRadius.md),
        child: SdPanel(
          padding: const EdgeInsets.symmetric(vertical: SdSpace.md),
          child: Column(
            children: [
              Text(value, style: SdType.dataLarge.copyWith(fontSize: 17)),
              const SizedBox(height: 2),
              Text(label.toUpperCase(), style: SdType.label.copyWith(fontSize: 9.5)),
            ],
          ),
        ),
      ),
    );
  }
}
