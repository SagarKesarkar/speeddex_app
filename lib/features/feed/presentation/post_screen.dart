import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../core/theme/sd_tokens.dart';
import '../../../core/theme/sd_typography.dart';
import '../../../core/widgets/sd_states.dart';
import '../../../domain/social.dart';
import '../application/feed_controller.dart';
import 'feed_post_tile.dart';
import 'feed_screen.dart';
import 'feed_sheets.dart';

final _postProvider = FutureProvider.autoDispose.family<FeedPost, String>(
  (ref, id) => ref.watch(feedRepositoryProvider).post(id),
);

/// One feed post with its likes and comments, opened from a like or comment
/// notification or from the counts under a card in a grid.
class PostScreen extends ConsumerStatefulWidget {
  const PostScreen({super.key, required this.postId});
  final String postId;

  @override
  ConsumerState<PostScreen> createState() => _PostScreenState();
}

class _PostScreenState extends ConsumerState<PostScreen> {
  /// The post as changed here (likes, comment count), over what was loaded.
  FeedPost? _post;

  Future<void> _like(FeedPost p) async {
    final liked = !p.viewerHasLiked;
    final next = p.copyWith(viewerHasLiked: liked, likeCount: p.likeCount + (liked ? 1 : -1));
    setState(() => _post = next);
    try {
      await ref.read(feedRepositoryProvider).setLiked(p.id, liked: liked);
      ref.read(feedControllerProvider.notifier).applyPost(next);
      if (liked) {
        ref
          ..invalidate(dailyGoalsProvider)
          ..invalidate(profileProvider);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _post = p);
      showSdSnack(context, 'Couldn’t update like. Try again.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final loaded = ref.watch(_postProvider(widget.postId));
    return Scaffold(
      appBar: AppBar(title: Text('POST', style: SdType.label)),
      body: loaded.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) =>
            SdErrorState(error: e, onRetry: () => ref.invalidate(_postProvider(widget.postId))),
        data: (fetched) {
          final p = _post ?? fetched;
          return CommentsThread(
            post: p,
            onAdded: () {
              final current = _post ?? fetched;
              setState(() => _post = current.copyWith(commentCount: current.commentCount + 1));
            },
            header: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: SdSize.maxContentWidth),
              child: FeedPostTile(
                post: p,
                onOpen: () => context.push('/card/${p.card.id}'),
                onLike: () => _like(p),
                // The comments are right below.
                onComments: () {},
                onMore: () => showReportSheet(context, ref, p),
                onAuthor: () => openAuthor(context, p),
              ),
            ),
          );
        },
      ),
    );
  }
}
