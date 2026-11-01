import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/sd_colors.dart';
import '../../../core/theme/sd_tokens.dart';
import '../../../core/theme/sd_typography.dart';
import '../../../core/widgets/car_visual.dart';
import '../../../core/widgets/sd_primitives.dart';
import '../../../domain/car_card.dart';
import '../../../domain/rarity_tier.dart';

/// The SpeedDex Car Card: header plate, framed capture, tier strip,
/// performance bars and a spec sheet that stays sealed until unlocked.
class CollectorCard extends StatelessWidget {
  const CollectorCard({
    super.key,
    required this.card,
    this.onUnlock,
    this.unlocking = false,
    this.showSpecSheet = true,
    this.footerNote,
    this.heroTag,
  });

  final CarCard card;

  /// When non-null and details are locked, the sealed spec sheet shows an
  /// unlock action. Null hides the action (e.g. a candidate not yet owned).
  final VoidCallback? onUnlock;
  final bool unlocking;
  final bool showSpecSheet;

  /// e.g. "+420 XP" on a fresh catch.
  final String? footerNote;
  final Object? heroTag;

  @override
  Widget build(BuildContext context) {
    final tier = card.tier;
    Widget photo = ClipRRect(
      borderRadius: const BorderRadius.all(SdRadius.xs),
      child: AspectRatio(
        aspectRatio: 4 / 3,
        child: CarVisual(card: card),
      ),
    );
    if (heroTag != null) photo = Hero(tag: heroTag!, child: photo);

    return Semantics(
      container: true,
      label: '${card.displayName}, ${tier.label} tier card',
      child: Container(
        decoration: BoxDecoration(
          borderRadius: const BorderRadius.all(SdRadius.lg),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: tier.isFoil
                ? [tier.color, tier.deep, Color.lerp(tier.color, Colors.white, 0.3)!, tier.deep]
                : [Color.lerp(tier.deep, tier.color, 0.35)!, tier.deep],
          ),
          boxShadow: [
            BoxShadow(
              color: tier.color.withValues(alpha: 0.18),
              blurRadius: 28,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        padding: const EdgeInsets.all(3),
        child: Container(
          decoration: const BoxDecoration(
            color: SdColors.surface,
            borderRadius: BorderRadius.all(Radius.circular(11)),
          ),
          padding: const EdgeInsets.all(SdSpace.sm),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              _HeaderPlate(card: card),
              const SizedBox(height: SdSpace.sm),
              _FramedPhoto(color: tier.color, child: photo),
              const SizedBox(height: SdSpace.sm),
              _TierStrip(card: card),
              const SizedBox(height: SdSpace.sm),
              _PerformanceBlock(card: card),
              if (showSpecSheet) ...[
                const SizedBox(height: SdSpace.sm),
                _SpecSheet(card: card, onUnlock: onUnlock, unlocking: unlocking),
              ],
              const SizedBox(height: SdSpace.sm),
              _Footer(card: card, note: footerNote),
            ],
          ),
        ),
      ),
    );
  }
}

class _HeaderPlate extends StatelessWidget {
  const _HeaderPlate({required this.card});
  final CarCard card;

  @override
  Widget build(BuildContext context) {
    final tier = card.tier;
    return Container(
      padding: const EdgeInsets.fromLTRB(SdSpace.md, SdSpace.sm, SdSpace.md, SdSpace.sm),
      decoration: BoxDecoration(
        borderRadius: const BorderRadius.all(SdRadius.sm),
        gradient: LinearGradient(
          colors: [tier.color.withValues(alpha: 0.28), tier.color.withValues(alpha: 0.06)],
        ),
        border: Border.all(color: tier.color.withValues(alpha: 0.45)),
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
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: SdType.label.copyWith(fontSize: 10, color: tier.color),
                ),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(card.model.toUpperCase(), style: SdType.title.copyWith(fontSize: 26)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FramedPhoto extends StatelessWidget {
  const _FramedPhoto({required this.color, required this.child});
  final Color color;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        border: Border.all(color: SdColors.lineStrong),
        borderRadius: const BorderRadius.all(SdRadius.sm),
      ),
      child: Stack(
        children: [
          child,
          // Viewfinder corner marks.
          Positioned.fill(
            child: IgnorePointer(child: CustomPaint(painter: _CornerPainter(color))),
          ),
        ],
      ),
    );
  }
}

class _CornerPainter extends CustomPainter {
  _CornerPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    const l = 12.0;
    const i = 6.0;
    final p = Paint()
      ..color = color.withValues(alpha: 0.9)
      ..strokeWidth = 1.6
      ..style = PaintingStyle.stroke;
    final r = size.width - i;
    final b = size.height - i;
    canvas
      ..drawPath(
        Path()
          ..moveTo(i, i + l)
          ..lineTo(i, i)
          ..lineTo(i + l, i),
        p,
      )
      ..drawPath(
        Path()
          ..moveTo(r - l, i)
          ..lineTo(r, i)
          ..lineTo(r, i + l),
        p,
      )
      ..drawPath(
        Path()
          ..moveTo(i, b - l)
          ..lineTo(i, b)
          ..lineTo(i + l, b),
        p,
      )
      ..drawPath(
        Path()
          ..moveTo(r - l, b)
          ..lineTo(r, b)
          ..lineTo(r, b - l),
        p,
      );
  }

