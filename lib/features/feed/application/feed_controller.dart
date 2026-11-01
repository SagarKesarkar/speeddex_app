import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../domain/car_card.dart';
import '../../../domain/social.dart';

enum FeedMode { list, cards }

class FeedState {
  const FeedState({
    this.posts = const [],
    this.cursor,
    this.hasMore = true,
    this.loading = true,
    this.loadingMore = false,
    this.error,
    this.pageError,
    this.mode = FeedMode.list,
  });

  final List<FeedPost> posts;
  final String? cursor;
  final bool hasMore;
  final bool loading;
  final bool loadingMore;

  /// Blocking error: nothing loaded yet.
  final Object? error;

  /// Non-blocking error: a later page failed; loaded posts are kept.
  final Object? pageError;
  final FeedMode mode;

  FeedState copyWith({
    List<FeedPost>? posts,
    String? Function()? cursor,
    bool? hasMore,
    bool? loading,
    bool? loadingMore,
    Object? Function()? error,
    Object? Function()? pageError,
    FeedMode? mode,
  }) => FeedState(
    posts: posts ?? this.posts,
    cursor: cursor != null ? cursor() : this.cursor,
    hasMore: hasMore ?? this.hasMore,
    loading: loading ?? this.loading,
    loadingMore: loadingMore ?? this.loadingMore,
    error: error != null ? error() : this.error,
    pageError: pageError != null ? pageError() : this.pageError,
    mode: mode ?? this.mode,
  );
}

class FeedController extends Notifier<FeedState> {
  @override
  FeedState build() {
    Future.microtask(refresh);
    return const FeedState();
  }

  Future<void> refresh() async {
    state = state.copyWith(loading: state.posts.isEmpty, error: () => null, pageError: () => null);
    try {
      final page = await ref.read(feedRepositoryProvider).fetch();
      state = state.copyWith(
        posts: page.posts,
        cursor: () => page.nextCursor,
        hasMore: page.nextCursor != null,
        loading: false,
      );
    } catch (e) {
      state = state.posts.isEmpty
          ? state.copyWith(loading: false, error: () => e)
          : state.copyWith(loading: false, pageError: () => e);
    }
  }

  Future<void> loadMore() async {
    if (state.loading || state.loadingMore || !state.hasMore) return;
    state = state.copyWith(loadingMore: true, pageError: () => null);
    try {
      final page = await ref.read(feedRepositoryProvider).fetch(cursor: state.cursor);
      // Cursor pages can overlap during live activity; de-duplicate by id.
      final seen = state.posts.map((p) => p.id).toSet();
      state = state.copyWith(
        posts: [...state.posts, ...page.posts.where((p) => seen.add(p.id))],
        cursor: () => page.nextCursor,
        hasMore: page.nextCursor != null,
        loadingMore: false,
      );
    } catch (e) {
      state = state.copyWith(loadingMore: false, pageError: () => e);
    }
  }

  void setMode(FeedMode mode) => state = state.copyWith(mode: mode);

  /// Optimistic like; rolls back if the request fails. Returns false on rollback.
  Future<bool> toggleLike(String postId) async {
    final before = state.posts.firstWhere((p) => p.id == postId);
    final liked = !before.viewerHasLiked;
    _replace(
      before.copyWith(viewerHasLiked: liked, likeCount: before.likeCount + (liked ? 1 : -1)),
    );
    try {
      await ref.read(feedRepositoryProvider).setLiked(postId, liked: liked);
      // Liking counts towards today's goals, which can pay XP.
      if (liked) {
        ref
          ..invalidate(dailyGoalsProvider)
          ..invalidate(profileProvider);
      }
      return true;
    } catch (_) {
      _replace(before);
      return false;
    }
  }

  /// The post may not be loaded in the feed (opened from a notification).
  void bumpComments(String postId) {
    ref
      ..invalidate(dailyGoalsProvider)
      ..invalidate(profileProvider);
    for (final p in state.posts) {
      if (p.id == postId) _replace(p.copyWith(commentCount: p.commentCount + 1));
    }
  }

  /// A post changed elsewhere (the post screen): keeps the feed in step, if loaded.
  void applyPost(FeedPost post) {
    if (state.posts.any((p) => p.id == post.id)) _replace(post);
  }

  /// Applies an unlocked card to every post showing it.
  void applyCard(CarCard card) {
    state = state.copyWith(
      posts: [
        for (final p in state.posts)
          p.card.id == card.id
              ? p.copyWith(
                  card: p.card.copyWith(hidden: card.hidden, hiddenUnlocked: card.hiddenUnlocked),
                )
              : p,
      ],
    );
  }

  void _replace(FeedPost post) {
    state = state.copyWith(posts: [for (final p in state.posts) p.id == post.id ? post : p]);
  }
}

final feedControllerProvider = NotifierProvider<FeedController, FeedState>(FeedController.new);
