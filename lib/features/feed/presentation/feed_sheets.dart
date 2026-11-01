import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/errors/app_failure.dart';
import '../../../core/theme/sd_colors.dart';
import '../../../core/theme/sd_tokens.dart';
import '../../../core/theme/sd_typography.dart';
import '../../../core/util/format.dart';
import '../../../core/widgets/sd_button.dart';
import '../../../core/widgets/sd_primitives.dart';
import '../../../core/widgets/sd_states.dart';
import '../../../domain/social.dart';
import '../application/feed_controller.dart';

final _commentsProvider = FutureProvider.autoDispose.family<List<FeedComment>, String>(
  (ref, postId) => ref.watch(feedRepositoryProvider).comments(postId),
);

Future<void> showCommentsSheet(BuildContext context, FeedPost post) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (context) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.62,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: SdSpace.gutter),
              child: SdSectionLabel('Comments · ${post.card.displayName}'),
            ),
            Expanded(child: CommentsThread(post: post)),
          ],
        ),
      ),
    ),
  );
}

/// A post's comments with a box to add one. [header] scrolls with the list
/// (the post screen puts the post above its comments).
class CommentsThread extends ConsumerStatefulWidget {
  const CommentsThread({super.key, required this.post, this.header, this.onAdded});
  final FeedPost post;
  final Widget? header;

  /// After a comment is posted.
  final VoidCallback? onAdded;

  @override
  ConsumerState<CommentsThread> createState() => _CommentsThreadState();
}

class _CommentsThreadState extends ConsumerState<CommentsThread> {
  static const maxLength = 500;
  final _input = TextEditingController();
  final List<FeedComment> _added = [];
  bool _sending = false;

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    // Comment text is untrusted: trimmed and length-capped here, sanitised
    // and moderated server-side, and always rendered as plain text.
    final text = _input.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      final c = await ref.read(feedRepositoryProvider).addComment(widget.post.id, text);
      ref.read(feedControllerProvider.notifier).bumpComments(widget.post.id);
      _input.clear();
      setState(() => _added.add(c));
      widget.onAdded?.call();
    } catch (e) {
      if (mounted) showSdSnack(context, e.userMessage);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final comments = ref.watch(_commentsProvider(widget.post.id));
    final header = widget.header;
    Widget withHeader(Widget body) => header == null
        ? body
        : ListView(
            padding: const EdgeInsets.all(SdSpace.gutter),
            children: [
              header,
              const SizedBox(height: SdSpace.xxl),
              body,
            ],
          );
    return Column(
      children: [
        Expanded(
          child: comments.when(
            loading: () => withHeader(
              const Padding(
                padding: EdgeInsets.all(SdSpace.xxl),
                child: Center(child: CircularProgressIndicator()),
              ),
            ),
            error: (e, _) => withHeader(
              SdErrorState(
                error: e,
                onRetry: () => ref.invalidate(_commentsProvider(widget.post.id)),
              ),
            ),
            data: (list) {
              // Comments posted here, unless the loaded list already has them.
              final shown = {for (final c in list) c.id};
              final all = [...list, ..._added.where((c) => !shown.contains(c.id))];
              if (all.isEmpty) {
                return withHeader(
                  const SdEmptyState(
                    icon: Icons.mode_comment_outlined,
                    title: 'No comments yet',
                    message: 'Be the first to say something about this catch.',
                  ),
                );
              }
              if (header != null) {
                return ListView(
                  padding: const EdgeInsets.all(SdSpace.gutter),
                  children: [
                    header,
                    const SizedBox(height: SdSpace.xxl),
                    SdSectionLabel(
                      'Comments',
                      trailing: Text('${all.length}', style: SdType.dataSmall),
                    ),
                    const SizedBox(height: SdSpace.lg),
                    for (final c in all) ...[
                      _CommentRow(comment: c),
                      const SizedBox(height: SdSpace.lg),
                    ],
                  ],
                );
              }
              return ListView.separated(
                padding: const EdgeInsets.all(SdSpace.gutter),
                itemCount: all.length,
                separatorBuilder: (_, _) => const SizedBox(height: SdSpace.lg),
                itemBuilder: (_, i) => _CommentRow(comment: all[i]),
              );
            },
          ),
        ),
        const Divider(),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(SdSpace.gutter, SdSpace.sm, SdSpace.sm, SdSpace.sm),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _input,
                    maxLength: maxLength,
                    minLines: 1,
                    maxLines: 3,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _send(),
                    decoration: const InputDecoration(
                      hintText: 'Add a comment',
                      counterText: '',
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: SdSpace.xs),
                IconButton(
                  tooltip: 'Send comment',
                  onPressed: _sending ? null : _send,
                  icon: _sending
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.send_rounded, color: SdColors.gold),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _CommentRow extends StatelessWidget {
  const _CommentRow({required this.comment});
  final FeedComment comment;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Monogram(initials: comment.author.initials, size: 30),
        const SizedBox(width: SdSpace.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    '@${comment.author.handle}',
                    style: SdType.bodyStrong.copyWith(fontSize: 13),
                  ),
                  const SizedBox(width: SdSpace.sm),
                  Text(SdFormat.ago(comment.createdAt), style: SdType.caption),
                ],
              ),
              const SizedBox(height: 2),
              Text(comment.text, style: SdType.body),
            ],
          ),
        ),
      ],
    );
  }
}

/// Report a capture (spec §3.3). Outcome is never disclosed to the reporter.
Future<void> showReportSheet(BuildContext context, WidgetRef ref, FeedPost post) async {
  const reasons = [
    'Wrong make or model',
    'Not a live photo',
    'Shows people or plates',
    'Offensive or unsafe',
  ];
  final reason = await showModalBottomSheet<String>(
    context: context,
    builder: (context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(SdSpace.gutter, 0, SdSpace.gutter, SdSpace.md),
            child: Text('REPORT THIS CATCH', style: SdType.heading),
          ),
          for (final r in reasons)
            ListTile(
              title: Text(r, style: SdType.body),
              trailing: const Icon(Icons.chevron_right_rounded, color: SdColors.textFaint),
              onTap: () => Navigator.of(context).pop(r),
            ),
          Padding(
            padding: const EdgeInsets.all(SdSpace.gutter),
            child: SdButton(
              label: 'Cancel',
              variant: SdButtonVariant.ghost,
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),
        ],
      ),
    ),
  );
  if (reason == null || !context.mounted) return;
  try {
    await ref.read(feedRepositoryProvider).report(post.id, reason);
    if (context.mounted) {
      showSdSnack(context, 'Report received. Thanks for keeping SpeedDex accurate.', success: true);
    }
  } catch (e) {
    if (context.mounted) showSdSnack(context, e.userMessage);
  }
}
