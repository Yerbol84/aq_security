// pkgs/aq_security/lib/src/server/oauth/csrf_store.dart
//
// CSRF protection для OAuth flows через state parameter.
// State генерируется перед редиректом на OAuth provider,
// сохраняется в памяти с TTL, валидируется при callback.

import 'dart:math';
import 'dart:convert';

/// In-memory CSRF state store с автоматической очисткой.
final class CsrfStore {
  CsrfStore({this.ttl = const Duration(minutes: 10)});

  final Duration ttl;
  final _states = <String, _StateEntry>{};
  final _random = Random.secure();

  /// Генерирует новый state token и сохраняет его.
  String generate({Map<String, dynamic>? metadata}) {
    _cleanup();

    final state = _generateToken();
    final expiresAt = DateTime.now().add(ttl);

    _states[state] = _StateEntry(
      expiresAt: expiresAt,
      metadata: metadata,
    );

    return state;
  }

  /// Валидирует state token и удаляет его (one-time use).
  /// Возвращает metadata если state валиден.
  Map<String, dynamic>? validate(String? state) {
    if (state == null || state.isEmpty) return null;

    _cleanup();

    final entry = _states.remove(state);
    if (entry == null) return null;

    if (DateTime.now().isAfter(entry.expiresAt)) {
      return null;
    }

    return entry.metadata;
  }

  /// Удаляет истёкшие state tokens.
  void _cleanup() {
    final now = DateTime.now();
    _states.removeWhere((_, entry) => now.isAfter(entry.expiresAt));
  }

  /// Генерирует криптографически случайный token (32 байта = 64 hex символа).
  String _generateToken() {
    final bytes = List<int>.generate(32, (_) => _random.nextInt(256));
    return base64UrlEncode(bytes).replaceAll('=', '');
  }

  /// Количество активных state tokens (для мониторинга).
  int get activeCount {
    _cleanup();
    return _states.length;
  }
}

final class _StateEntry {
  const _StateEntry({
    required this.expiresAt,
    this.metadata,
  });

  final DateTime expiresAt;
  final Map<String, dynamic>? metadata;
}
