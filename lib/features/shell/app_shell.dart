import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../core/theme/sd_colors.dart';
import '../../core/theme/sd_tokens.dart';
import '../../core/theme/sd_typography.dart';
import '../../core/widgets/sd_primitives.dart';
import '../scan/application/scan_controller.dart';

/// Authenticated shell: five tabs — Feed, Radar, Scan, Garage, Profile —
/// each keeping its own navigation stack. Ranking opens from the Feed header.
///
/// Android back walks back through the tabs the user visited, then to Scan
/// (home), and only closes the app on a second press from Scan.
class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key, required this.shell});

  final StatefulNavigationShell shell;

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  static const _tabs = [
    (Icons.dynamic_feed_outlined, Icons.dynamic_feed_rounded, 'Feed'),
    (Icons.radar_outlined, Icons.radar_rounded, 'Radar'),
    (Icons.center_focus_strong_outlined, Icons.center_focus_strong_rounded, 'Scan'),
    (Icons.garage_outlined, Icons.garage_rounded, 'Garage'),
    (Icons.badge_outlined, Icons.badge_rounded, 'Profile'),
  ];

  static const _exitWindow = Duration(seconds: 2);

  /// Tabs visited before the current one, oldest first, without repeats.
  final List<int> _history = [];
  bool _goingBack = false;
  DateTime? _lastBackOnHome;

  StatefulNavigationShell get shell => widget.shell;

  @override
  void didUpdateWidget(AppShell old) {
    super.didUpdateWidget(old);
    // Tab changes can come from anywhere (a tap, a link to /profile), so the
    // history is kept here rather than in [_select].
    final from = old.shell.currentIndex;
    final to = shell.currentIndex;
    if (from == to) return;
    if (_goingBack) {
      _goingBack = false;
    } else {
      _history
        ..remove(from)
        ..add(from);
    }
    _history.remove(to);
  }

  void _select(int i) {
    HapticFeedback.selectionClick();
    // Re-tapping the current tab pops it back to its root.
    shell.goBranch(i, initialLocation: i == shell.currentIndex);
  }

  /// Scan is the home tab: the app opens on it and back ends there.
  static const _home = 2;

  void _back() {
    // On Scan, back first steps out of a shot being reviewed. A candidate
    // card stays put (leaving the tab keeps it), so no scan is lost.
    if (shell.currentIndex == 2) {
      final ctrl = ref.read(scanControllerProvider.notifier);
      switch (ref.read(scanControllerProvider)) {
        case ScanPreparing() || ScanIdentifying():
          return; // wait for the answer
        case ScanPreview() || ScanFailed() || ScanNeedsReview() || ScanRejected():
          ctrl.retake();
          return;
        case ScanAdded():
          ctrl.reset();
          return;
        case ScanFraming() || ScanResult():
          break;
      }
    }
    if (_history.isNotEmpty || shell.currentIndex != _home) {
      final to = _history.isNotEmpty ? _history.removeLast() : _home;
      _goingBack = true;
      shell.goBranch(to);
      return;
    }
    final now = DateTime.now();
    if (_lastBackOnHome != null && now.difference(_lastBackOnHome!) < _exitWindow) {
      SystemNavigator.pop();
      return;
    }
    _lastBackOnHome = now;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(content: Text('Press back again to exit'), duration: _exitWindow),
      );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // The shell never pops itself: [_back] decides where back goes.
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: Scaffold(
        body: ActiveTab(index: shell.currentIndex, child: shell),
        bottomNavigationBar: DecoratedBox(
          decoration: const BoxDecoration(
            color: SdColors.surface,
            border: Border(top: BorderSide(color: SdColors.line)),
          ),
          child: SafeArea(
            top: false,
            child: SizedBox(
              height: SdSize.navBarHeight,
              child: Row(
                children: [
                  for (final (i, t) in _tabs.indexed)
                    Expanded(
                      child: i == 2
                          ? _ScanTab(selected: shell.currentIndex == 2, onTap: () => _select(2))
                          : _NavTab(
                              icon: shell.currentIndex == i ? t.$2 : t.$1,
                              label: t.$3,
                              index: i,
                              selected: shell.currentIndex == i,
                              onTap: () => _select(i),
                            ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Lets tab screens know whether they are visible. The Scan tab uses this to
/// release the camera whenever it is offstage.
class ActiveTab extends InheritedWidget {
  const ActiveTab({super.key, required this.index, required super.child});

  final int index;

  static int? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ActiveTab>()?.index;

  @override
  bool updateShouldNotify(ActiveTab old) => old.index != index;
}

class _NavTab extends StatelessWidget {
  const _NavTab({
    required this.icon,
    required this.label,
    required this.index,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final int index;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? SdColors.text : SdColors.textFaint;
    return Semantics(
      button: true,
      selected: selected,
      label: '$label, tab ${index + 1} of 5',
      excludeSemantics: true,
      child: InkResponse(
        onTap: onTap,
        radius: 40,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedContainer(
              duration: SdMotion.medium,
              curve: SdMotion.curve,
              width: selected ? 18 : 0,
              height: 2,
              margin: const EdgeInsets.only(bottom: 6),
              color: SdColors.signal,
            ),
            Icon(icon, size: 22, color: color),
            const SizedBox(height: 3),
            Text(
              label.toUpperCase(),
              style: SdType.label.copyWith(fontSize: 9.5, color: color, letterSpacing: 1.2),
            ),
          ],
        ),
      ),
    );
  }
}

class _ScanTab extends StatelessWidget {
  const _ScanTab({required this.selected, required this.onTap});
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: 'Scan, tab 3 of 5',
      excludeSemantics: true,
      child: Center(
        child: GestureDetector(
          onTap: onTap,
          child: AnimatedContainer(
            duration: SdMotion.medium,
            width: 56,
            height: 44,
            decoration: BoxDecoration(
              borderRadius: const BorderRadius.all(SdRadius.md),
              gradient: const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFFEB4A43), SdColors.signal],
              ),
              boxShadow: [
                BoxShadow(
                  color: SdColors.signal.withValues(alpha: selected ? 0.45 : 0.2),
                  blurRadius: selected ? 18 : 10,
                ),
              ],
            ),
            child: const Icon(Icons.photo_camera_rounded, color: SdColors.text, size: 24),
          ),
        ),
      ),
    );
  }
}

/// Large tab title with coin balance; shared by every tab root.
class TabHeader extends ConsumerWidget {
  const TabHeader({
    super.key,
    required this.title,
    this.trailing,
    this.subtitle,
    this.leading,
    this.action,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;

  /// Before the title, e.g. a back button on a pushed screen.
  final Widget? leading;

  /// Shown at the end instead of the coin balance.
  final Widget? action;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final coins = ref.watch(walletProvider).value?.coins;
    final dev = ref.watch(appConfigProvider).usesDevData;
    return Padding(
      padding: const EdgeInsets.fromLTRB(SdSpace.gutter, SdSpace.md, SdSpace.gutter, SdSpace.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (leading != null) ...[leading!, const SizedBox(width: SdSpace.xs)],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Semantics(
                        header: true,
                        // Scale down at large text sizes rather than truncate the tab name.
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(title.toUpperCase(), style: SdType.title, maxLines: 1),
                        ),
                      ),
                    ),
                    if (dev) ...[const SizedBox(width: SdSpace.sm), const DevDataTag()],
                  ],
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(subtitle!, style: SdType.caption),
                ],
              ],
            ),
          ),
          ?trailing,
          if (trailing != null) const SizedBox(width: SdSpace.sm),
          action ?? CoinPill(coins: coins, onTap: () => context.go('/profile')),
        ],
      ),
    );
  }
}

/// Gold trophy in the Feed header: opens the leaderboard.
class RankingButton extends StatelessWidget {
  const RankingButton({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Ranking',
      child: Semantics(
        button: true,
        label: 'Ranking',
        excludeSemantics: true,
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: SdColors.surfaceRaised,
              border: Border.all(color: SdColors.goldDeep.withValues(alpha: 0.6)),
              boxShadow: [BoxShadow(color: SdColors.gold.withValues(alpha: 0.18), blurRadius: 10)],
            ),
            child: const Icon(Icons.emoji_events_rounded, size: 19, color: SdColors.gold),
          ),
        ),
      ),
    );
  }
}
