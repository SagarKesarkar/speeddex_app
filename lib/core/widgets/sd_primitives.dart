import 'package:flutter/material.dart';

import '../../domain/rarity_tier.dart';
import '../theme/sd_colors.dart';
import '../theme/sd_tokens.dart';
import '../theme/sd_typography.dart';

/// Bordered surface. The basic building block for grouped content.
class SdPanel extends StatelessWidget {
  const SdPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(SdSpace.lg),
    this.accent,
    this.onTap,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  /// Optional coloured top edge, used sparingly to signal category.
  final Color? accent;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    // Flutter only allows a border radius with uniformly coloured borders, so
    // the accent is drawn as a clipped strip rather than a coloured top border.
    final body = Container(
      clipBehavior: accent == null ? Clip.none : Clip.antiAlias,
      decoration: BoxDecoration(
        color: SdColors.surface,
        borderRadius: const BorderRadius.all(SdRadius.md),
        border: Border.all(color: SdColors.line),
      ),
      child: accent == null
          ? Padding(padding: padding, child: child)
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(height: 2, color: accent),
                Padding(padding: padding, child: child),
              ],
            ),
    );
    if (onTap == null) return body;
    return Material(
      color: Colors.transparent,
      child: InkWell(onTap: onTap, borderRadius: const BorderRadius.all(SdRadius.md), child: body),
    );
  }
}

/// Section header: gold marker, tracked uppercase label, hairline rule.
class SdSectionLabel extends StatelessWidget {
  const SdSectionLabel(this.text, {super.key, this.trailing});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      header: true,
      child: Row(
        children: [
          Container(width: 3, height: 12, color: SdColors.gold),
          const SizedBox(width: SdSpace.sm),
          Text(text.toUpperCase(), style: SdType.label),
          const SizedBox(width: SdSpace.md),
          const Expanded(child: _TickRule()),
          if (trailing != null) ...[const SizedBox(width: SdSpace.md), trailing!],
        ],
      ),
    );
  }
}

class _TickRule extends StatelessWidget {
  const _TickRule();

  @override
  Widget build(BuildContext context) {
    return SizedBox(height: 8, child: CustomPaint(painter: _TickPainter()));
  }
}

class _TickPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = SdColors.line
      ..strokeWidth = 1;
    final mid = size.height / 2;
    canvas.drawLine(Offset(0, mid), Offset(size.width, mid), p);
    for (double x = 0; x < size.width; x += 8) {
      canvas.drawLine(Offset(x, mid - 2.5), Offset(x, mid + 2.5), p);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Rarity chip. Colour plus the tier name — never colour alone.
class TierChip extends StatelessWidget {
  const TierChip(this.tier, {super.key, this.dense = false});

  final RarityTier tier;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: dense ? 6 : SdSpace.sm, vertical: dense ? 2 : 3),
      decoration: BoxDecoration(
        color: tier.color.withValues(alpha: 0.16),
        borderRadius: const BorderRadius.all(SdRadius.xs),
        border: Border.all(color: tier.color.withValues(alpha: 0.7)),
      ),
      child: Text(
        tier.label.toUpperCase(),
        style: SdType.label.copyWith(
          color: tier.color,
          fontSize: dense ? 9 : 10.5,
          letterSpacing: 1.4,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// Segmented performance bar.
class StatBar extends StatelessWidget {
  const StatBar({super.key, required this.value, required this.color, this.segments = 16});

  /// 0–1.
  final double value;
  final Color color;
  final int segments;

  @override
  Widget build(BuildContext context) {
    final filled = (value.clamp(0, 1) * segments).round();
    return Row(
      children: List.generate(segments, (i) {
        return Expanded(
          child: Container(
            height: 7,
            margin: EdgeInsets.only(right: i == segments - 1 ? 0 : 2),
            decoration: BoxDecoration(
              color: i < filled ? color : SdColors.line,
              borderRadius: const BorderRadius.all(Radius.circular(1)),
            ),
          ),
        );
      }),
    );
  }
}

/// Coin balance pill.
class CoinPill extends StatelessWidget {
  const CoinPill({super.key, required this.coins, this.onTap});

  final int? coins;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: coins == null ? 'Coins loading' : '$coins coins',
      button: onTap != null,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: const BorderRadius.all(SdRadius.xl),
        child: Container(
          constraints: const BoxConstraints(minHeight: 32),
          padding: const EdgeInsets.symmetric(horizontal: SdSpace.md),
          decoration: BoxDecoration(
            color: SdColors.surfaceRaised,
            borderRadius: const BorderRadius.all(SdRadius.xl),
            border: Border.all(color: SdColors.goldDeep.withValues(alpha: 0.6)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CoinGlyph(size: 14),
              const SizedBox(width: 6),
              Text(coins?.toString() ?? '—', style: SdType.data.copyWith(color: SdColors.gold)),
            ],
          ),
        ),
      ),
    );
  }
}

class CoinGlyph extends StatelessWidget {
  const CoinGlyph({super.key, this.size = 16});
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFF1D893), SdColors.goldDeep],
        ),
        border: Border.all(color: const Color(0xFF6E5626), width: 1),
      ),
      alignment: Alignment.center,
      child: Text(
        'S',
        style: SdType.label.copyWith(
          fontSize: size * 0.55,
          color: const Color(0xFF5A4419),
          letterSpacing: 0,
          fontWeight: FontWeight.w800,
          height: 1,
        ),
      ),
    );
  }
}

/// Initials monogram used until avatar uploads exist.
class Monogram extends StatelessWidget {
  const Monogram({super.key, required this.initials, this.size = 36, this.color});

  final String initials;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? SdColors.gold;
    return ExcludeSemantics(
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: c.withValues(alpha: 0.14),
          borderRadius: BorderRadius.all(Radius.circular(size * 0.28)),
          border: Border.all(color: c.withValues(alpha: 0.55)),
        ),
        child: Text(
          initials,
          style: SdType.subheading.copyWith(fontSize: size * 0.36, color: c),
        ),
      ),
    );
  }
}

/// Persistent, honest marker that the app is running on development data.
class DevDataTag extends StatelessWidget {
  const DevDataTag({super.key});

  /// `--dart-define=STORE_SCREENSHOTS=true` hides the tag for store screenshots
  /// taken on the demo data. Never set in builds people use.
  static const _hidden = bool.fromEnvironment('STORE_SCREENSHOTS');

  @override
  Widget build(BuildContext context) {
    if (_hidden) return const SizedBox.shrink();
    return Tooltip(
      message: 'No backend connected. Showing development data.',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          borderRadius: const BorderRadius.all(SdRadius.xs),
          border: Border.all(color: SdColors.warning.withValues(alpha: 0.6)),
        ),
        child: Text('DEV DATA', style: SdType.label.copyWith(fontSize: 9, color: SdColors.warning)),
      ),
    );
  }
}
