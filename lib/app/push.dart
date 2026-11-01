import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/push/push_service.dart';
import '../core/widgets/sd_states.dart';
import 'providers.dart';
import 'router.dart';

const _off = PushConfig(apiKey: '', appId: '', senderId: '', projectId: '');

/// Push for the signed-in player. Started and stopped by the auth controller.
final pushServiceProvider = Provider<PushService>((ref) {
  final profiles = ref.watch(profileRepositoryProvider);
  return PushService(
    // Built-in demo data has no server to register with.
    config: ref.watch(appConfigProvider).usesDevData ? _off : PushConfig.fromEnvironment,
    register: (token, platform) => profiles.registerPushToken(token, platform: platform),
    unregister: profiles.unregisterPushToken,
    onEvent: (e) => _handle(ref, e),
  );
});

void _handle(Ref ref, PushEvent e) {
  // Whatever it was about (a like, a goal, a reviewed scan) changed these.
  ref
    ..invalidate(dailyGoalsProvider)
    ..invalidate(profileProvider);
  final router = ref.read(routerProvider);
  final route = e.route;
  if (e.opened) {
    if (route == null) return;
    // Cards and players open on top; tabs are switched to.
    route.startsWith('/card/') || route.startsWith('/user/')
        ? router.push(route)
        : router.go(route);
    return;
  }
  // Android doesn't show a notification while the app is open: say it here.
  final context = router.routerDelegate.navigatorKey.currentContext;
  final text = [e.title, e.body].whereType<String>().join(' · ');
  if (context != null && context.mounted && text.isNotEmpty) showSdSnack(context, text);
}
