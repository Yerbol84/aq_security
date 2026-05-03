// test/unit/dos_protection_test.dart
//
// Тесты для DoS protection

import 'package:test/test.dart';
import 'package:shelf/shelf.dart';
import 'package:aq_security/aq_security_server.dart';

void main() {
  group('ConnectionLimiter', () {
    test('позволяет соединения в пределах лимита', () {
      final config = ConnectionLimitConfig(
        maxConnections: 10,
        maxConnectionsPerIp: 5,
      );
      final limiter = ConnectionLimiter(config: config);

      // Должно разрешить 10 соединений
      for (var i = 0; i < 10; i++) {
        final result = limiter.tryConnect(
          connectionId: 'conn$i',
          ip: '192.168.1.$i',
        );
        expect(result.allowed, isTrue);
      }

      // 11-е соединение должно быть заблокировано
      final result = limiter.tryConnect(
        connectionId: 'conn11',
        ip: '192.168.1.11',
      );
      expect(result.allowed, isFalse);
      expect(result.reason, contains('Global connection limit'));

      limiter.dispose();
    });

    test('ограничивает соединения с одного IP', () {
      final config = ConnectionLimitConfig(
        maxConnections: 100,
        maxConnectionsPerIp: 3,
      );
      final limiter = ConnectionLimiter(config: config);

      // Должно разрешить 3 соединения с одного IP
      for (var i = 0; i < 3; i++) {
        final result = limiter.tryConnect(
          connectionId: 'conn$i',
          ip: '192.168.1.1',
        );
        expect(result.allowed, isTrue);
      }

      // 4-е соединение с того же IP должно быть заблокировано
      final result = limiter.tryConnect(
        connectionId: 'conn4',
        ip: '192.168.1.1',
      );
      expect(result.allowed, isFalse);
      expect(result.reason, contains('Per-IP connection limit'));

      limiter.dispose();
    });

    test('disconnect освобождает слот', () {
      final config = ConnectionLimitConfig(
        maxConnections: 2,
        maxConnectionsPerIp: 2,
      );
      final limiter = ConnectionLimiter(config: config);

      // Заполнить лимит
      limiter.tryConnect(connectionId: 'conn1', ip: '192.168.1.1');
      limiter.tryConnect(connectionId: 'conn2', ip: '192.168.1.2');

      // Должно быть заблокировано
      var result = limiter.tryConnect(connectionId: 'conn3', ip: '192.168.1.3');
      expect(result.allowed, isFalse);

      // Отключить одно соединение
      limiter.disconnect('conn1');

      // Теперь должно быть разрешено
      result = limiter.tryConnect(connectionId: 'conn3', ip: '192.168.1.3');
      expect(result.allowed, isTrue);

      limiter.dispose();
    });

    test('getStats возвращает правильную статистику', () {
      final config = ConnectionLimitConfig(
        maxConnections: 10,
        maxConnectionsPerIp: 5,
      );
      final limiter = ConnectionLimiter(config: config);

      limiter.tryConnect(connectionId: 'conn1', ip: '192.168.1.1');
      limiter.tryConnect(connectionId: 'conn2', ip: '192.168.1.1');
      limiter.tryConnect(connectionId: 'conn3', ip: '192.168.1.2');

      final stats = limiter.getStats();
      expect(stats.totalConnections, equals(3));
      expect(stats.connectionsByIp['192.168.1.1'], equals(2));
      expect(stats.connectionsByIp['192.168.1.2'], equals(1));

      limiter.dispose();
    });
  });

  group('RequestValidator', () {
    test('валидирует правильный запрос', () {
      final config = RequestValidationConfig();
      final validator = RequestValidator(config: config);

      final request = Request(
        'GET',
        Uri.parse('http://localhost/api/users'),
        headers: {'content-type': 'application/json'},
      );

      final result = validator.validate(request);
      expect(result.valid, isTrue);
    });

    test('блокирует неразрешённый метод', () {
      final config = RequestValidationConfig(
        allowedMethods: ['GET', 'POST'],
      );
      final validator = RequestValidator(config: config);

      final request = Request(
        'DELETE',
        Uri.parse('http://localhost/api/users/1'),
      );

      final result = validator.validate(request);
      expect(result.valid, isFalse);
      expect(result.statusCode, equals(405));
    });

    test('блокирует слишком длинный URL', () {
      final config = RequestValidationConfig(
        maxUrlLength: 100,
      );
      final validator = RequestValidator(config: config);

      final longUrl = 'http://localhost/api/' + 'a' * 200;
      final request = Request('GET', Uri.parse(longUrl));

      final result = validator.validate(request);
      expect(result.valid, isFalse);
      expect(result.statusCode, equals(414));
    });

    test('требует Content-Type для POST', () {
      final config = RequestValidationConfig(
        requireContentType: true,
      );
      final validator = RequestValidator(config: config);

      final request = Request(
        'POST',
        Uri.parse('http://localhost/api/users'),
      );

      final result = validator.validate(request);
      expect(result.valid, isFalse);
      expect(result.statusCode, equals(400));
    });

    test('блокирует слишком большой Content-Length', () {
      final config = RequestValidationConfig(
        maxBodySize: 1024,
      );
      final validator = RequestValidator(config: config);

      final request = Request(
        'POST',
        Uri.parse('http://localhost/api/users'),
        headers: {
          'content-type': 'application/json',
          'content-length': '2048',
        },
      );

      final result = validator.validate(request);
      expect(result.valid, isFalse);
      expect(result.statusCode, equals(413));
    });
  });

  group('IpBlacklist', () {
    test('блокирует IP', () {
      final config = IpBlacklistConfig();
      final blacklist = IpBlacklist(config: config);

      blacklist.block(
        ip: '192.168.1.1',
        reason: 'Too many failed attempts',
      );

      expect(blacklist.isBlocked('192.168.1.1'), isTrue);
      expect(blacklist.isBlocked('192.168.1.2'), isFalse);

      blacklist.dispose();
    });

    test('разблокирует IP', () {
      final config = IpBlacklistConfig();
      final blacklist = IpBlacklist(config: config);

      blacklist.block(
        ip: '192.168.1.1',
        reason: 'Test',
      );

      expect(blacklist.isBlocked('192.168.1.1'), isTrue);

      blacklist.unblock('192.168.1.1');

      expect(blacklist.isBlocked('192.168.1.1'), isFalse);

      blacklist.dispose();
    });

    test('автоматически разблокирует после истечения', () async {
      final config = IpBlacklistConfig();
      final blacklist = IpBlacklist(config: config);

      blacklist.block(
        ip: '192.168.1.1',
        reason: 'Test',
        durationSeconds: 1,
      );

      expect(blacklist.isBlocked('192.168.1.1'), isTrue);

      // Подождать истечения
      await Future.delayed(Duration(seconds: 2));

      expect(blacklist.isBlocked('192.168.1.1'), isFalse);

      blacklist.dispose();
    });

    test('permanent block не истекает', () async {
      final config = IpBlacklistConfig();
      final blacklist = IpBlacklist(config: config);

      blacklist.blockPermanent(
        ip: '192.168.1.1',
        reason: 'Malicious',
      );

      expect(blacklist.isBlocked('192.168.1.1'), isTrue);

      await Future.delayed(Duration(seconds: 2));

      expect(blacklist.isBlocked('192.168.1.1'), isTrue);

      blacklist.dispose();
    });
  });

  group('ThreatDetector', () {
    test('блокирует IP после превышения лимита', () {
      final blacklist = IpBlacklist(config: IpBlacklistConfig());
      final detector = ThreatDetector(
        blacklist: blacklist,
        maxFailedAttempts: 3,
        failedAttemptsWindow: 60,
      );

      // Зарегистрировать 3 failed attempts
      for (var i = 0; i < 3; i++) {
        detector.recordFailedAttempt('192.168.1.1', 'Invalid password');
      }

      // IP должен быть заблокирован
      expect(blacklist.isBlocked('192.168.1.1'), isTrue);

      blacklist.dispose();
    });

    test('не блокирует если attempts в пределах лимита', () {
      final blacklist = IpBlacklist(config: IpBlacklistConfig());
      final detector = ThreatDetector(
        blacklist: blacklist,
        maxFailedAttempts: 5,
        failedAttemptsWindow: 60,
      );

      // Зарегистрировать 3 failed attempts
      for (var i = 0; i < 3; i++) {
        detector.recordFailedAttempt('192.168.1.1', 'Invalid password');
      }

      // IP не должен быть заблокирован
      expect(blacklist.isBlocked('192.168.1.1'), isFalse);

      blacklist.dispose();
    });

    test('getAttempts возвращает правильное количество', () {
      final blacklist = IpBlacklist(config: IpBlacklistConfig());
      final detector = ThreatDetector(
        blacklist: blacklist,
        maxFailedAttempts: 10,
      );

      detector.recordFailedAttempt('192.168.1.1', 'Test');
      detector.recordFailedAttempt('192.168.1.1', 'Test');

      expect(detector.getAttempts('192.168.1.1'), equals(2));

      blacklist.dispose();
    });
  });
}
