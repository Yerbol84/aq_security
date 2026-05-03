// pkgs/aq_security/test/server/monitoring/metrics_handler_test.dart

import 'package:test/test.dart';
import 'package:shelf/shelf.dart';
import 'package:aq_security/src/server/monitoring/metrics.dart';
import 'package:aq_security/src/server/monitoring/metrics_handler.dart';

void main() {
  group('metricsHandler', () {
    late MetricsCollector collector;

    setUp(() {
      collector = MetricsCollector();
    });

    test('returns metrics in Prometheus format', () async {
      // Add some metrics
      collector.incrementCounter('test_counter', value: 42);
      collector.setGauge('test_gauge', 100);

      final handler = metricsHandler(collector);
      final request = Request('GET', Uri.parse('http://localhost/metrics'));
      final response = await handler(request);

      expect(response.statusCode, 200);
      expect(response.headers['Content-Type'],
        'text/plain; version=0.0.4; charset=utf-8');

      final body = await response.readAsString();
      expect(body, contains('# HELP test_counter'));
      expect(body, contains('# TYPE test_counter COUNTER'));
      expect(body, contains('test_counter 42'));
      expect(body, contains('# HELP test_gauge'));
      expect(body, contains('# TYPE test_gauge GAUGE'));
      expect(body, contains('test_gauge 100'));
    });

    test('returns 405 for non-GET requests', () async {
      final handler = metricsHandler(collector);
      final request = Request('POST', Uri.parse('http://localhost/metrics'));
      final response = await handler(request);

      expect(response.statusCode, 405);
      expect(await response.readAsString(), 'Method Not Allowed');
    });

    test('returns empty metrics when no metrics collected', () async {
      final handler = metricsHandler(collector);
      final request = Request('GET', Uri.parse('http://localhost/metrics'));
      final response = await handler(request);

      expect(response.statusCode, 200);
      final body = await response.readAsString();
      expect(body.trim(), isEmpty);
    });

    test('includes all metric types', () async {
      collector.incrementCounter('counter_metric');
      collector.setGauge('gauge_metric', 50);
      collector.observeHistogram('histogram_metric', 0.5);

      final handler = metricsHandler(collector);
      final request = Request('GET', Uri.parse('http://localhost/metrics'));
      final response = await handler(request);

      final body = await response.readAsString();
      expect(body, contains('# TYPE counter_metric COUNTER'));
      expect(body, contains('# TYPE gauge_metric GAUGE'));
      expect(body, contains('# TYPE histogram_metric HISTOGRAM'));
    });
  });

  group('createMetricsEndpoint', () {
    late MetricsCollector collector;

    setUp(() {
      collector = MetricsCollector();
    });

    test('serves metrics at specified path', () async {
      collector.incrementCounter('test_counter');

      final handler = createMetricsEndpoint(collector, path: '/metrics');
      final request = Request('GET', Uri.parse('http://localhost/metrics'));
      final response = await handler(request);

      expect(response.statusCode, 200);
      final body = await response.readAsString();
      expect(body, contains('test_counter'));
    });

    test('returns 404 for other paths', () async {
      final handler = createMetricsEndpoint(collector, path: '/metrics');
      final request = Request('GET', Uri.parse('http://localhost/other'));
      final response = await handler(request);

      expect(response.statusCode, 404);
      expect(await response.readAsString(), 'Not Found');
    });

    test('uses default /metrics path', () async {
      collector.incrementCounter('test_counter');

      final handler = createMetricsEndpoint(collector);
      final request = Request('GET', Uri.parse('http://localhost/metrics'));
      final response = await handler(request);

      expect(response.statusCode, 200);
    });

    test('handles custom path', () async {
      collector.incrementCounter('test_counter');

      final handler = createMetricsEndpoint(collector, path: '/custom/metrics');
      final request = Request('GET', Uri.parse('http://localhost/custom/metrics'));
      final response = await handler(request);

      expect(response.statusCode, 200);
      final body = await response.readAsString();
      expect(body, contains('test_counter'));
    });
  });
}
