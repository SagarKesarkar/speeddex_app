import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/theme/sd_colors.dart';
import '../../../core/theme/sd_tokens.dart';
import '../../../core/theme/sd_typography.dart';
import '../../../core/util/format.dart';
import '../../../domain/profile.dart';

extension BadgeGradeStyle on BadgeGrade {
  Color get color => switch (this) {
    BadgeGrade.bronze => const Color(0xFFC6865A),
    BadgeGrade.silver => const Color(0xFFBFC6D1),
    BadgeGrade.gold => SdColors.gold,
    BadgeGrade.platinum => const Color(0xFF9EE6E1),
  };

  String get label => switch (this) {
    BadgeGrade.bronze => 'Bronze',
    BadgeGrade.silver => 'Silver',
    BadgeGrade.gold => 'Gold',
    BadgeGrade.platinum => 'Platinum',
  };
}

IconData badgeIcon(String key) => switch (key) {
  'camera' => Icons.photo_camera_rounded,
  'collection' => Icons.grid_view_rounded,
  'crown' => Icons.workspace_premium_rounded,
  'gem' => Icons.diamond_rounded,
  'flame' => Icons.local_fire_department_rounded,
  'star' => Icons.auto_awesome_rounded,
  'globe' => Icons.public_rounded,
  'heart' => Icons.favorite_rounded,
  'people' => Icons.groups_rounded,
  _ => Icons.military_tech_rounded,
};

/// A hexagonal medal in the badge's grade colour. Locked badges are drawn as
/// a dim outline with the progress towards them traced around the edge.
class BadgeMedal extends StatelessWidget {
  const BadgeMedal({super.key, required this.badge, this.size = 56});

  final SpotterBadge badge;
  final double size;

  @override
  Widget build(BuildContext context) {
    final color = badge.grade.color;
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(
        painter: _MedalPainter(
          color: color,
          earned: badge.earned,
          progress: badge.earned ? 1 : badge.fraction,
        ),
        child: Center(
          child: Icon(
            badge.earned ? badgeIcon(badge.icon) : Icons.lock_rounded,
            size: size * (badge.earned ? 0.42 : 0.34),
            color: badge.earned ? color : SdColors.textFaint,
          ),
        ),
      ),
    );
  }
}

class _MedalPainter extends CustomPainter {
  _MedalPainter({required this.color, required this.earned, required this.progress});

  final Color color;
  final bool earned;
  final double progress;

  Path _hex(Offset c, double r) {
    final p = Path();
    for (var i = 0; i < 6; i++) {
      // Pointed top, flat sides left and right; starts at the top corner so
      // progress on a locked badge is traced clockwise from 12 o'clock.
      final a = -math.pi / 2 + i * math.pi / 3;
      final pt = c + Offset(math.cos(a) * r, math.sin(a) * r);
      i == 0 ? p.moveTo(pt.dx, pt.dy) : p.lineTo(pt.dx, pt.dy);
    }
    return p..close();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2;
    final outer = _hex(c, r * 0.96);
    final inner = _hex(c, r * 0.78);

    if (earned) {
      // Soft glow, metallic rim, dark face.
      canvas.drawPath(
        outer,
        Paint()
          ..color = color.withValues(alpha: 0.28)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
      );
      canvas.drawPath(
        outer,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color.lerp(color, Colors.white, 0.35)!,
              color,
              Color.lerp(color, SdColors.ink, 0.45)!,
            ],
            stops: const [0, 0.5, 1],
          ).createShader(outer.getBounds()),
      );
      canvas.drawPath(
        inner,
        Paint()
          ..shader = RadialGradient(
            center: const Alignment(0, -0.4),
            colors: [Color.lerp(SdColors.surfaceHigh, color, 0.18)!, SdColors.ink],
          ).createShader(inner.getBounds()),
      );
      return;
    }

    canvas.drawPath(inner, Paint()..color = SdColors.surfaceRaised);
    canvas.drawPath(
      outer,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = SdColors.lineStrong,
    );
    if (progress > 0) {
      // Trace the progress clockwise from the top along the rim.
      for (final m in outer.computeMetrics()) {
        canvas.drawPath(
          m.extractPath(0, m.length * progress),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.5
            ..strokeCap = StrokeCap.round
            ..color = color.withValues(alpha: 0.85),
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _MedalPainter old) =>
      old.color != color || old.earned != earned || old.progress != progress;
}

/// The player's own badge case: every badge in a grid, earned ones first,
/// the rest with their progress. Tapping one explains how to earn it.
class BadgeCase extends StatelessWidget {
  const BadgeCase({super.key, required this.badges});

  final List<SpotterBadge> badges;

  @override
  Widget build(BuildContext context) {
    if (badges.isEmpty) {
      return Text('No badges yet. Your first catch earns one.', style: SdType.caption);
    }
    return LayoutBuilder(
      builder: (context, c) {
        final columns = c.maxWidth >= 480 ? 4 : 3;
        const gap = SdSpace.sm;
        final width = (c.maxWidth - gap * (columns - 1)) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final b in badges)
              SizedBox(
                width: width,
                child: _BadgeTile(badge: b, onTap: () => showBadgeSheet(context, b)),
              ),
          ],
        );
      },
    );
  }
}

