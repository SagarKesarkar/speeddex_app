/// One of today's goals. Progress is counted by the server from what the
/// player did today (UTC), and its XP is paid once, when it's reached.
class DailyGoal {
  const DailyGoal({
    required this.id,
    required this.title,
    required this.description,
    required this.progress,
    required this.target,
    required this.xp,
    required this.completed,
  });

  final String id;
  final String title;
  final String description;
  final int progress;
  final int target;
  final int xp;
  final bool completed;

  double get fraction => target <= 0 ? 1 : (progress / target).clamp(0, 1).toDouble();
}

class DailyGoals {
  const DailyGoals({
    required this.goals,
    required this.bonusTitle,
    required this.bonusXp,
    required this.bonusCompleted,
    required this.xpEarnedToday,
    required this.resetsAt,
  });

  final List<DailyGoal> goals;

  /// Paid once every goal is done.
  final String bonusTitle;
  final int bonusXp;
  final bool bonusCompleted;
  final int xpEarnedToday;
  final DateTime resetsAt;

  int get done => goals.where((g) => g.completed).length;
  int get xpAvailable => goals.fold(bonusXp, (n, g) => n + g.xp);
}
