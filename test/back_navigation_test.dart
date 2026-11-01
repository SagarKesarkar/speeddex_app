import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:speeddex/features/shell/app_shell.dart';

const _names = ['Feed', 'Ranking', 'Scan', 'Garage', 'Profile'];

/// The real shell over stand-in tab screens.
GoRouter _router() => GoRouter(
  initialLocation: '/scan',
  routes: [
    GoRoute(
      path: '/detail',
      builder: (_, _) => const Scaffold(body: Text('DETAIL PAGE')),
    ),
    StatefulShellRoute.indexedStack(
      builder: (context, state, shell) => AppShell(shell: shell),
      branches: [
        for (final n in _names)
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/${n.toLowerCase()}',
                builder: (_, _) => Scaffold(body: Center(child: Text('$n screen'))),
              ),
            ],
          ),
      ],
    ),
  ],
);

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  testWidgets('back retraces tabs, then needs a second press on Scan (home) to exit', (
    tester,
  ) async {
    var exits = 0;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (
      call,
    ) async {
      if (call.method == 'SystemNavigator.pop') exits++;
      return null;
    });
    final router = _router();
    await tester.pumpWidget(ProviderScope(child: MaterialApp.router(routerConfig: router)));
    await tester.pumpAndSettle();

    Future<void> back() async {
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
    }

    Future<void> tab(String name) async {
      await tester.tap(find.bySemanticsLabel(RegExp('^$name, tab')));
      await tester.pumpAndSettle();
    }

    await tab('Garage');
    await tab('Profile');
    expect(find.text('Profile screen'), findsOneWidget);

    // A page pushed over the tabs closes first.
    router.push('/detail');
    await tester.pumpAndSettle();
    await back();
    expect(find.text('DETAIL PAGE'), findsNothing);
    expect(find.text('Profile screen'), findsOneWidget);

    await back();
    expect(find.text('Garage screen'), findsOneWidget);
    await back();
    expect(find.text('Scan screen'), findsOneWidget);

    await back();
    expect(exits, 0, reason: 'the first back on Scan only warns');
    expect(find.text('Press back again to exit'), findsOneWidget);
    await back();
    expect(exits, 1);
  });

  testWidgets('back from a tab reached without history goes to Scan', (tester) async {
    final router = _router()..go('/ranking');
    await tester.pumpWidget(ProviderScope(child: MaterialApp.router(routerConfig: router)));
    await tester.pumpAndSettle();
    expect(find.text('Ranking screen'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Scan screen'), findsOneWidget);
  });
}