class _BadgeTile extends StatelessWidget {
  const _BadgeTile({required this.badge, required this.onTap});

  final SpotterBadge badge;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final b = badge;
    return Semantics(
      button: true,
      label: b.earned
          ? '${b.name} badge, earned${b.earnedAt == null ? '' : ' ${SdFormat.date(b.earnedAt!)}'}'
          : '${b.name} badge, locked, ${b.progress} of ${b.target}',
      excludeSemantics: true,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: const BorderRadius.all(SdRadius.md),
          child: Ink(
            padding: const EdgeInsets.fromLTRB(SdSpace.xs, SdSpace.md, SdSpace.xs, SdSpace.sm),
            decoration: BoxDecoration(
              color: b.earned ? SdColors.surface : SdColors.ink,
              borderRadius: const BorderRadius.all(SdRadius.md),
              border: Border.all(
                color: b.earned ? b.grade.color.withValues(alpha: 0.35) : SdColors.line,
              ),
            ),
            child: Column(
              children: [
                BadgeMedal(badge: b, size: 52),
                const SizedBox(height: SdSpace.sm),
                Text(
                  b.name.toUpperCase(),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: SdType.label.copyWith(
                    fontSize: 9.5,
                    height: 1.2,
                    color: b.earned ? SdColors.text : SdColors.textMuted,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  b.earned
                      ? (b.earnedAt == null ? b.grade.label : SdFormat.date(b.earnedAt!))
                      : '${SdFormat.compact(b.progress)} / ${SdFormat.compact(b.target)}',
                  style: SdType.dataSmall.copyWith(
                    fontSize: 10,
                    color: b.earned ? b.grade.color : SdColors.textFaint,
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

/// Earned badges on another player's profile, in one scrolling row.
class BadgeStrip extends StatelessWidget {
  const BadgeStrip({super.key, required this.badges});

  final List<SpotterBadge> badges;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 92,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: badges.length,
        separatorBuilder: (_, _) => const SizedBox(width: SdSpace.md),
        itemBuilder: (context, i) {
          final b = badges[i];
          return Semantics(
            button: true,
            label: '${b.name} badge',
            excludeSemantics: true,
            child: GestureDetector(
              onTap: () => showBadgeSheet(context, b),
              child: SizedBox(
                width: 68,
                child: Column(
                  children: [
                    BadgeMedal(badge: b, size: 52),
                    const SizedBox(height: SdSpace.xs),
                    Text(
                      b.name.toUpperCase(),
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      style: SdType.label.copyWith(fontSize: 9, height: 1.2, color: SdColors.text),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

Future<void> showBadgeSheet(BuildContext context, SpotterBadge b) => showModalBottomSheet<void>(
  context: context,
  // The sheet otherwise takes its content's width: an earned badge, with no
  // progress bar, would open as a narrow card instead of a full-width sheet.
  constraints: const BoxConstraints(minWidth: double.infinity),
  builder: (context) => SafeArea(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(SdSpace.gutter, SdSpace.xxl, SdSpace.gutter, SdSpace.xxl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          BadgeMedal(badge: b, size: 96),
          const SizedBox(height: SdSpace.lg),
          Text(b.name, style: SdType.heading, textAlign: TextAlign.center),
          const SizedBox(height: SdSpace.xs),
          Text(b.grade.label.toUpperCase(), style: SdType.label.copyWith(color: b.grade.color)),
          if (b.description.isNotEmpty) ...[
            const SizedBox(height: SdSpace.md),
            Text(
              b.description,
              textAlign: TextAlign.center,
              style: SdType.body.copyWith(color: SdColors.textMuted),
            ),
          ],
          const SizedBox(height: SdSpace.lg),
          if (b.earned)
            Text(
              b.earnedAt == null ? 'Earned' : 'Earned ${SdFormat.date(b.earnedAt!)}',
              style: SdType.data.copyWith(color: SdColors.text),
            )
          else ...[
            ClipRRect(
              borderRadius: const BorderRadius.all(SdRadius.xs),
              child: LinearProgressIndicator(
                value: b.fraction,
                minHeight: 6,
                color: b.grade.color,
                backgroundColor: SdColors.line,
              ),
            ),
            const SizedBox(height: SdSpace.sm),
            Text(
              '${SdFormat.number(b.progress)} of ${SdFormat.number(b.target)}',
              style: SdType.dataSmall,
            ),
          ],
        ],
      ),
    ),
  ),
);
