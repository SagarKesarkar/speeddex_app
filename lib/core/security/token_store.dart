import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Session tokens, held in the Keychain (iOS) / Keystore-backed storage
/// (Android). Tokens are never written to logs, preferences or plain files.
class TokenStore {
  TokenStore([FlutterSecureStorage? storage])
    : _storage =
          storage ??
          const FlutterSecureStorage(
            iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock_this_device),
          );

  final FlutterSecureStorage _storage;

  static const _accessKey = 'sd.access_token';
  static const _refreshKey = 'sd.refresh_token';

  Future<void> save({required String access, required String refresh}) async {
    await _storage.write(key: _accessKey, value: access);
    await _storage.write(key: _refreshKey, value: refresh);
  }

  Future<String?> readAccess() => _storage.read(key: _accessKey);
  Future<String?> readRefresh() => _storage.read(key: _refreshKey);

  Future<bool> hasSession() async => (await readRefresh()) != null;

  Future<void> clear() async {
    await _storage.delete(key: _accessKey);
    await _storage.delete(key: _refreshKey);
  }
}
