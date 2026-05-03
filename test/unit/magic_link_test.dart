// test/unit/magic_link_test.dart
//
// Тесты для MagicLinkService

import 'package:test/test.dart';
import 'package:aq_security/aq_security_server.dart';

void main() {
  group('MagicLinkService', () {
    late MagicLinkService service;

    setUp(() {
      service = MagicLinkService(ttl: const Duration(seconds: 2));
    });

    test('generateToken создаёт уникальный token', () {
      final token1 = service.generateToken(email: 'test@example.com');
      final token2 = service.generateToken(email: 'test@example.com');

      expect(token1, isNotEmpty);
      expect(token2, isNotEmpty);
      expect(token1, isNot(equals(token2)));
    });

    test('validateToken возвращает данные для валидного token', () {
      const email = 'test@example.com';
      const displayName = 'Test User';
      final token = service.generateToken(
        email: email,
        newUser: true,
        displayName: displayName,
      );

      final result = service.validateToken(token);

      expect(result, isNotNull);
      expect(result!.email, equals(email));
      expect(result.newUser, isTrue);
      expect(result.displayName, equals(displayName));
    });

    test('validateToken возвращает null для невалидного token', () {
      final result = service.validateToken('invalid_token');

      expect(result, isNull);
    });

    test('validateToken удаляет token после использования (one-time use)', () {
      const email = 'test@example.com';
      final token = service.generateToken(email: email);

      final result1 = service.validateToken(token);
      final result2 = service.validateToken(token);

      expect(result1, isNotNull);
      expect(result1!.email, equals(email));
      expect(result2, isNull);
    });

    test('validateToken возвращает null для истёкшего token', () async {
      const email = 'test@example.com';
      final token = service.generateToken(email: email);

      await Future.delayed(const Duration(seconds: 3));

      final result = service.validateToken(token);

      expect(result, isNull);
    });

    test('generateToken сохраняет newUser flag', () {
      final token1 = service.generateToken(email: 'new@example.com', newUser: true);
      final token2 = service.generateToken(email: 'existing@example.com', newUser: false);

      final result1 = service.validateToken(token1);
      final result2 = service.validateToken(token2);

      expect(result1!.newUser, isTrue);
      expect(result2!.newUser, isFalse);
    });

    test('generateToken сохраняет displayName', () {
      final token = service.generateToken(
        email: 'test@example.com',
        displayName: 'John Doe',
      );

      final result = service.validateToken(token);

      expect(result!.displayName, equals('John Doe'));
    });

    test('generateToken работает без displayName', () {
      final token = service.generateToken(email: 'test@example.com');

      final result = service.validateToken(token);

      expect(result!.email, equals('test@example.com'));
      expect(result.displayName, isNull);
    });

    test('cancelTokens отменяет все токены для email', () {
      const email = 'test@example.com';
      final token1 = service.generateToken(email: email);
      final token2 = service.generateToken(email: email);
      final token3 = service.generateToken(email: 'other@example.com');

      service.cancelTokens(email);

      expect(service.validateToken(token1), isNull);
      expect(service.validateToken(token2), isNull);
      expect(service.validateToken(token3), isNotNull); // другой email не затронут
    });

    test('activeCount возвращает количество активных токенов', () {
      service.generateToken(email: 'test1@example.com');
      service.generateToken(email: 'test2@example.com');

      expect(service.activeCount, equals(2));
    });

    test('activeCount уменьшается после валидации', () {
      final token = service.generateToken(email: 'test@example.com');

      expect(service.activeCount, equals(1));

      service.validateToken(token);

      expect(service.activeCount, equals(0));
    });

    test('cleanup автоматически удаляет истёкшие токены', () async {
      service.generateToken(email: 'test1@example.com');
      service.generateToken(email: 'test2@example.com');

      expect(service.activeCount, equals(2));

      await Future.delayed(const Duration(seconds: 3));

      expect(service.activeCount, equals(0));
    });
  });

  group('MagicLinkData', () {
    test('создаётся с корректными данными', () {
      const data = MagicLinkData(
        email: 'test@example.com',
        newUser: true,
        displayName: 'Test User',
      );

      expect(data.email, equals('test@example.com'));
      expect(data.newUser, isTrue);
      expect(data.displayName, equals('Test User'));
    });

    test('работает без displayName', () {
      const data = MagicLinkData(
        email: 'test@example.com',
        newUser: false,
      );

      expect(data.email, equals('test@example.com'));
      expect(data.newUser, isFalse);
      expect(data.displayName, isNull);
    });
  });
}
