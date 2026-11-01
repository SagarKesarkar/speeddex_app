import 'car_card.dart';

/// Minimal public view of another user.
class UserSummary {
  const UserSummary({
    required this.id,
    required this.handle,
    required this.displayName,
    required this.level,
  });

  final String id;
  final String handle;
  final String displayName;
  final int level;

  String get initials {
    final parts = displayName.trim().split(RegExp(r'\s+'));
    final letters = parts.take(2).map((p) => p.isEmpty ? '' : p[0]).join();
    return letters.isEmpty ? '?' : letters.toUpperCase();
  }
}

class FeedPost {
  const FeedPost({
    required this.id,
    required this.author,
    required this.card,
    required this.likeCount,
    required this.commentCount,
    required this.viewerHasLiked,
    required this.createdAt,
  });

  final String id;
  final UserSummary author;
  final CarCard card;
  final int likeCount;
  final int commentCount;
  final bool viewerHasLiked;
  final DateTime createdAt;

  FeedPost copyWith({int? likeCount, bool? viewerHasLiked, int? commentCount, CarCard? card}) =>
      FeedPost(
        id: id,
        author: author,
        card: card ?? this.card,
        likeCount: likeCount ?? this.likeCount,
        commentCount: commentCount ?? this.commentCount,
        viewerHasLiked: viewerHasLiked ?? this.viewerHasLiked,
        createdAt: createdAt,
      );
}

class FeedComment {
  const FeedComment({
    required this.id,
    required this.author,
    required this.text,
    required this.createdAt,
  });

  final String id;
  final UserSummary author;
  final String text;
  final DateTime createdAt;
}

/// Ranking scopes from spec §3.4.
enum LeaderboardScope {
  world('World'),
  country('Country'),
  state('State'),
  city('City'),
  nearby('Nearby');

  const LeaderboardScope(this.label);
  final String label;
}

enum LeaderboardPeriod {
  allTime('All time'),
  weekly('Weekly'),
  monthly('Monthly');

  const LeaderboardPeriod(this.label);
  final String label;
}

class LeaderboardEntry {
  const LeaderboardEntry({
    required this.rank,
    required this.user,
    required this.xp,
    required this.carCount,
    this.isViewer = false,
  });

  final int rank;
  final UserSummary user;
  final int xp;
  final int carCount;
  final bool isViewer;
}

class LeaderboardPage {
  const LeaderboardPage({required this.entries, required this.viewer});

  final List<LeaderboardEntry> entries;

  /// The viewer's own position, returned even when outside the loaded page.
  final LeaderboardEntry? viewer;
}
