import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class TokenStorage {
  TokenStorage({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  static const _tokenKey = 'supabase_management_token';
  static const _pendingRestoresKey = 'pending_supabase_restores';
  final FlutterSecureStorage _storage;

  Future<void> saveToken(String token) =>
      _storage.write(key: _tokenKey, value: token);

  Future<String?> getToken() => _storage.read(key: _tokenKey);

  Future<void> clearToken() => _storage.delete(key: _tokenKey);

  Future<Set<String>> getPendingRestores() async {
    final value = await _storage.read(key: _pendingRestoresKey);
    if (value == null || value.isEmpty) return <String>{};
    return value
        .split('\n')
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .toSet();
  }

  Future<void> savePendingRestores(Set<String> projectRefs) async {
    if (projectRefs.isEmpty) {
      await _storage.delete(key: _pendingRestoresKey);
      return;
    }
    await _storage.write(
      key: _pendingRestoresKey,
      value: projectRefs.join('\n'),
    );
  }
}
