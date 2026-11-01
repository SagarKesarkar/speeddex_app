import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../app/push.dart';
import '../../feed/application/feed_controller.dart';

enum AuthStatus { unknown, signedOut, signedIn }

/// Session state. The router redirects on every change.
class AuthController extends Notifier<AuthStatus> {
  @override
  AuthStatus build() {
    // If the API can't refresh the session, return to sign-in everywhere.
    ref.read(apiClientProvider)?.onSessionExpired = _sessionExpired;
    _restore();
    return AuthStatus.unknown;
  }

  void _sessionExpired() {
    if (state != AuthStatus.signedIn) return;
    state = AuthStatus.signedOut;
  }

  /// Account-scoped data must never outlive a session. Tabs in the shell stay
  /// mounted, so anything they cached while signed out (typically a "session
  /// expired" error) would otherwise be shown to the next signed-in user.
  /// Runs on every transition into [AuthStatus.signedIn], after the new tokens
  /// are stored, so each provider refetches with valid credentials.
  void _signedIn() {
    ref
      ..invalidate(profileProvider)
      ..invalidate(walletProvider)
      ..invalidate(garageSummaryProvider)
      ..invalidate(dailyGoalsProvider)
      ..invalidate(feedControllerProvider);
    state = AuthStatus.signedIn;
    unawaited(ref.read(pushServiceProvider).start());
  }

  Future<void> _restore() async {
    try {
      final session = await ref.read(authRepositoryProvider).restore();
      session == null ? state = AuthStatus.signedOut : _signedIn();
    } catch (_) {
      // Unreadable storage is treated as signed out, never as signed in.
      state = AuthStatus.signedOut;
    }
  }

  Future<void> signIn(String email, String password) async {
    await ref.read(authRepositoryProvider).signInWithEmail(email.trim(), password);
    _signedIn();
  }

  Future<void> signInWithGoogle() async {
    await ref.read(authRepositoryProvider).signInWithGoogle();
    _signedIn();
  }

  Future<void> register(String name, String email, String password) async {
    await ref
        .read(authRepositoryProvider)
        .register(displayName: name.trim(), email: email.trim(), password: password);
    _signedIn();
  }

  /// Deletes the account on the server, then forgets it here. Unlike
  /// [signOut], nothing changes locally if the server refuses.
  Future<void> deleteAccount(String password) async {
    await ref.read(authRepositoryProvider).deleteAccount(password);
    // The server has already forgotten this phone; this stops the spotlight.
    await ref.read(pushServiceProvider).stop();
    await ref.read(tokenStoreProvider).clear();
    state = AuthStatus.signedOut;
  }

  Future<void> signOut() async {
    // While the session is still valid, so the server forgets this phone.
    await ref.read(pushServiceProvider).stop();
    try {
      await ref.read(authRepositoryProvider).signOut();
    } finally {
      // Local tokens are cleared even if the server call fails. Cached data
      // is reset on the next sign-in (see [_signedIn]).
      await ref.read(tokenStoreProvider).clear();
      state = AuthStatus.signedOut;
    }
  }
}

final authControllerProvider = NotifierProvider<AuthController, AuthStatus>(AuthController.new);

/// Onboarding is shown once per app launch until persisted preferences exist.
class OnboardingSeen extends Notifier<bool> {
  @override
  bool build() => false;
  void markSeen() => state = true;
}

final onboardingSeenProvider = NotifierProvider<OnboardingSeen, bool>(OnboardingSeen.new);

/// Client-side validation. The server re-validates everything (spec §3.2).
abstract final class AuthValidators {
  static final _email = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]{2,}$');

  static String? email(String? v) {
    final value = v?.trim() ?? '';
    if (value.isEmpty) return 'Enter your email address.';
    if (value.length > 254 || !_email.hasMatch(value)) return 'Enter a valid email address.';
    return null;
  }

  static String? password(String? v) {
    final value = v ?? '';
    if (value.length < 8) return 'Use at least 8 characters.';
    if (value.length > 128) return 'Use 128 characters or fewer.';
    if (!RegExp(r'[A-Za-z]').hasMatch(value) || !RegExp(r'\d').hasMatch(value)) {
      return 'Include at least one letter and one number.';
    }
    return null;
  }

  static String? loginPassword(String? v) =>
      (v == null || v.isEmpty) ? 'Enter your password.' : null;

  static String? displayName(String? v) {
    final value = v?.trim() ?? '';
    if (value.length < 2) return 'Use at least 2 characters.';
    if (value.length > 40) return 'Use 40 characters or fewer.';
    return null;
  }
}
