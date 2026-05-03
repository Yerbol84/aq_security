// pkgs/aq_security/lib/src/server/monitoring/metrics_handler.dart
//
// Server-only. Handler для /metrics endpoint (Prometheus scraping).

import 'package:shelf/shelf.dart';
import 'metrics.dart';

/// Handler для /metrics endpoint
///
/// Возвращает метрики в Prometheus exposition format.
/// Используется Prometheus для scraping метрик.
///
/// Example:
/// ```dart
/// final collector = MetricsCollector();
/// final handler = metricsHandler(collector);
/// final response = await handler(request);
/// ```
Handler metricsHandler(MetricsCollector collector) {
  return (Request request) async {
    // Only allow GET requests
    if (request.method != 'GET') {
      return Response(405, body: 'Method Not Allowed');
    }

    // Export metrics in Prometheus format
    final prometheusFormat = collector.toPrometheusFormat();

    return Response.ok(
      prometheusFormat,
      headers: {
        'Content-Type': 'text/plain; version=0.0.4; charset=utf-8',
      },
    );
  };
}

/// Create metrics endpoint with path
///
/// Example:
/// ```dart
/// final collector = MetricsCollector();
/// final handler = createMetricsEndpoint(collector, path: '/metrics');
/// ```
Handler createMetricsEndpoint(
  MetricsCollector collector, {
  String path = '/metrics',
}) {
  return (Request request) async {
    if (request.url.path == path.replaceFirst('/', '')) {
      return metricsHandler(collector)(request);
    }

    return Response.notFound('Not Found');
  };
}
