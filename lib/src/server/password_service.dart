// pkgs/aq_security/lib/src/server/password_service.dart
//
// Password hashing, verification, and strength validation.
// Uses bcrypt for secure password hashing.

import 'package:bcrypt/bcrypt.dart';

/// Password service для hashing и validation.
final class PasswordService {
  PasswordService({this.bcryptCost = 12});

  /// Bcrypt cost factor (10-12 recommended for production).
  final int bcryptCost;

  /// Хеширует пароль с использованием bcrypt.
  String hash(String password) {
    return BCrypt.hashpw(password, BCrypt.gensalt(logRounds: bcryptCost));
  }

  /// Проверяет пароль против хеша.
  bool verify(String password, String hash) {
    try {
      return BCrypt.checkpw(password, hash);
    } catch (e) {
      return false;
    }
  }

  /// Валидирует силу пароля.
  PasswordValidationResult validateStrength(String password) {
    final errors = <String>[];

    if (password.length < 8) {
      errors.add('Password must be at least 8 characters');
    }

    if (password.length > 128) {
      errors.add('Password must be less than 128 characters');
    }

    if (!password.contains(RegExp(r'[A-Z]'))) {
      errors.add('Password must contain at least one uppercase letter');
    }

    if (!password.contains(RegExp(r'[a-z]'))) {
      errors.add('Password must contain at least one lowercase letter');
    }

    if (!password.contains(RegExp(r'[0-9]'))) {
      errors.add('Password must contain at least one digit');
    }

    if (!password.contains(RegExp(r'[!@#$%^&*(),.?":{}|<>]'))) {
      errors.add('Password must contain at least one special character');
    }

    // Check for common weak passwords
    if (_isCommonPassword(password)) {
      errors.add('Password is too common');
    }

    return PasswordValidationResult(
      valid: errors.isEmpty,
      errors: errors,
    );
  }

  /// Проверяет, является ли пароль слишком распространённым.
  bool _isCommonPassword(String password) {
    final common = [
      'password',
      'password123',
      '12345678',
      'qwerty',
      'abc123',
      'monkey',
      '1234567890',
      'letmein',
      'trustno1',
      'dragon',
      'baseball',
      'iloveyou',
      'master',
      'sunshine',
      'ashley',
      'bailey',
      'passw0rd',
      'shadow',
      '123123',
      '654321',
    ];

    return common.contains(password.toLowerCase());
  }
}

/// Результат валидации пароля.
final class PasswordValidationResult {
  const PasswordValidationResult({
    required this.valid,
    required this.errors,
  });

  final bool valid;
  final List<String> errors;

  String get message => errors.join(', ');
}

/// Исключение при работе с паролями.
final class PasswordException implements Exception {
  const PasswordException(this.message);

  final String message;

  @override
  String toString() => 'PasswordException: $message';
}
