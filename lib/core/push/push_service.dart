import 'dart:async';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

// firebase_messaging 17 deprecates the FCM token calls in favour of
// installation-ID (FID) direct send. The server sends to FCM registration
// tokens through the HTTP v1 API, which those calls still provide, so they
// stay until the server moves to FID targets.
// ignore_for_file: deprecated_member_use

/// Firebase settings for push, supplied with `--dart-define` (from the
/// Android app registered in the Firebase console). They identify the app,
/// they aren't secrets. Any of them missing: push is off.
class PushConfig {
  const PushConfig({
    required this.apiKey,
    required this.appId,
    required this.senderId,
    required this.projectId,
  });

  final String apiKey;
  final String appId;
  final String senderId;
  final String projectId;

  bool get enabled =>
      apiKey.isNotEmpty && appId.isNotEmpty && senderId.isNotEmpty && projectId.isNotEmpty;

  static const fromEnvironment = PushConfig(
    apiKey: String.fromEnvironment('FIREBASE_API_KEY'),
    appId: String.fromEnvironment('FIREBASE_APP_ID'),
    senderId: String.fromEnvironment('FIREBASE_SENDER_ID'),
    projectId: String.fromEnvironment('FIREBASE_PROJECT_ID'),
  );
}

/// The everyone-gets-it topic for the twice-daily rare-car spotlight.
const spotlightTopic = 'spotlight';

/// A tapped or received push: where it leads, and what it said.
class PushEvent {
  const PushEvent({this.route, this.title, this.body, this.kind, required this.opened});

  /// In-app location, e.g. `/card/12`; validated by [PushService.safeRoute].
  final String? route;
  final String? title;
  final String? body;

  /// What it's about: like, comment, follow, moderation, goal, scans, spotlight.
  final String? kind;

  /// A reward (a completed daily goal): shown with a tick, not an info icon.
  /// The route is checked too, for notifications sent before `kind` existed.
  bool get isReward => kind == 'goal' || (kind == null && route == '/profile');

  /// True when the player tapped it; false when it arrived with the app open.
  final bool opened;
}

/// Registers this install for push notifications while a player is signed in.
class PushService {
  PushService({
    required this.config,
    required this.register,
    required this.unregister,
    required this.onEvent,
  });

  final PushConfig config;
  final Future<void> Function(String token, String platform) register;
  final Future<void> Function(String token) unregister;
  final void Function(PushEvent) onEvent;

  final _subs = <StreamSubscription<Object?>>[];
  String? _token;
  bool _initialised = false;

  /// Only screens the app has; anything else in a push is ignored.
  static final _routes = RegExp(r'^/(card/\d+|post/\d+|user/\d+|profile|garage|scan|feed)$');

  static String? safeRoute(Object? raw) => raw is String && _routes.hasMatch(raw) ? raw : null;

  static PushEvent _event(RemoteMessage m, {required bool opened}) => PushEvent(
    route: safeRoute(m.data['route']),
    title: m.notification?.title,
    body: m.notification?.body,
    kind: m.data['kind'] as String?,
    opened: opened,
  );

  /// After sign-in. Asks for permission (Android 13+), then registers the
  /// token. Never throws: a phone without push still works.
  Future<void> start() async {
    if (!config.enabled || kIsWeb || !(Platform.isAndroid || Platform.isIOS)) return;
    try {
      if (!_initialised) {
        await Firebase.initializeApp(
          options: FirebaseOptions(
            apiKey: config.apiKey,
            appId: config.appId,
            messagingSenderId: config.senderId,
            projectId: config.projectId,
          ),
        );
        _initialised = true;
      }
      final fcm = FirebaseMessaging.instance;
      final settings = await fcm.requestPermission();
      if (settings.authorizationStatus == AuthorizationStatus.denied) return;

      final token = await fcm.getToken();
      if (token != null) await _register(token);
      await fcm.subscribeToTopic(spotlightTopic);

      await _cancel();
      _subs
        ..add(fcm.onTokenRefresh.listen(_register))
        ..add(FirebaseMessaging.onMessage.listen((m) => onEvent(_event(m, opened: false))))
        ..add(FirebaseMessaging.onMessageOpenedApp.listen((m) => onEvent(_event(m, opened: true))));

      // The app was started by tapping a notification.
      final initial = await fcm.getInitialMessage();
      if (initial != null) onEvent(_event(initial, opened: true));
    } catch (e) {
      debugPrint('push unavailable: $e');
    }
  }

  Future<void> _register(String token) async {
    _token = token;
    try {
      await register(token, Platform.isIOS ? 'ios' : 'android');
    } catch (e) {
      debugPrint('push token not registered: $e');
    }
  }

  /// Before sign-out, while the session is still valid: this phone stops
  /// receiving the account's notifications and the spotlight.
  Future<void> stop() async {
    await _cancel();
    if (!_initialised) return;
    final token = _token;
    _token = null;
    try {
      if (token != null) await unregister(token);
      await FirebaseMessaging.instance.unsubscribeFromTopic(spotlightTopic);
      await FirebaseMessaging.instance.deleteToken();
    } catch (e) {
      debugPrint('push sign-out incomplete: $e');
    }
  }

  Future<void> _cancel() async {
    for (final s in _subs) {
      await s.cancel();
    }
    _subs.clear();
  }
}