  @override
  bool shouldRepaint(covariant _CornerPainter old) => old.color != color;
}

class _TierStrip extends StatelessWidget {
  const _TierStrip({required this.card});
  final CarCard card;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: SdSpace.md, vertical: 6),
      decoration: const BoxDecoration(
        color: SdColors.surfaceRaised,
        borderRadius: BorderRadius.all(SdRadius.xs),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              (card.variant ?? 'Standard').toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: SdType.label.copyWith(color: SdColors.text, fontSize: 11),
            ),
          ),
          TierChip(card.tier, dense: true),
        ],
      ),
    );
  }
}

class _PerformanceBlock extends StatelessWidget {
  const _PerformanceBlock({required this.card});
  final CarCard card;

  @override
  Widget build(BuildContext context) {
    final s = card.specs;
    final c = card.tier.color;
    return Container(
      padding: const EdgeInsets.fromLTRB(SdSpace.md, SdSpace.md, SdSpace.md, SdSpace.sm),
      decoration: const BoxDecoration(
        color: SdColors.ink,
        borderRadius: BorderRadius.all(SdRadius.xs),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${card.category} · ${card.origin} · ${card.yearLabel}'.toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: SdType.dataSmall.copyWith(color: SdColors.textMuted),
          ),
          const SizedBox(height: SdSpace.sm),
          ...switch (_availableStats(s)) {
            final stats when stats.isNotEmpty => [
              for (final (label, value, display) in stats) _StatRow(label, value, display, c),
            ],
            _ => [
              Padding(
                padding: const EdgeInsets.symmetric(vertical: SdSpace.xs),
                child: Text(
                  s.engine ?? 'Performance figures not published',
                  style: SdType.dataSmall.copyWith(color: SdColors.textFaint),
                ),
              ),
            ],
          },
        ],
      ),
    );
  }

  /// Up to three stats the catalogue actually has, in priority order. A missing
  /// figure is left out rather than shown as an empty or zero bar.
  static List<(String, double, String)> _availableStats(VehicleSpecs s) => [
    if (s.topSpeedMph case final v?) ('SPD', v / 270, '$v MPH'),
    if (s.horsepower case final v?) ('HP', v / 1100, '$v'),
    if (s.zeroToSixtySeconds case final v?) ('0–60', (13 - v) / 11, '${v}s'),
    if (s.displacementCc case final v?) ('CC', v / 6500, NumberFormat.decimalPattern().format(v)),
  ].take(3).toList();
}

class _StatRow extends StatelessWidget {
  const _StatRow(this.label, this.value, this.display, this.color);
  final String label;
  final double value;
  final String display;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '$label $display',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: [
            SizedBox(width: 40, child: Text(label, style: SdType.dataSmall)),
            Expanded(
              child: StatBar(value: value, color: color),
            ),
            SizedBox(
              width: 78,
              child: Text(
                display,
                textAlign: TextAlign.right,
                style: SdType.data.copyWith(fontSize: 13),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SpecSheet extends StatelessWidget {
  const _SpecSheet({required this.card, required this.onUnlock, required this.unlocking});
  final CarCard card;
  final VoidCallback? onUnlock;
  final bool unlocking;

  @override
  Widget build(BuildContext context) {
    final h = card.hidden;
    final unlocked = card.hiddenUnlocked && h != null;
    final n = NumberFormat.decimalPattern();
    String or(Object? v, [String Function(Object)? f]) => v == null ? '—' : (f?.call(v) ?? '$v');
    // Metric units, as in the catalogue source. "—" marks a figure it lacks.
    final rows = <(String, String)>[
      ('ENGINE', unlocked ? or(card.specs.engine) : ''),
      ('FUEL', unlocked ? or(card.specs.fuelType) : ''),
      ('DRIVE', unlocked ? or(h.drivetrain) : ''),
      ('GEARBOX', unlocked ? or(h.transmission) : ''),
      ('WEIGHT', unlocked ? or(h.curbWeightKg, (v) => '${n.format(v)} kg') : ''),
      ('LENGTH', unlocked ? or(h.lengthMm, (v) => '${n.format(v)} mm') : ''),
    ];

    final grid = Column(
      children: [
        for (var i = 0; i < rows.length; i += 2)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              children: [
                Expanded(child: _SpecCell(rows[i].$1, rows[i].$2, locked: !unlocked)),
                const SizedBox(width: SdSpace.lg),
                Expanded(
                  child: _SpecCell(
                    rows[i + 1].$1,
                    rows[i + 1].$2,
                    locked: !unlocked,
                    valueColor: null,
                  ),
                ),
              ],
            ),
          ),
      ],
    );

    return Container(
      padding: const EdgeInsets.fromLTRB(SdSpace.md, SdSpace.sm, SdSpace.md, SdSpace.sm),
      decoration: const BoxDecoration(
        color: SdColors.ink,
        borderRadius: BorderRadius.all(SdRadius.xs),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('SPEC SHEET', style: SdType.label.copyWith(fontSize: 10, color: SdColors.gold)),
              const Spacer(),
              if (card.ownedByViewer)
                Text(
                  'YOUR CATCH',
                  style: SdType.label.copyWith(fontSize: 9, color: SdColors.success),
                )
              else if (!unlocked)
                const Icon(Icons.lock_rounded, size: 12, color: SdColors.textFaint),
            ],
          ),
          const SizedBox(height: SdSpace.xs),
          grid,
          // Only other players' cards are sold; owners always see their own details.
          if (!unlocked && !card.ownedByViewer && onUnlock != null) ...[
            const SizedBox(height: SdSpace.sm),
            _UnlockBar(onTap: unlocking ? null : onUnlock, busy: unlocking),
          ],
        ],
      ),
    );
  }
}

