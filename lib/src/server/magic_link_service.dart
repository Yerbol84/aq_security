// pkgs/aq_security/lib/src/server/magic_link_service.dart
//
// Magic Link (passwordless) authentication service.
// Генерирует одноразовые ссылки для login без пароля.

import 'dart:math';
import 'dart:convert';

/// Magic Link service для passwordless authentication.
final class MagicLinkService {
  MagicLinkService({
    this.ttl = const Duration(minutes: 15),
  });

  final Duration ttl;
  final _tokens = <String, _MagicLinkEntry>{};
  final _random = Random.secure();

  /// Генерирует magic link token для email.
  /// Если newUser=true, создаст нового пользователя при использовании.
  String generateToken({
    required String email,
    bool newUser = false,
    String? displayName,
  }) {
    _cleanup();

    final token = _generateToken();
    final expiresAt = DateTime.now().add(ttl);

    _tokens[token] = _MagicLinkEntry(
      email: email,
      newUser: newUser,
      displayName: displayName,
      expiresAt: expiresAt,
    );

    return token;
  }

  /// Валидирует magic link token и возвращает данные.
  MagicLinkData? validateToken(String token) {
    _cleanup();

    final entry = _tokens.remove(token);
    if (entry == null) return null;

    if (DateTime.now().isAfter(entry.expiresAt)) {
      return null;
    }

    return MagicLinkData(
      email: entry.email,
      newUser: entry.newUser,
      displayName: entry.displayName,
    );
  }

  /// Отменяет все pending magic links для email.
  void cancelTokens(String email) {
    _tokens.removeWhere((_, entry) => entry.email == email);
  }

  /// Удаляет истёкшие токены.
  void _cleanup() {
    final now = DateTime.now();
    _tokens.removeWhere((_, entry) => now.isAfter(entry.expiresAt));
  }

  /// Генерирует криптографически случайный token (32 байта).
  String _generateToken() {
    final bytes = List<int>.generate(32, (_) => _random.nextInt(256));
    return base64UrlEncode(bytes).replaceAll('=', '');
  }

  /// Количество активных magic link tokens (для мониторинга).
  int get activeCount {
    _cleanup();
    return _tokens.length;
  }
}

final class _MagicLinkEntry {
  const _MagicLinkEntry({
    required this.email,
    required this.newUser,
    required this.expiresAt,
    this.displayName,
  });

  final String email;
  final bool newUser;
  final String? displayName;
  final DateTime expiresAt;
}

/// Данные из валидированного magic link token.
final class MagicLinkData {
  const MagicLinkData({
    required this.email,
    required this.newUser,
    this.displayName,
  });

  final String email;
  final bool newUser;
  final String? displayName;
}
