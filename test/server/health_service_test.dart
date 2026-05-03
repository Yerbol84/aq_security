// test/server/health_service_test.dart
//
// Unit tests for HealthService

import 'package:test/test.dart';
import 'package:aq_security/aq_security_server.dart';

void main() {
  group('HealthService', () {
    test('returns healthy when no checks configured', () async {
      final service = HealthService();
      final result = await service.check();

      expect(result.status, 'healthy');
      expect(result.checks['app'], 'ok');
    });

    test('returns healthy when all checks pass', () async {
      final service = HealthService(
        databaseCheck: () async => true,
        redisCheck: () async => true,
      );
      final result = await service.check();

      expect(result.status, 'healthy');
      expect(result.checks['database'], 'ok');
      expect(result.checks['redis'], 'ok');
    });

    test('returns unhealthy when database check fails', () async {
      final service = HealthService(
        databaseCheck: () async => false,
        redisCheck: () async => true,
      );
      final result = await service.check();

      expect(result.status, 'unhealthy');
      expect(result.checks['database'], 'failed');
      expect(result.checks['redis'], 'ok');
    });

    test('returns unhealthy when redis check fails', () async {
      final service = HealthService(
        databaseCheck: () async => true,
        redisCheck: () async => false,
      );
      final result = await service.check();

      expect(result.status, 'unhealthy');
      expect(result.checks['database'], 'ok');
      expect(result.checks['redis'], 'failed');
    });

    test('handles database check exception', () async {
      final service = HealthService(
        databaseCheck: () async => throw Exception('Connection failed'),
        redisCheck: () async => true,
      );
      final result = await service.check();

      expect(result.status, 'unhealthy');
      expect(result.checks['database'], contains('error'));
      expect(result.checks['redis'], 'ok');
    });

    test('handles redis check exception', () async {
      final service = HealthService(
        databaseCheck: () async => true,
        redisCheck: () async => throw Exception('Connection timeout'),
      );
      final result = await service.check();

      expect(result.status, 'unhealthy');
      expect(result.checks['database'], 'ok');
      expect(result.checks['redis'], contains('error'));
    });

    test('includes timestamp in result', () async {
      final service = HealthService();
      final result = await service.check();

      expect(result.timestamp, isNotEmpty);
      expect(DateTime.parse(result.timestamp), isA<DateTime>());
    });

    test('toJson returns correct structure', () async {
      final service = HealthService(
        databaseCheck: () async => true,
      );
      final result = await service.check();
      final json = result.toJson();

      expect(json['status'], 'healthy');
      expect(json['checks'], isA<Map>());
      expect(json['timestamp'], isA<String>());
    });
  });
}
