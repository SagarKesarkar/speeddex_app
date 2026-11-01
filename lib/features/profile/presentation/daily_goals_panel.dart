import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/theme/sd_colors.dart';
import '../../../core/theme/sd_tokens.dart';
import '../../../core/theme/sd_typography.dart';
import '../../../core/widgets/sd_primitives.dart';
import '../../../domain/goals.dart';

/// Today's goals with their progress and XP. XP is paid by the server the
/// moment a goal is reached; this panel only shows where things stand.
class DailyGoalsPanel extends ConsumerWidget {
  const DailyGoalsPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final goals = ref.watch(dailyGoalsProvider);
    return SdPanel(
      accent: SdColors.gold,
      padding: const EdgeInsets.fromLTRB(SdSpace.lg, SdSpace.md, SdSpace.lg, SdSpace.lg),
      child: goals.when(
        loading: () => const SizedBox(
          height: 120,
          child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
        ),
        error: (_, _) => Row(
          children: [
            Expanded(child: Text("Couldn't load today's goals.", style: SdType.caption)),
            TextButton(
              onPressed: () => ref.invalidate(dailyGoalsProvider),
              child: const Text('Try again'),
            ),
          ],
        ),
        data: (g) => _Goals(goals: g),
      ),
    );
  }
}

class _Goals extends StatelessWidget {
  const _Goals({required this.goals});
  final DailyGoals goals;

  String _resetsIn() {
    final left = goals.resetsAt.difference(DateTime.now());
    if (left.isNegative) return 'New goals soon';
    final h = left.inHours;
    final m = left.inMinutes % 60;
    return h > 0 ? 'New goals in ${h}h ${m}m' : 'New goals in ${m}m';
  }

  @override
  Widget build(BuildContext context) {
    final g = goals;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '${g.done} of ${g.goals.length} done',
                overflow: TextOverflow.ellipsis,
                style: SdType.bodyStrong,
              ),
            ),
            const SizedBox(width: SdSpace.sm),
            Flexible(
              child: Text(
                _resetsIn(),
                textAlign: TextAlign.end,
                overflow: TextOverflow.ellipsis,
                style: SdType.dataSmall.copyWith(color: SdColors.textFaint),
              ),
            ),
          ],
        ),
        const SizedBox(height: SdSpace.md),
        for (final goal in g.goals) ...[
          _GoalRow(
            title: goal.title,
            detail: goal.target > 1 ? '${goal.progress} / ${goal.target}' : null,
            fraction: goal.fraction,
            xp: goal.xp,
            completed: goal.completed,
          ),
          const SizedBox(height: SdSpace.sm),
        ],
        const Divider(height: SdSpace.lg, color: SdColors.line),
        _GoalRow(
          title: g.bonusTitle,
          fraction: g.done / (g.goals.isEmpty ? 1 : g.goals.length),
          xp: g.bonusXp,
          completed: g.bonusCompleted,
          bonus: true,
        ),
        const SizedBox(height: SdSpace.md),
        Text(
          g.xpEarnedToday == 0
              ? 'Up to ${g.xpAvailable} XP to earn today.'
              : '${g.xpEarnedToday} of ${g.xpAvailable} XP earned today.',
          style: SdType.caption,
        ),
      ],
    );
  }
}

class _GoalRow extends StatelessWidget {
  const _GoalRow({
    required this.title,
    required this.fraction,
    required this.xp,
    required this.completed,
    this.detail,
    this.bonus = false,
  });

  final String title;
  final String? detail;
  final double fraction;
  final int xp;
  final bool completed;
  final bool bonus;

  @override
  Widget build(BuildContext context) {
    final accent = bonus ? SdColors.gold : SdColors.success;
    return Semantics(
      label:
          '$title${detail == null ? '' : ', $detail'}, $xp XP, ${completed ? 'done' : 'not done yet'}',
      excludeSemantics: true,
      child: Row(
        children: [
          SizedBox.square(
            dimension: 28,
            child: completed
                ? DecoratedBox(
                    decoration: BoxDecoration(shape: BoxShape.circle, color: accent),
                    child: const Icon(Icons.check_rounded, size: 18, color: SdColors.ink),
                  )
                : Stack(
                    alignment: Alignment.center,
                    children: [
                      CircularProgressIndicator(
                        value: fraction,
                        strokeWidth: 2.5,
                        color: accent,
                        backgroundColor: SdColors.line,
                      ),
                      if (bonus) const Icon(Icons.bolt_rounded, size: 15, color: SdColors.gold),
                    ],
                  ),
          ),
          const SizedBox(width: SdSpace.md),
          Expanded(
            child: Text(
              title,
              style: SdType.body.copyWith(
                color: completed ? SdColors.textMuted : SdColors.text,
                decoration: completed ? TextDecoration.lineThrough : null,
                decorationColor: SdColors.textFaint,
              ),
            ),
          ),
          if (detail != null && !completed) ...[
            Text(detail!, style: SdType.dataSmall),
            const SizedBox(width: SdSpace.md),
          ],
          _XpChip(xp: xp, earned: completed, gold: bonus),
        ],
      ),
    );
  }
}

class _XpChip extends StatelessWidget {
  const _XpChip({required this.xp, required this.earned, required this.gold});
  final int xp;
  final bool earned;
  final bool gold;

  @override
  Widget build(BuildContext context) {
    final color = earned ? (gold ? SdColors.gold : SdColors.success) : SdColors.textMuted;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: SdSpace.sm, vertical: 3),
      decoration: BoxDecoration(
        borderRadius: const BorderRadius.all(SdRadius.sm),
        border: Border.all(color: color.withValues(alpha: 0.5)),
        color: earned ? color.withValues(alpha: 0.12) : null,
      ),
      child: Text('+$xp XP', style: SdType.dataSmall.copyWith(fontSize: 11, color: color)),
    );
  }
}