class _SpecCell extends StatelessWidget {
  const _SpecCell(this.label, this.value, {required this.locked, this.valueColor});
  final String label;
  final String value;
  final bool locked;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: Text(label, style: SdType.dataSmall),
        ),
        const SizedBox(width: SdSpace.sm),
        Expanded(
          child: Align(
            alignment: Alignment.centerRight,
            child: locked
                ? ExcludeSemantics(
                    child: Container(
                      width: 44,
                      height: 10,
                      decoration: BoxDecoration(
                        borderRadius: const BorderRadius.all(Radius.circular(2)),
                        gradient: LinearGradient(
                          colors: [SdColors.surfaceHigh, SdColors.lineStrong, SdColors.surfaceHigh],
                        ),
                      ),
                    ),
                  )
                // Long values (e.g. "5-speed Manual / AMT / CVT") wrap to a
                // second line at a readable size instead of shrinking to fit.
                : Text(
                    value,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.right,
                    style: SdType.data.copyWith(
                      fontSize: value.length > 14 ? 11 : 12.5,
                      height: 1.25,
                      color: valueColor,
                    ),
                  ),
          ),
        ),
      ],
    );
  }
}

class _UnlockBar extends StatelessWidget {
  const _UnlockBar({required this.onTap, required this.busy});
  final VoidCallback? onTap;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Unlock spec sheet for 5 coins',
      excludeSemantics: true,
      child: Material(
        color: SdColors.gold.withValues(alpha: 0.1),
        shape: RoundedRectangleBorder(
          borderRadius: const BorderRadius.all(SdRadius.xs),
          side: BorderSide(color: SdColors.gold.withValues(alpha: 0.5)),
        ),
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            height: 40,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (busy)
                  const SizedBox.square(
                    dimension: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else ...[
                  Text(
                    'UNLOCK DETAILS',
                    style: SdType.label.copyWith(color: SdColors.gold, fontSize: 11),
                  ),
                  const SizedBox(width: SdSpace.sm),
                  const CoinGlyph(size: 14),
                  const SizedBox(width: 4),
                  Text('5', style: SdType.data.copyWith(color: SdColors.gold, fontSize: 13)),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer({required this.card, this.note});
  final CarCard card;
  final String? note;

  @override
  Widget build(BuildContext context) {
    final tier = card.tier;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: SdSpace.md, vertical: 6),
      decoration: BoxDecoration(
        color: tier.color.withValues(alpha: 0.12),
        borderRadius: const BorderRadius.all(SdRadius.xs),
      ),
      child: Row(
        children: [
          Text(card.serial, style: SdType.dataSmall.copyWith(color: SdColors.text)),
          const Spacer(),
          Text(
            note ?? '${card.xp} XP',
            style: SdType.dataSmall.copyWith(color: SdColors.gold, fontWeight: FontWeight.w700),
          ),
          const SizedBox(width: SdSpace.sm),
          ...List.generate(RarityTier.values.length, (i) {
            return Container(
              width: 5,
              height: 5,
              margin: const EdgeInsets.only(left: 2),
              color: i <= tier.index ? tier.color : SdColors.lineStrong,
            );
          }),
        ],
      ),
    );
  }
}
