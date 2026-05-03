// pkgs/aq_security/lib/src/server/email_verification_service.dart
//
// Email verification tokens для регистрации и password reset.
// Токены хранятся in-memory с TTL, в production нужно использовать Redis.

import 'dart:math';
import 'dart:convert';

/// Email verification service.
final class EmailVerificationService {
  EmailVerificationService({
    this.verificationTtl = const Duration(hours: 24),
    this.resetTtl = const Duration(hours: 1),
  });

  final Duration verificationTtl;
  final Duration resetTtl;

  final _verificationTokens = <String, _VerificationEntry>{};
  final _resetTokens = <String, _ResetEntry>{};
  final _random = Random.secure();

  /// Генерирует verification token для email.
  String generateVerificationToken(String email) {
    _cleanup();

    final token = _generateToken();
    final expiresAt = DateTime.now().add(verificationTtl);

    _verificationTokens[token] = _VerificationEntry(
      email: email,
      expiresAt: expiresAt,
    );

    return token;
  }

  /// Валидирует verification token и возвращает email.
  String? validateVerificationToken(String token) {
    _cleanup();

    final entry = _verificationTokens.remove(token);
    if (entry == null) return null;

    if (DateTime.now().isAfter(entry.expiresAt)) {
      return null;
    }

    return entry.email;
  }

  /// Генерирует password reset token для userId.
  String generateResetToken(String userId, String email) {
    _cleanup();

    final token = _generateToken();
    final expiresAt = DateTime.now().add(resetTtl);

    _resetTokens[token] = _ResetEntry(
      userId: userId,
      email: email,
      expiresAt: expiresAt,
    );

    return token;
  }

  /// Валидирует reset token и возвращает userId.
  String? validateResetToken(String token) {
    _cleanup();

    final entry = _resetTokens.remove(token);
    if (entry == null) return null;

    if (DateTime.now().isAfter(entry.expiresAt)) {
      return null;
    }

    return entry.userId;
  }

  /// Отменяет все pending verification tokens для email.
  void cancelVerificationTokens(String email) {
    _verificationTokens.removeWhere((_, entry) => entry.email == email);
  }

  /// Отменяет все pending reset tokens для userId.
  void cancelResetTokens(String userId) {
    _resetTokens.removeWhere((_, entry) => entry.userId == userId);
  }

  /// Удаляет истёкшие токены.
  void _cleanup() {
    final now = DateTime.now();
    _verificationTokens.removeWhere((_, entry) => now.isAfter(entry.expiresAt));
    _resetTokens.removeWhere((_, entry) => now.isAfter(entry.expiresAt));
  }

  /// Генерирует криптографически случайный token (32 байта).
  String _generateToken() {
    final bytes = List<int>.generate(32, (_) => _random.nextInt(256));
    return base64UrlEncode(bytes).replaceAll('=', '');
  }

  /// Количество активных verification tokens (для мониторинга).
  int get activeVerificationCount {
    _cleanup();
    return _verificationTokens.length;
  }

  /// Количество активных reset tokens (для мониторинга).
  int get activeResetCount {
    _cleanup();
    return _resetTokens.length;
  }
}

final class _VerificationEntry {
  const _VerificationEntry({
    required this.email,
    required this.expiresAt,
  });

  final String email;
  final DateTime expiresAt;
}

final class _ResetEntry {
  const _ResetEntry({
    required this.userId,
    required this.email,
    required this.expiresAt,
  });

  final String userId;
  final String email;
  final DateTime expiresAt;
}
