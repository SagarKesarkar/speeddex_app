import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:speeddex/app/providers.dart';
import 'package:speeddex/core/auth/google_auth.dart';
import 'package:speeddex/core/config/app_config.dart';
import 'package:speeddex/data/repositories.dart';
import 'package:speeddex/features/auth/application/auth_controller.dart';

/// Google's account picker, scripted: a token, or null when it's closed.
class _Picker extends GoogleAuth {
  _Picker(this.result) : super(serverClientId: 'web-client.apps.googleusercontent.com');
  final String? result;

  @override
  Future<String?> idToken() async => result;
}

class _Auth implements AuthRepository {
  final tokens = <String>[];

  @override
  Future<AuthSession?> restore() async => null;

  @override
  Future<AuthSession> signInWithGoogle(String idToken) async {
    tokens.add(idToken);
    return const AuthSession(userId: '7');
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

void main() {
  ProviderContainer container(_Auth auth, String? picked) => ProviderContainer(
    overrides: [
      appConfigProvider.overrideWithValue(
        AppConfig.parse('https://api.example.com', allowLocalHttp: false),
      ),
      apiClientProvider.overrideWithValue(null),
      authRepositoryProvider.overrideWithValue(auth),
      googleAuthProvider.overrideWithValue(_Picker(picked)),
    ],
  );

  test('a Google account signs the player in with its ID token', () async {
    final auth = _Auth();
    final c = container(auth, 'id-token-1');
    addTearDown(c.dispose);
    c.read(authControllerProvider);
    expect(await c.read(authControllerProvider.notifier).signInWithGoogle(), isTrue);
    expect(auth.tokens, ['id-token-1']);
    expect(c.read(authControllerProvider), AuthStatus.signedIn);
  });

  test('closing Google’s account picker changes nothing', () async {
    final auth = _Auth();
    final c = container(auth, null);
    addTearDown(c.dispose);
    c.read(authControllerProvider);
    await Future<void>.delayed(Duration.zero);
    expect(await c.read(authControllerProvider.notifier).signInWithGoogle(), isFalse);
    expect(auth.tokens, isEmpty);
    expect(c.read(authControllerProvider), AuthStatus.signedOut);
  });

  test('a build without the server client ID says Google sign-in is unavailable', () async {
    await expectLater(GoogleAuth(serverClientId: '').idToken(), throwsA(anything));
  });
}
