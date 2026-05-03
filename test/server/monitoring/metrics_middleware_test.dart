// pkgs/aq_security/test/server/monitoring/metrics_middleware_test.dart

import 'package:test/test.dart';
import 'package:shelf/shelf.dart';
import 'package:aq_security/src/server/monitoring/metrics.dart';
import 'package:aq_security/src/server/monitoring/metrics_middleware.dart';

void main() {
  group('metricsMiddleware', () {
    late MetricsCollector collector;
    late SecurityMetrics metrics;

    setUp(() {
      collector = MetricsCollector();
      metrics = SecurityMetrics(collector);
    });

    test('records successful request metrics', () async {
      final handler = const Pipeline()
          .addMiddleware(metricsMiddleware(metrics))
          .addHandler((request) => Response.ok('OK'));

      final request = Request('GET', Uri.parse('http://localhost/api/users'));
      final response = await handler(request);

      expect(response.statusCode, 200);

      // Check counter metric
      final counterMetric = collector.get('http_requests_total',
        labels: {'method': 'GET', 'path': '/api/users', 'status': '200'});
      expect(counterMetric, isNotNull);
      expect((counterMetric!.value as CounterValue).value, 1);

      // Check histogram metric
      final histogramMetric = collector.get('http_request_duration_seconds',
        labels: {'method': 'GET', 'path': '/api/users'});
      expect(histogramMetric, isNotNull);
      expect((histogramMetric!.value as HistogramValue).count, 1);
    });

    test('records failed request metrics', () async {
      final handler = const Pipeline()
          .addMiddleware(metricsMiddleware(metrics))
          .addHandler((request) => throw Exception('Error'));

      final request = Request('POST', Uri.parse('http://localhost/api/data'));

      try {
        await handler(request);
        fail('Should throw exception');
      } catch (e) {
        // Expected
      }

      // Check that 500 error was recorded
      final counterMetric = collector.get('http_requests_total',
        labels: {'method': 'POST', 'path': '/api/data', 'status': '500'});
      expect(counterMetric, isNotNull);
      expect((counterMetric!.value as CounterValue).value, 1);
    });

    test('normalizes path with UUID', () async {
      final handler = const Pipeline()
          .addMiddleware(metricsMiddleware(metrics))
          .addHandler((request) => Response.ok('OK'));

      final request = Request('GET',
        Uri.parse('http://localhost/api/users/550e8400-e29b-41d4-a716-446655440000'));
      await handler(request);

      // Path should be normalized to /api/users/:id
      final counterMetric = collector.get('http_requests_total',
        labels: {'method': 'GET', 'path': '/api/users/:id', 'status': '200'});
      expect(counterMetric, isNotNull);
    });

    test('normalizes path with numeric ID', () async {
      final handler = const Pipeline()
          .addMiddleware(metricsMiddleware(metrics))
          .addHandler((request) => Response.ok('OK'));

      final request = Request('GET',
        Uri.parse('http://localhost/api/users/12345'));
      await handler(request);

      // Path should be normalized to /api/users/:id
      final counterMetric = collector.get('http_requests_total',
        labels: {'method': 'GET', 'path': '/api/users/:id', 'status': '200'});
      expect(counterMetric, isNotNull);
    });

    test('records multiple requests', () async {
      final handler = const Pipeline()
          .addMiddleware(metricsMiddleware(metrics))
          .addHandler((request) => Response.ok('OK'));

      // Make 5 requests
      for (var i = 0; i < 5; i++) {
        final request = Request('GET', Uri.parse('http://localhost/api/test'));
        await handler(request);
      }

      final counterMetric = collector.get('http_requests_total',
        labels: {'method': 'GET', 'path': '/api/test', 'status': '200'});
      expect((counterMetric!.value as CounterValue).value, 5);
    });

    test('records different status codes separately', () async {
      final handler = const Pipeline()
          .addMiddleware(metricsMiddleware(metrics))
          .addHandler((request) {
            if (request.url.path.contains('error')) {
              return Response.internalServerError(body: 'Error');
            }
            return Response.ok('OK');
          });

      await handler(Request('GET', Uri.parse('http://localhost/api/success')));
      await handler(Request('GET', Uri.parse('http://localhost/api/error')));

      final successMetric = collector.get('http_requests_total',
        labels: {'method': 'GET', 'path': '/api/success', 'status': '200'});
      final errorMetric = collector.get('http_requests_total',
        labels: {'method': 'GET', 'path': '/api/error', 'status': '500'});

      expect((successMetric!.value as CounterValue).value, 1);
      expect((errorMetric!.value as CounterValue).value, 1);
    });
  });
}
