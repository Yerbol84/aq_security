// test/unit/email_verification_test.dart
//
// Тесты для EmailVerificationService

import 'package:test/test.dart';
import 'package:aq_security/aq_security_server.dart';

void main() {
  group('EmailVerificationService', () {
    late EmailVerificationService service;

    setUp(() {
      service = EmailVerificationService(
        verificationTtl: const Duration(seconds: 2),
        resetTtl: const Duration(seconds: 2),
      );
    });

    group('Email Verification', () {
      test('generateVerificationToken создаёт уникальный token', () {
        final token1 = service.generateVerificationToken('test@example.com');
        final token2 = service.generateVerificationToken('test@example.com');

        expect(token1, isNotEmpty);
        expect(token2, isNotEmpty);
        expect(token1, isNot(equals(token2)));
      });

      test('validateVerificationToken возвращает email для валидного token', () {
        const email = 'test@example.com';
        final token = service.generateVerificationToken(email);

        final result = service.validateVerificationToken(token);

        expect(result, equals(email));
      });

      test('validateVerificationToken возвращает null для невалидного token', () {
        final result = service.validateVerificationToken('invalid_token');

        expect(result, isNull);
      });

      test('validateVerificationToken удаляет token после использования', () {
        const email = 'test@example.com';
        final token = service.generateVerificationToken(email);

        final result1 = service.validateVerificationToken(token);
        final result2 = service.validateVerificationToken(token);

        expect(result1, equals(email));
        expect(result2, isNull);
      });

      test('validateVerificationToken возвращает null для истёкшего token', () async {
        const email = 'test@example.com';
        final token = service.generateVerificationToken(email);

        await Future.delayed(const Duration(seconds: 3));

        final result = service.validateVerificationToken(token);

        expect(result, isNull);
      });

      test('cancelVerificationTokens отменяет все токены для email', () {
        const email = 'test@example.com';
        final token1 = service.generateVerificationToken(email);
        final token2 = service.generateVerificationToken(email);

        service.cancelVerificationTokens(email);

        expect(service.validateVerificationToken(token1), isNull);
        expect(service.validateVerificationToken(token2), isNull);
      });

      test('activeVerificationCount возвращает количество активных токенов', () {
        service.generateVerificationToken('test1@example.com');
        service.generateVerificationToken('test2@example.com');

        expect(service.activeVerificationCount, equals(2));
      });
    });

    group('Password Reset', () {
      test('generateResetToken создаёт уникальный token', () {
        final token1 = service.generateResetToken('user1', 'test@example.com');
        final token2 = service.generateResetToken('user1', 'test@example.com');

        expect(token1, isNotEmpty);
        expect(token2, isNotEmpty);
        expect(token1, isNot(equals(token2)));
      });

      test('validateResetToken возвращает userId для валидного token', () {
        const userId = 'user123';
        final token = service.generateResetToken(userId, 'test@example.com');

        final result = service.validateResetToken(token);

        expect(result, equals(userId));
      });

      test('validateResetToken возвращает null для невалидного token', () {
        final result = service.validateResetToken('invalid_token');

        expect(result, isNull);
      });

      test('validateResetToken удаляет token после использования', () {
        const userId = 'user123';
        final token = service.generateResetToken(userId, 'test@example.com');

        final result1 = service.validateResetToken(token);
        final result2 = service.validateResetToken(token);

        expect(result1, equals(userId));
        expect(result2, isNull);
      });

      test('validateResetToken возвращает null для истёкшего token', () async {
        const userId = 'user123';
        final token = service.generateResetToken(userId, 'test@example.com');

        await Future.delayed(const Duration(seconds: 3));

        final result = service.validateResetToken(token);

        expect(result, isNull);
      });

      test('cancelResetTokens отменяет все токены для userId', () {
        const userId = 'user123';
        final token1 = service.generateResetToken(userId, 'test@example.com');
        final token2 = service.generateResetToken(userId, 'test@example.com');

        service.cancelResetTokens(userId);

        expect(service.validateResetToken(token1), isNull);
        expect(service.validateResetToken(token2), isNull);
      });

      test('activeResetCount возвращает количество активных токенов', () {
        service.generateResetToken('user1', 'test1@example.com');
        service.generateResetToken('user2', 'test2@example.com');

        expect(service.activeResetCount, equals(2));
      });
    });

    group('Cleanup', () {
      test('автоматически удаляет истёкшие verification tokens', () async {
        service.generateVerificationToken('test1@example.com');
        service.generateVerificationToken('test2@example.com');

        expect(service.activeVerificationCount, equals(2));

        await Future.delayed(const Duration(seconds: 3));

        expect(service.activeVerificationCount, equals(0));
      });

      test('автоматически удаляет истёкшие reset tokens', () async {
        service.generateResetToken('user1', 'test1@example.com');
        service.generateResetToken('user2', 'test2@example.com');

        expect(service.activeResetCount, equals(2));

        await Future.delayed(const Duration(seconds: 3));

        expect(service.activeResetCount, equals(0));
      });
    });
  });
}
