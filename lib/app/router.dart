import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/auth/application/auth_controller.dart';
import '../features/auth/presentation/auth_screens.dart';
import '../features/cards/presentation/card_detail_screen.dart';
import '../features/feed/presentation/feed_screen.dart';
import '../features/feed/presentation/post_screen.dart';
import '../features/garage/presentation/garage_screen.dart';
import '../features/onboarding/onboarding_screen.dart';
import '../data/repositories.dart';
import '../features/profile/presentation/follow_list_screen.dart';
import '../features/profile/presentation/delete_account_screen.dart';
import '../features/profile/presentation/profile_screen.dart';
import '../features/profile/presentation/public_profile_screen.dart';
import '../features/ranking/presentation/ranking_screen.dart';
import '../features/scan/presentation/scan_screen.dart';
import '../features/shell/app_shell.dart';
import '../features/shell/splash_screen.dart';

final _rootKey = GlobalKey<NavigatorState>();

/// Bridges Riverpod auth state to go_router's refresh mechanism.
class _AuthListenable extends ChangeNotifier {
  _AuthListenable(Ref ref) {
    ref.listen(authControllerProvider, (_, _) => notifyListeners());
    ref.listen(onboardingSeenProvider, (_, _) => notifyListeners());
  }
}

final routerProvider = Provider<GoRouter>((ref) {
  final refresh = _AuthListenable(ref);
  ref.onDispose(refresh.dispose);

  return GoRouter(
    navigatorKey: _rootKey,
    initialLocation: '/splash',
    refreshListenable: refresh,
    redirect: (context, state) {
      final auth = ref.read(authControllerProvider);
      final loc = state.matchedLocation;
      final inAuth = loc.startsWith('/auth') || loc == '/onboarding';

      if (auth == AuthStatus.unknown) return loc == '/splash' ? null : '/splash';
      if (auth == AuthStatus.signedOut) {
        if (inAuth) return null;
        return ref.read(onboardingSeenProvider) ? '/auth/login' : '/onboarding';
      }
      // Signed in: keep users out of auth flows.
      // Scan is home: the app always opens on it.
      if (inAuth || loc == '/splash') return '/scan';
      return null;
    },
    routes: [
      GoRoute(path: '/splash', builder: (_, _) => const SplashScreen()),
      GoRoute(path: '/onboarding', builder: (_, _) => const OnboardingScreen()),
      GoRoute(path: '/auth/login', builder: (_, _) => const LoginScreen()),
      GoRoute(path: '/auth/register', builder: (_, _) => const RegisterScreen()),
      GoRoute(path: '/auth/forgot', builder: (_, _) => const ForgotPasswordScreen()),
      // The email and reset token travel in memory (extra), never in the URL.
      GoRoute(
        path: '/auth/forgot/code',
        builder: (_, state) => state.extra is String
            ? ResetCodeScreen(email: state.extra! as String)
            : const ForgotPasswordScreen(),
      ),
      GoRoute(
        path: '/auth/forgot/new',
        builder: (_, state) => state.extra is String
            ? NewPasswordScreen(resetToken: state.extra! as String)
            : const ForgotPasswordScreen(),
      ),
      GoRoute(
        path: '/settings/delete-account',
        parentNavigatorKey: _rootKey,
        builder: (_, _) => const DeleteAccountScreen(),
      ),
      GoRoute(
        path: '/user/:id',
        parentNavigatorKey: _rootKey,
        builder: (_, state) => PublicProfileScreen(userId: state.pathParameters['id']!),
      ),
      for (final list in FollowList.values)
        GoRoute(
          path: '/${list.name}/:id',
          parentNavigatorKey: _rootKey,
          builder: (_, state) => FollowListScreen(userId: state.pathParameters['id']!, list: list),
        ),
      GoRoute(
        path: '/post/:id',
        parentNavigatorKey: _rootKey,
        builder: (_, state) => PostScreen(postId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/card/:id',
        parentNavigatorKey: _rootKey,
        pageBuilder: (context, state) => CustomTransitionPage(
          key: state.pageKey,
          child: CardDetailScreen(cardId: state.pathParameters['id']!),
          transitionsBuilder: (context, animation, _, child) => FadeTransition(
            opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
            child: SlideTransition(
              position: Tween(
                begin: const Offset(0, 0.04),
                end: Offset.zero,
              ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
              child: child,
            ),
          ),
        ),
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => AppShell(shell: shell),
        branches: [
          StatefulShellBranch(
            routes: [GoRoute(path: '/feed', builder: (_, _) => const FeedScreen())],
          ),
          StatefulShellBranch(
            routes: [GoRoute(path: '/ranking', builder: (_, _) => const RankingScreen())],
          ),
          StatefulShellBranch(
            routes: [GoRoute(path: '/scan', builder: (_, _) => const ScanScreen())],
          ),
          StatefulShellBranch(
            routes: [GoRoute(path: '/garage', builder: (_, _) => const GarageScreen())],
          ),
          StatefulShellBranch(
            routes: [GoRoute(path: '/profile', builder: (_, _) => const ProfileScreen())],
          ),
        ],
      ),
    ],
  );
});
