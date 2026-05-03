// test/unit/password_service_test.dart
//
// Тесты для PasswordService

import 'package:test/test.dart';
import 'package:aq_security/aq_security_server.dart';

void main() {
  group('PasswordService', () {
    late PasswordService service;

    setUp(() {
      service = PasswordService(bcryptCost: 4); // низкий cost для быстрых тестов
    });

    test('hash создаёт bcrypt hash', () {
      final hash = service.hash('MyPassword123!');

      expect(hash, isNotEmpty);
      expect(hash, startsWith(r'$2'));
      expect(hash.length, greaterThan(50));
    });

    test('hash создаёт разные хеши для одного пароля', () {
      final hash1 = service.hash('MyPassword123!');
      final hash2 = service.hash('MyPassword123!');

      expect(hash1, isNot(equals(hash2)));
    });

    test('verify возвращает true для правильного пароля', () {
      final password = 'MyPassword123!';
      final hash = service.hash(password);

      final result = service.verify(password, hash);

      expect(result, isTrue);
    });

    test('verify возвращает false для неправильного пароля', () {
      final hash = service.hash('MyPassword123!');

      final result = service.verify('WrongPassword', hash);

      expect(result, isFalse);
    });

    test('verify возвращает false для невалидного хеша', () {
      final result = service.verify('password', 'invalid_hash');

      expect(result, isFalse);
    });

    test('validateStrength принимает сильный пароль', () {
      final result = service.validateStrength('MyPassword123!');

      expect(result.valid, isTrue);
      expect(result.errors, isEmpty);
    });

    test('validateStrength отклоняет короткий пароль', () {
      final result = service.validateStrength('Pass1!');

      expect(result.valid, isFalse);
      expect(result.errors, contains('Password must be at least 8 characters'));
    });

    test('validateStrength отклоняет пароль без uppercase', () {
      final result = service.validateStrength('mypassword123!');

      expect(result.valid, isFalse);
      expect(result.errors, contains('Password must contain at least one uppercase letter'));
    });

    test('validateStrength отклоняет пароль без lowercase', () {
      final result = service.validateStrength('MYPASSWORD123!');

      expect(result.valid, isFalse);
      expect(result.errors, contains('Password must contain at least one lowercase letter'));
    });

    test('validateStrength отклоняет пароль без цифр', () {
      final result = service.validateStrength('MyPassword!');

      expect(result.valid, isFalse);
      expect(result.errors, contains('Password must contain at least one digit'));
    });

    test('validateStrength отклоняет пароль без спецсимволов', () {
      final result = service.validateStrength('MyPassword123');

      expect(result.valid, isFalse);
      expect(result.errors, contains('Password must contain at least one special character'));
    });

    test('validateStrength отклоняет слишком длинный пароль', () {
      final longPassword = 'A' * 129 + '1!';
      final result = service.validateStrength(longPassword);

      expect(result.valid, isFalse);
      expect(result.errors, contains('Password must be less than 128 characters'));
    });

    test('validateStrength отклоняет распространённые пароли', () {
      final commonPasswords = [
        'password',
        'Password123',
        'qwerty',
        'Letmein1',
      ];

      for (final password in commonPasswords) {
        final result = service.validateStrength(password);
        expect(result.valid, isFalse, reason: 'Should reject: $password');
      }
    });

    test('validateStrength возвращает все ошибки', () {
      final result = service.validateStrength('pass');

      expect(result.valid, isFalse);
      expect(result.errors.length, greaterThan(1));
      expect(result.message, isNotEmpty);
    });
  });
}
