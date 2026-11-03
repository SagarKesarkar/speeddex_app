import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../errors/app_failure.dart';

/// Gets a Google ID token for the API's `POST /v1/auth/google`.
///
/// The token's audience is the server's OAuth client (the "Web client" of
/// the Firebase project), supplied with `--dart-define=GOOGLE_SERVER_CLIENT_ID`.
/// The API accepts it only if that ID is in its GOOGLE_CLIENT_IDS.
class GoogleAuth {
  GoogleAuth({this.serverClientId = const String.fromEnvironment('GOOGLE_SERVER_CLIENT_ID')});

  final String serverClientId;
  bool _initialised = false;

  bool get configured => serverClientId.isNotEmpty;

  /// The ID token, or null if the player closed the account picker.
  Future<String?> idToken() async {
    if (!configured) {
      throw const ServiceUnavailableFailure('Google sign-in is not available in this build.');
    }
    final google = GoogleSignIn.instance;
    try {
      if (!_initialised) {
        await google.initialize(serverClientId: serverClientId);
        _initialised = true;
      }
      // Always offer the account picker, rather than reusing the last account.
      await google.signOut();
      final account = await google.authenticate();
      final token = account.authentication.idToken;
      if (token == null) {
        throw const ServiceUnavailableFailure('Google didn’t confirm the account. Try again.');
      }
      return token;
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled ||
          e.code == GoogleSignInExceptionCode.interrupted) {
        return null;
      }
      debugPrint('Google sign-in failed: ${e.code} ${e.description}');
      throw ServiceUnavailableFailure(
        e.code == GoogleSignInExceptionCode.clientConfigurationError ||
                e.code == GoogleSignInExceptionCode.providerConfigurationError
            ? 'Google sign-in isn’t set up for this app version yet.'
            : 'Google sign-in didn’t work. Try again, or use your email.',
      );
    }
  }

  /// On sign-out, so the next Google sign-in asks which account to use.
  Future<void> signOut() async {
    if (!_initialised) return;
    try {
      await GoogleSignIn.instance.signOut();
    } catch (_) {}
  }
}
