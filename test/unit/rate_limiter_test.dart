// test/unit/rate_limiter_test.dart
//
// Тесты для RateLimiter

import 'package:test/test.dart';
import 'package:aq_security/aq_security_server.dart';

void main() {
  group('TokenBucket', () {
    test('позволяет запросы в пределах лимита', () {
      final config = RateLimitConfig(
        maxRequests: 10,
        windowSeconds: 60,
      );
      final bucket = TokenBucket(config: config);

      // Должно разрешить 10 запросов
      for (var i = 0; i < 10; i++) {
        expect(bucket.tryConsume(), isTrue, reason: 'Request $i should be allowed');
      }

      // 11-й запрос должен быть заблокирован
      expect(bucket.tryConsume(), isFalse);
    });

    test('refill токенов со временем', () async {
      final config = RateLimitConfig(
        maxRequests: 10,
        windowSeconds: 10, // 1 token/second
      );
      final bucket = TokenBucket(config: config);

      // Использовать все токены
      for (var i = 0; i < 10; i++) {
        bucket.tryConsume();
      }

      expect(bucket.tryConsume(), isFalse);

      // Подождать 2 секунды
      await Future.delayed(Duration(seconds: 2));

      // Должно быть ~2 новых токена
      expect(bucket.tryConsume(), isTrue);
      expect(bucket.tryConsume(), isTrue);
      expect(bucket.tryConsume(), isFalse);
    });

    test('burst size ограничивает максимальные токены', () {
      final config = RateLimitConfig(
        maxRequests: 100,
        windowSeconds: 60,
        burstSize: 10,
      );
      final bucket = TokenBucket(config: config);

      // Должно разрешить только 10 запросов (burst size)
      for (var i = 0; i < 10; i++) {
        expect(bucket.tryConsume(), isTrue);
      }

      expect(bucket.tryConsume(), isFalse);
    });

    test('availableTokens возвращает правильное количество', () {
      final config = RateLimitConfig(
        maxRequests: 10,
        windowSeconds: 60,
      );
      final bucket = TokenBucket(config: config);

      expect(bucket.availableTokens, equals(10));

      bucket.tryConsume();
      expect(bucket.availableTokens, equals(9));

      bucket.tryConsume(tokens: 3);
      expect(bucket.availableTokens, equals(6));
    });

    test('timeToNextToken возвращает правильное время', () {
      final config = RateLimitConfig(
        maxRequests: 10,
        windowSeconds: 10, // 1 token/second
      );
      final bucket = TokenBucket(config: config);

      // Использовать все токены
      for (var i = 0; i < 10; i++) {
        bucket.tryConsume();
      }

      // Должно быть ~1 секунда до следующего токена
      final timeToNext = bucket.timeToNextToken;
      expect(timeToNext, greaterThan(0));
      expect(timeToNext, lessThanOrEqualTo(1));
    });
  });

  group('RateLimiter', () {
    test('checkLimit блокирует после превышения лимита', () {
      final config = RateLimitConfig(
        maxRequests: 5,
        windowSeconds: 60,
      );
      final limiter = RateLimiter(config: config);

      // Первые 5 запросов разрешены
      for (var i = 0; i < 5; i++) {
        final result = limiter.checkLimit('user1');
        expect(result.allowed, isTrue);
        expect(result.remaining, equals(4 - i));
      }

      // 6-й запрос заблокирован
      final result = limiter.checkLimit('user1');
      expect(result.allowed, isFalse);
      expect(result.remaining, equals(0));
      expect(result.retryAfter, isNotNull);
    });

    test('разные ключи имеют независимые лимиты', () {
      final config = RateLimitConfig(
        maxRequests: 5,
        windowSeconds: 60,
      );
      final limiter = RateLimiter(config: config);

      // User1 использует все токены
      for (var i = 0; i < 5; i++) {
        limiter.checkLimit('user1');
      }

      final result1 = limiter.checkLimit('user1');
      expect(result1.allowed, isFalse);

      // User2 всё ещё может делать запросы
      final result2 = limiter.checkLimit('user2');
      expect(result2.allowed, isTrue);
    });

    test('getStatus возвращает текущий статус', () {
      final config = RateLimitConfig(
        maxRequests: 10,
        windowSeconds: 60,
      );
      final limiter = RateLimiter(config: config);

      // Новый ключ
      final status1 = limiter.getStatus('user1');
      expect(status1.allowed, isTrue);
      expect(status1.remaining, equals(10));

      // После использования
      limiter.checkLimit('user1');
      limiter.checkLimit('user1');

      final status2 = limiter.getStatus('user1');
      expect(status2.remaining, equals(8));
    });

    test('clear удаляет bucket для ключа', () {
      final config = RateLimitConfig(
        maxRequests: 5,
        windowSeconds: 60,
      );
      final limiter = RateLimiter(config: config);

      // Использовать все токены
      for (var i = 0; i < 5; i++) {
        limiter.checkLimit('user1');
      }

      expect(limiter.checkLimit('user1').allowed, isFalse);

      // Clear bucket
      limiter.clear('user1');

      // Теперь снова разрешено
      expect(limiter.checkLimit('user1').allowed, isTrue);
    });

    test('clearAll удаляет все buckets', () {
      final config = RateLimitConfig(
        maxRequests: 5,
        windowSeconds: 60,
      );
      final limiter = RateLimiter(config: config);

      // Использовать токены для нескольких пользователей
      for (var i = 0; i < 5; i++) {
        limiter.checkLimit('user1');
        limiter.checkLimit('user2');
      }

      expect(limiter.checkLimit('user1').allowed, isFalse);
      expect(limiter.checkLimit('user2').allowed, isFalse);

      // Clear all
      limiter.clearAll();

      // Теперь оба снова разрешены
      expect(limiter.checkLimit('user1').allowed, isTrue);
      expect(limiter.checkLimit('user2').allowed, isTrue);
    });

    test('headers содержат правильные значения', () {
      final config = RateLimitConfig(
        maxRequests: 10,
        windowSeconds: 60,
      );
      final limiter = RateLimiter(config: config);

      final result = limiter.checkLimit('user1');

      expect(result.headers['X-RateLimit-Limit'], equals('10'));
      expect(result.headers['X-RateLimit-Remaining'], equals('9'));
      expect(result.headers['X-RateLimit-Reset'], isNotNull);
      expect(result.headers['Retry-After'], isNull);
    });

    test('headers содержат Retry-After при блокировке', () {
      final config = RateLimitConfig(
        maxRequests: 5,
        windowSeconds: 60,
      );
      final limiter = RateLimiter(config: config);

      // Использовать все токены
      for (var i = 0; i < 5; i++) {
        limiter.checkLimit('user1');
      }

      final result = limiter.checkLimit('user1');
      expect(result.headers['Retry-After'], isNotNull);
    });

    test('cleanup удаляет старые buckets', () async {
      final config = RateLimitConfig(
        maxRequests: 10,
        windowSeconds: 2,
      );
      final limiter = RateLimiter(
        config: config,
        cleanupIntervalSeconds: 1,
      );

      // Создать bucket
      limiter.checkLimit('user1');

      // Подождать > 2 * windowSeconds
      await Future.delayed(Duration(seconds: 5));

      // Bucket должен быть удалён
      final status = limiter.getStatus('user1');
      expect(status.remaining, equals(10)); // Новый bucket

      limiter.dispose();
    });
  });

  group('RateLimitResult', () {
    test('headers форматируются правильно', () {
      final result = RateLimitResult(
        allowed: true,
        limit: 100,
        remaining: 50,
        resetAt: 1234567890,
        retryAfter: null,
      );

      expect(result.headers['X-RateLimit-Limit'], equals('100'));
      expect(result.headers['X-RateLimit-Remaining'], equals('50'));
      expect(result.headers['X-RateLimit-Reset'], equals('1234567890'));
      expect(result.headers.containsKey('Retry-After'), isFalse);
    });

    test('headers включают Retry-After если есть', () {
      final result = RateLimitResult(
        allowed: false,
        limit: 100,
        remaining: 0,
        resetAt: 1234567890,
        retryAfter: 60,
      );

      expect(result.headers['Retry-After'], equals('60'));
    });
  });
}
