// pkgs/aq_security/lib/src/client/local_session_store.dart
//
// In-memory token storage for the current session.
// Pure Dart — no platform APIs.
//
// Flutter apps: override with SecureStorageSessionStore (flutter_secure_storage)
// Dart CLI / workers: DefaultLocalSessionStore (in-memory is fine — process lifetime)
//
// The store deliberately does NOT write to disk — that's a platform concern.
// Flutter wraps this and persists to secure storage separately.

import 'package:aq_schema/security/security.dart';

/// Abstract token storage. Override for platform-specific persistence.
abstract interface class ISessionStore {
  TokenPair? getStoredTokens();
  void saveTokens(TokenPair tokens);
  void clear();
}

/// Default in-memory implementation.
/// Sufficient for workers and backend services (process-lifetime sessions).
final class LocalSessionStore implements ISessionStore {
  TokenPair? _tokens;

  @override
  TokenPair? getStoredTokens() => _tokens;

  @override
  void saveTokens(TokenPair tokens) => _tokens = tokens;

  @override
  void clear() => _tokens = null;
}

/// Map-backed store — useful for testing.
final class MapSessionStore implements ISessionStore {
  MapSessionStore({Map<String, dynamic>? backing}) : _map = backing ?? {};

  final Map<String, dynamic> _map;

  @override
  TokenPair? getStoredTokens() {
    if (_map['accessToken'] == null) return null;
    return TokenPair.fromJson(_map.cast<String, dynamic>());
  }

  @override
  void saveTokens(TokenPair tokens) {
    _map.addAll(tokens.toJson());
  }

  @override
  void clear() => _map.clear();
}
