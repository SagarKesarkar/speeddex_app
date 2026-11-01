import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/router.dart';
import 'core/errors/app_failure.dart';
import 'core/theme/sd_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  if (kDebugMode) {
    // Exposes the accessibility tree to adb/uiautomator for on-device QA.
    SemanticsBinding.instance.ensureSemantics();
  }
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  runApp(const ProviderScope(retry: providerRetry, child: SpeedDexApp()));
}

/// Riverpod retries failed providers forever by default, which hides
/// non-retryable errors (validation, permissions) behind a loading state.
/// Only transient failures are retried, three times with backoff.
Duration? providerRetry(int retryCount, Object error) {
  if (error is! AppFailure || !error.retryable || retryCount >= 3) return null;
  return Duration(milliseconds: 500 * (1 << retryCount));
}

class SpeedDexApp extends ConsumerWidget {
  const SpeedDexApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      title: 'SpeedDex',
      debugShowCheckedModeBanner: false,
      theme: SdTheme.dark(),
      darkTheme: SdTheme.dark(),
      themeMode: ThemeMode.dark,
      routerConfig: ref.watch(routerProvider),
    );
  }
}
