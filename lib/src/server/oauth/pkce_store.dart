// pkgs/aq_security/lib/src/server/oauth/pkce_store.dart
//
// PKCE (Proof Key for Code Exchange) для мобильных OAuth клиентов.
// RFC 7636: https://tools.ietf.org/html/rfc7636
//
// Flow:
// 1. Клиент генерирует code_verifier (случайная строка)
// 2. Клиент вычисляет code_challenge = BASE64URL(SHA256(code_verifier))
// 3. Клиент отправляет code_challenge на /oauth/authorize
// 4. Сервер сохраняет code_challenge
// 5. При callback клиент отправляет code_verifier
// 6. Сервер проверяет: SHA256(code_verifier) == code_challenge

import 'dart:convert';
import 'package:crypto/crypto.dart';

/// In-memory PKCE challenge store с автоматической очисткой.
final class PkceStore {
  PkceStore({this.ttl = const Duration(minutes: 10)});

  final Duration ttl;
  final _challenges = <String, _ChallengeEntry>{};

  /// Сохраняет code_challenge для state token.
  void store({
    required String state,
    required String codeChallenge,
    required String codeChallengeMethod,
  }) {
    _cleanup();

    _challenges[state] = _ChallengeEntry(
      codeChallenge: codeChallenge,
      codeChallengeMethod: codeChallengeMethod,
      expiresAt: DateTime.now().add(ttl),
    );
  }

  /// Валидирует code_verifier против сохранённого code_challenge.
  /// Возвращает true если валиден, удаляет challenge (one-time use).
  bool validate({
    required String state,
    required String codeVerifier,
  }) {
    _cleanup();

    final entry = _challenges.remove(state);
    if (entry == null) return false;

    if (DateTime.now().isAfter(entry.expiresAt)) {
      return false;
    }

    // Вычисляем challenge из verifier
    final computedChallenge = _computeChallenge(
      codeVerifier,
      entry.codeChallengeMethod,
    );

    return computedChallenge == entry.codeChallenge;
  }

  /// Вычисляет code_challenge из code_verifier.
  String _computeChallenge(String verifier, String method) {
    switch (method) {
      case 'S256':
        final bytes = utf8.encode(verifier);
        final hash = sha256.convert(bytes);
        return base64UrlEncode(hash.bytes).replaceAll('=', '');
      case 'plain':
        return verifier;
      default:
        throw ArgumentError('Unsupported code_challenge_method: $method');
    }
  }

  /// Удаляет истёкшие challenges.
  void _cleanup() {
    final now = DateTime.now();
    _challenges.removeWhere((_, entry) => now.isAfter(entry.expiresAt));
  }

  /// Количество активных challenges (для мониторинга).
  int get activeCount {
    _cleanup();
    return _challenges.length;
  }
}

final class _ChallengeEntry {
  const _ChallengeEntry({
    required this.codeChallenge,
    required this.codeChallengeMethod,
    required this.expiresAt,
  });

  final String codeChallenge;
  final String codeChallengeMethod;
  final DateTime expiresAt;
}
