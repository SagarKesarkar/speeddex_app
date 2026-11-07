import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/sd_colors.dart';
import '../../core/theme/sd_tokens.dart';
import '../../core/theme/sd_typography.dart';
import '../../core/widgets/brand.dart';
import '../../core/widgets/sd_button.dart';
import '../../core/widgets/sd_primitives.dart';
import '../../dev/dev_fixtures.dart';
import '../../domain/rarity_tier.dart';
import '../auth/application/auth_controller.dart';
import '../auth/presentation/legal_sheet.dart';
import '../cards/presentation/collector_card.dart';

/// First-launch carousel (spec §3.1). Permissions are not requested here —
/// camera and location are asked for only when the user starts a scan.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _controller = PageController();
  int _page = 0;
  static const _count = 4;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _go(int page) =>
      _controller.animateToPage(page, duration: SdMotion.medium, curve: SdMotion.curve);

  void _finish(String route) {
    ref.read(onboardingSeenProvider.notifier).markSeen();
    context.go(route);
  }

  @override
  Widget build(BuildContext context) {
    final last = _page == _count - 1;
    return Scaffold(
      body: Stack(
        children: [
          const Positioned.fill(child: Pinstripe()),
          SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: SdSize.maxContentWidth),
                child: Column(
                  children: [
                    SizedBox(
                      height: SdSize.topBarHeight,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: SdSpace.gutter),
                        child: Row(
                          children: [
                            const SdLogo(height: 48),
                            const Spacer(),
                            if (!last)
                              TextButton(
                                onPressed: () => _go(_count - 1),
                                child: Text('SKIP', style: SdType.label),
                              ),
                          ],
                        ),
                      ),
                    ),
                    Expanded(
                      child: PageView(
                        controller: _controller,
                        onPageChanged: (p) => setState(() => _page = p),
                        children: const [
                          _HeroSlide(),
                          _CaptureSlide(),
                          _TiersSlide(),
                          _RankSlide(),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        SdSpace.gutter,
                        SdSpace.md,
                        SdSpace.gutter,
                        SdSpace.lg,
                      ),
                      child: AnimatedSwitcher(
                        duration: SdMotion.medium,
                        child: last
                            ? _AuthActions(onRoute: _finish)
                            : _Pager(
                                page: _page,
                                count: _count,
                                onBack: _page == 0 ? null : () => _go(_page - 1),
                                onNext: () => _go(_page + 1),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Pager extends StatelessWidget {
  const _Pager({required this.page, required this.count, this.onBack, required this.onNext});
  final int page;
  final int count;
  final VoidCallback? onBack;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 96,
          child: onBack == null
              ? null
              : SdButton(
                  label: 'Back',
                  variant: SdButtonVariant.ghost,
                  onPressed: onBack,
                  compact: true,
                ),
        ),
        Expanded(
          child: Semantics(
            label: 'Page ${page + 1} of $count',
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(count, (i) {
                final active = i == page;
                return AnimatedContainer(
                  duration: SdMotion.medium,
                  curve: SdMotion.curve,
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  width: active ? 22 : 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: active ? SdColors.signal : SdColors.lineStrong,
                    borderRadius: const BorderRadius.all(Radius.circular(3)),
                  ),
                );
              }),
            ),
          ),
        ),
        SizedBox(
          width: 96,
          child: SdButton(
            label: 'Next',
            variant: SdButtonVariant.secondary,
            onPressed: onNext,
            compact: true,
          ),
        ),
      ],
    );
  }
}

class _AuthActions extends ConsumerStatefulWidget {
  const _AuthActions({required this.onRoute});
  final void Function(String route) onRoute;

  @override
  ConsumerState<_AuthActions> createState() => _AuthActionsState();
}

class _AuthActionsState extends ConsumerState<_AuthActions> {
  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SdButton(label: 'Create account', onPressed: () => widget.onRoute('/auth/register')),
        const SizedBox(height: SdSpace.md),
        SdButton(
          label: 'Sign in',
          variant: SdButtonVariant.secondary,
          onPressed: () => widget.onRoute('/auth/login'),
        ),
        const SizedBox(height: SdSpace.md),
        const LegalNotice(),
      ],
    );
  }
}

class _SlideFrame extends StatelessWidget {
  const _SlideFrame({required this.visual, required this.title, required this.body});
  final Widget visual;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: SdSpace.gutter),
      child: Column(
        children: [
          Expanded(child: Center(child: visual)),
          const SizedBox(height: SdSpace.xl),
          Text(title.toUpperCase(), style: SdType.title, textAlign: TextAlign.center),
          const SizedBox(height: SdSpace.sm),
          Text(
            body,
            textAlign: TextAlign.center,
            style: SdType.body.copyWith(color: SdColors.textMuted),
          ),
          const SizedBox(height: SdSpace.md),
        ],
      ),
    );
  }
}

