import 'package:flutter/foundation.dart';

/// Build-time configuration, supplied via `--dart-define`.
///
/// No secrets belong here: anything compiled into the client is public.
/// API keys for AI, ads verification and stores live on the backend only.
class AppConfig {
  const AppConfig._(this.apiBaseUrl);

  /// Empty means "no backend configured" and the app runs on clearly labelled
  /// development data.
  final Uri? apiBaseUrl;

  bool get usesDevData => apiBaseUrl == null;

  /// Hosts allowed over plain HTTP in non-release builds: the Android
  /// emulator's alias for the host machine, and loopback.
  static const _localHosts = {'10.0.2.2', 'localhost', '127.0.0.1'};

  static AppConfig fromEnvironment() =>
      parse(const String.fromEnvironment('API_BASE_URL'), allowLocalHttp: !kReleaseMode);

  @visibleForTesting
  static AppConfig parse(String raw, {required bool allowLocalHttp}) {
    if (raw.isEmpty) return const AppConfig._(null);
    final uri = Uri.tryParse(raw);
    if (uri == null || uri.host.isEmpty) {
      throw StateError('API_BASE_URL must be an absolute URL.');
    }
    final localHttp = allowLocalHttp && uri.scheme == 'http' && _localHosts.contains(uri.host);
    // Anything else must be HTTPS, so a misconfigured build fails loudly
    // instead of sending tokens in clear text.
    if (uri.scheme != 'https' && !localHttp) {
      throw StateError(
        'API_BASE_URL must use https:// (plain http is allowed only for a local '
        'server in debug builds).',
      );
    }
    return AppConfig._(uri.replace(path: uri.path.replaceAll(RegExp(r'/+$'), '')));
  }
}
