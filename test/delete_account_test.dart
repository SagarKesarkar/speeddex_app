import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:speeddex/app/providers.dart';
import 'package:speeddex/core/errors/app_failure.dart';
import 'package:speeddex/core/security/token_store.dart';
import 'package:speeddex/data/repositories.dart';
import 'package:speeddex/features/auth/application/auth_controller.dart';
import 'package:speeddex/features/profile/presentation/delete_account_screen.dart';

class _Auth implements AuthRepository {
  final attempts = <String>[];
  @override
  Future<void> deleteAccount(String password) async {
    attempts.add(password);
    if (password != 'redline99') throw const InvalidCredentialsFailure();
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _Tokens extends TokenStore {
  var cleared = 0;
  @override
  Future<void> clear() async => cleared++;
}

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  testWidgets('needs DELETE typed and the right password, then signs out', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    final auth = _Auth();
    final tokens = _Tokens();
    final container = ProviderContainer(
      overrides: [
        authRepositoryProvider.overrideWithValue(auth),
        tokenStoreProvider.overrideWithValue(tokens),
      ],
    );
    addTearDown(container.dispose);
    container.read(authControllerProvider.notifier).state = AuthStatus.signedIn;
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: DeleteAccountScreen()),
      ),
    );

    final button = find.text('DELETE MY ACCOUNT');
    expect(find.text('THIS CAN’T BE UNDONE'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextFormField, 'Your password'), 'wrong-one');
    await tester.tap(button);
    await tester.pump();
    expect(auth.attempts, isEmpty, reason: 'disabled until DELETE is typed');

    await tester.enterText(find.widgetWithText(TextFormField, 'Type DELETE to confirm'), 'DELETE');
    await tester.pump();
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(auth.attempts, ['wrong-one']);
    expect(find.text('That password isn’t right.'), findsOneWidget);
    expect(container.read(authControllerProvider), AuthStatus.signedIn);
    expect(tokens.cleared, 0);

    await tester.enterText(find.widgetWithText(TextFormField, 'Your password'), 'redline99');
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(auth.attempts.last, 'redline99');
    expect(container.read(authControllerProvider), AuthStatus.signedOut);
    expect(tokens.cleared, 1);
  });
}