class _HeroSlide extends StatelessWidget {
  const _HeroSlide();

  @override
  Widget build(BuildContext context) {
    // The Bugatti Chiron: its catalogue photo is exactly this car.
    final card = DevFixtures.byId('812');
    return _SlideFrame(
      title: 'Spot it. Keep it.',
      body:
          'Photograph real cars on the street. Every catch becomes a graded '
          'Car Card in your Garage.',
      visual: LayoutBuilder(
        builder: (context, c) {
          final width = (c.maxHeight * 0.62).clamp(180.0, 300.0);
          return FittedBox(
            child: SizedBox(
              width: width,
              child: Transform.rotate(
                angle: -0.04,
                child: CollectorCard(card: card, showSpecSheet: false),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _CaptureSlide extends StatelessWidget {
  const _CaptureSlide();

  @override
  Widget build(BuildContext context) {
    return _SlideFrame(
      title: 'Live capture only',
      body:
          'Scans use your camera, never your photo library. SpeedDex identifies '
          'make, model and year, then grades the shot.',
      visual: AspectRatio(
        aspectRatio: 3 / 4,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 280),
          decoration: BoxDecoration(
            border: Border.all(color: SdColors.lineStrong),
            borderRadius: const BorderRadius.all(SdRadius.lg),
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Lamborghini Urus by Cutlass, CC0, Wikimedia Commons.
              Image.asset('assets/brand/onboarding-scan.jpg', fit: BoxFit.cover),
              Center(
                child: FractionallySizedBox(
                  widthFactor: 0.86,
                  heightFactor: 0.5,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      border: Border.all(color: SdColors.gold.withValues(alpha: 0.8), width: 1.2),
                    ),
                  ),
                ),
              ),
              Positioned(
                left: SdSpace.md,
                top: SdSpace.md,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  color: SdColors.scrim,
                  child: Text(
                    'IDENTIFYING…',
                    style: SdType.label.copyWith(color: SdColors.gold, fontSize: 10),
                  ),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: SdSpace.lg,
                child: Center(
                  child: Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: SdColors.text, width: 3),
                    ),
                    padding: const EdgeInsets.all(4),
                    child: const DecoratedBox(
                      decoration: BoxDecoration(shape: BoxShape.circle, color: SdColors.signal),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TiersSlide extends StatelessWidget {
  const _TiersSlide();

  @override
  Widget build(BuildContext context) {
    final tiers = RarityTier.values.reversed.toList();
    return _SlideFrame(
      title: 'Nine tiers of rarity',
      body:
          'From daily commuters to one-of-one icons. The rarer the find, the '
          'more XP it earns.',
      visual: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 300),
        child: FittedBox(
          child: SizedBox(
            width: 300,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final (i, t) in tiers.indexed)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(
                      children: [
                        // Rarer tiers get narrower bars: a pyramid of scarcity.
                        Expanded(
                          child: Align(
                            alignment: Alignment.centerRight,
                            child: FractionallySizedBox(
                              widthFactor: (i + 2) / (tiers.length + 1),
                              child: Container(
                                height: 22,
                                decoration: BoxDecoration(
                                  color: t.color.withValues(alpha: 0.18),
                                  border: Border(right: BorderSide(color: t.color, width: 3)),
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: SdSpace.md),
                        SizedBox(
                          width: 96,
                          child: Text(
                            t.label.toUpperCase(),
                            style: SdType.label.copyWith(color: t.color, fontSize: 12),
                          ),
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

class _RankSlide extends StatelessWidget {
  const _RankSlide();

  @override
  Widget build(BuildContext context) {
    final rows = [
      ('1', 'gridwalker', '48,000'),
      ('2', 'v12_hunter', '31,620'),
      ('3', 'nightshift', '24,790'),
    ];
    return _SlideFrame(
      title: 'Climb the ranks',
      body:
          'Earn XP for every card. Compete worldwide, in your city, or in '
          'weekly and monthly sprints.',
      visual: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 320),
        child: SdPanel(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final (rank, handle, xp) in rows)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: SdSpace.sm),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 28,
                        child: Text(
                          rank,
                          style: SdType.heading.copyWith(
                            color: rank == '1' ? SdColors.gold : SdColors.textMuted,
                          ),
                        ),
                      ),
                      Text('@$handle', style: SdType.bodyStrong),
                      const Spacer(),
                      Text('$xp XP', style: SdType.data.copyWith(color: SdColors.gold)),
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
