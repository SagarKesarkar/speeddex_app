import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../../core/errors/app_failure.dart';
import '../../core/security/token_store.dart';

/// HTTP transport for the SpeedDex API.
///
/// Attaches the access token, refreshes it once on expiry (one refresh in
/// flight at a time, rotating the refresh token), and converts the API error
/// envelope into typed [AppFailure]s. Tokens and bodies are never logged.
class ApiClient {
  ApiClient({
    required this.baseUrl,
    required this.tokens,
    http.Client? client,
    this.onSessionExpired,
    this.timeout = const Duration(seconds: 20),
  }) : _http = client ?? http.Client();

  final Uri baseUrl;
  final TokenStore tokens;
  final http.Client _http;
  final Duration timeout;

  /// Called when the session can't be refreshed, so the app can sign out.
  void Function()? onSessionExpired;

  Future<void>? _refreshing;

  Uri _uri(String path, [Map<String, String?>? query]) {
    final q = {
      for (final e in (query ?? const {}).entries)
        if (e.value != null) e.key: e.value!,
    };
    return baseUrl.replace(path: '${baseUrl.path}/v1$path', queryParameters: q.isEmpty ? null : q);
  }

  /// Re-points a server-issued URL (signed upload or media link) at this
  /// client's base URL. Signatures cover the path and query, not the host.
  /// Other URLs (catalogue photos published on the SpeedDex website) are
  /// left as they are.
  Uri rebase(String absolute) {
    final u = Uri.parse(absolute);
    if (!u.path.startsWith('/v1/')) return u;
    return baseUrl.replace(path: u.path, query: u.query.isEmpty ? null : u.query);
  }

  Future<dynamic> get(String path, {Map<String, String?>? query}) =>
      _send('GET', path, query: query);
  Future<dynamic> post(String path, [Object? body]) => _send('POST', path, body: body ?? const {});
  Future<dynamic> put(String path, [Object? body]) => _send('PUT', path, body: body);
  Future<dynamic> patch(String path, Object body) => _send('PATCH', path, body: body);
  Future<dynamic> delete(String path, [Object? body]) => _send('DELETE', path, body: body);

  /// Unauthenticated call (sign-in, registration, refresh).
  Future<dynamic> postPublic(String path, Object body) =>
      _send('POST', path, body: body, auth: false);

  Future<dynamic> _send(
    String method,
    String path, {
    Map<String, String?>? query,
    Object? body,
    bool auth = true,
    bool retried = false,
  }) async {
    final req = http.Request(method, _uri(path, query));
    req.headers['accept'] = 'application/json';
    if (body != null) {
      req.headers['content-type'] = 'application/json';
      req.body = jsonEncode(body);
    }
    if (auth) {
      final token = await tokens.readAccess();
      if (token == null) throw const SessionExpiredFailure();
      req.headers['authorization'] = 'Bearer $token';
    }

    final res = await _execute(req);
    if (res.statusCode == 401 && auth && !retried) {
      final code = _errorCode(res.body);
      if (code == 'AUTH_TOKEN_EXPIRED' || code == 'AUTH_REQUIRED') {
        await _refreshOnce();
        return _send(method, path, query: query, body: body, auth: auth, retried: true);
      }
    }
    return _decode(res);
  }

  /// Uploads raw bytes to a signed URL (no bearer token: the URL is the credential).
  Future<void> putBytes(Uri url, List<int> bytes, {String contentType = 'image/jpeg'}) async {
    final req = http.Request('PUT', url)
      ..headers['content-type'] = contentType
      ..bodyBytes = bytes;
    _decode(await _execute(req, timeout: const Duration(seconds: 60)));
  }

  Future<http.Response> _execute(http.BaseRequest req, {Duration? timeout}) async {
    try {
      final streamed = await _http.send(req).timeout(timeout ?? this.timeout);
      return await http.Response.fromStream(streamed);
    } on SocketException {
      throw const NetworkFailure();
    } on TimeoutException {
      throw const NetworkFailure();
    } on http.ClientException {
      throw const NetworkFailure();
    }
  }

  Future<void> _refreshOnce() {
    return _refreshing ??= _refresh().whenComplete(() => _refreshing = null);
  }

  Future<void> _refresh() async {
    final refresh = await tokens.readRefresh();
    if (refresh == null) await _expire();
    try {
      final body = await _send(
        'POST',
        '/auth/refresh',
        body: {'refreshToken': refresh},
        auth: false,
      );
      await saveSession(body as Map<String, dynamic>);
    } on NetworkFailure {
      rethrow; // offline: keep the session, let the caller retry later
    } on AppFailure {
      await _expire();
    }
  }

  Future<Never> _expire() async {
    await tokens.clear();
    onSessionExpired?.call();
    throw const SessionExpiredFailure();
  }

  Future<void> saveSession(Map<String, dynamic> body) =>
      tokens.save(access: body['accessToken'] as String, refresh: body['refreshToken'] as String);

  static String? _errorCode(String body) {
    try {
      return ((jsonDecode(body) as Map)['error'] as Map)['code'] as String?;
    } catch (_) {
      return null;
    }
  }

  dynamic _decode(http.Response res) {
    if (res.statusCode >= 200 && res.statusCode < 300) {
      return res.body.isEmpty ? null : jsonDecode(utf8.decode(res.bodyBytes));
    }
    throw failureFrom(res.statusCode, res.body);
  }

  /// Maps the API error envelope (spec §5.1) onto app failures.
  static AppFailure failureFrom(int status, String body) {
    Map<String, dynamic> e = const {};
    try {
      e = ((jsonDecode(body) as Map)['error'] as Map).cast<String, dynamic>();
    } catch (_) {}
    final code = e['code'] as String?;
    final message = (e['message'] as String?) ?? const UnknownFailure().message;
    final details = (e['details'] as Map?)?.cast<String, dynamic>() ?? const {};
    final retryable = e['retryable'] == true;
    return switch (code) {
      'AUTH_INVALID_CREDENTIALS' => const InvalidCredentialsFailure(),
      'AUTH_SESSION_REVOKED' ||
      'AUTH_TOKEN_EXPIRED' ||
      'AUTH_REQUIRED' => const SessionExpiredFailure(),
      'INSUFFICIENT_COINS' => InsufficientCoinsFailure(
        required: (details['required'] as num?)?.toInt() ?? 5,
        balance: (details['balance'] as num?)?.toInt() ?? 0,
      ),
      'GARAGE_CAPACITY_REACHED' => const GarageFullFailure(),
      'DAILY_SCAN_LIMIT' => const DailyScanLimitFailure(),
      'AD_REWARD_LIMIT' => AdRewardLimitFailure(message),
      'RATE_LIMITED' => const RateLimitedFailure(),
      'RESOURCE_NOT_FOUND' => NotFoundFailure(message),
      'FEATURE_NOT_CONFIGURED' => ServiceUnavailableFailure(message),
      'INTERNAL_ERROR' => const UnknownFailure(),
      _ when status >= 500 => const UnknownFailure(),
      _ => RequestFailure(
        message,
        code: code,
        retryable: retryable,
        fieldErrors: {
          for (final f in (e['fieldErrors'] as List?) ?? const [])
            (f as Map)['field'] as String: f['message'] as String,
        },
      ),
    };
  }
}
