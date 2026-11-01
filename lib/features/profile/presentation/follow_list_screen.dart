import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../core/errors/app_failure.dart';
import '../../../core/theme/sd_colors.dart';
import '../../../core/theme/sd_tokens.dart';
import '../../../core/theme/sd_typography.dart';
import '../../../core/widgets/sd_primitives.dart';
import '../../../core/widgets/sd_states.dart';
import '../../../data/repositories.dart';
import '../../../domain/social.dart';

/// A spotter's followers, or the spotters they follow, loaded a page at a
/// time. Tapping someone opens their profile.
class FollowListScreen extends ConsumerStatefulWidget {
  const FollowListScreen({super.key, required this.userId, required this.list});
  final String userId;
  final FollowList list;

  @override
  ConsumerState<FollowListScreen> createState() => _FollowListScreenState();
}

class _FollowListScreenState extends ConsumerState<FollowListScreen> {
  final List<UserSummary> _users = [];
  String? _cursor;
  bool _done = false;
  bool _loading = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _loadMore();
  }

  Future<void> _loadMore() async {
    if (_loading || _done) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await ref
          .read(usersRepositoryProvider)
          .follows(widget.userId, widget.list, cursor: _cursor);
      if (!mounted) return;
      setState(() {
        _users.addAll(page.users);
        _cursor = page.nextCursor;
        _done = page.nextCursor == null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _open(UserSummary u) {
    // Your own entry opens the Profile tab, as names in the feed do.
    if (u.id == ref.read(profileProvider).value?.id) {
      context.go('/profile');
    } else {
      context.push('/user/${u.id}');
    }
  }

  @override
  Widget build(BuildContext context) {
    final followers = widget.list == FollowList.followers;
    final title = followers ? 'FOLLOWERS' : 'FOLLOWING';
    if (_users.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: Text(title)),
        body: switch ((_error, _done)) {
          (final Object e, _) => SdErrorState(error: e, onRetry: _loadMore),
          (_, true) => SdEmptyState(
            icon: followers ? Icons.group_outlined : Icons.person_search_outlined,
            title: followers ? 'No followers yet' : 'Not following anyone yet',
            message: followers
                ? 'Spotters who follow this profile appear here.'
                : 'Spotters this profile follows appear here.',
          ),
          _ => const Center(child: CircularProgressIndicator()),
        },
      );
    }
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: NotificationListener<ScrollNotification>(
        // Load the next page as the end of the list comes into view.
        onNotification: (n) {
          if (n.metrics.extentAfter < 400) _loadMore();
          return false;
        },
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: SdSize.maxContentWidth),
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(
                SdSpace.gutter,
                SdSpace.md,
                SdSpace.gutter,
                SdSpace.huge,
              ),
              itemCount: _users.length + 1,
              separatorBuilder: (_, _) => const SizedBox(height: SdSpace.sm),
              itemBuilder: (_, i) => i < _users.length
                  ? _UserTile(user: _users[i], onTap: () => _open(_users[i]))
                  : _footer(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _footer() {
    if (_error != null) {
      return Column(
        children: [
          Text(_error!.userMessage, textAlign: TextAlign.center, style: SdType.caption),
          TextButton(onPressed: _loadMore, child: const Text('Try again')),
        ],
      );
    }
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.all(SdSpace.lg),
        child: Center(
          child: SizedBox.square(dimension: 24, child: CircularProgressIndicator(strokeWidth: 2)),
        ),
      );
    }
    return const SizedBox.shrink();
  }
}

class _UserTile extends StatelessWidget {
  const _UserTile({required this.user, required this.onTap});
  final UserSummary user;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '${user.displayName}, @${user.handle}, level ${user.level}',
      excludeSemantics: true,
      child: Material(
        color: SdColors.surface,
        borderRadius: const BorderRadius.all(SdRadius.md),
        child: InkWell(
          onTap: onTap,
          borderRadius: const BorderRadius.all(SdRadius.md),
          child: Padding(
            padding: const EdgeInsets.all(SdSpace.md),
            child: Row(
              children: [
                Monogram(initials: user.initials, size: 44),
                const SizedBox(width: SdSpace.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        user.displayName,
                        style: SdType.body.copyWith(fontWeight: FontWeight.w600),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '@${user.handle} · LV ${user.level}',
                        style: SdType.caption.copyWith(color: SdColors.textMuted),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right_rounded, color: SdColors.textFaint),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
