// pkgs/aq_security/lib/src/server/monitoring/metrics_middleware.dart
//
// Server-only. Middleware для автоматического сбора метрик HTTP запросов.

import 'package:shelf/shelf.dart';
import 'metrics.dart';

/// Middleware для сбора метрик HTTP запросов
Middleware metricsMiddleware(SecurityMetrics metrics) {
  return (Handler innerHandler) {
    return (Request request) async {
      final startTime = DateTime.now();

      try {
        final response = await innerHandler(request);

        // Record successful request
        final duration = DateTime.now().difference(startTime);
        metrics.recordRequest(
          method: request.method,
          path: _normalizePath(request.url.path),
          statusCode: response.statusCode,
          durationSeconds: duration.inMicroseconds / 1000000.0,
        );

        return response;
      } catch (e) {
        // Record failed request
        final duration = DateTime.now().difference(startTime);
        metrics.recordRequest(
          method: request.method,
          path: _normalizePath(request.url.path),
          statusCode: 500,
          durationSeconds: duration.inMicroseconds / 1000000.0,
        );

        rethrow;
      }
    };
  };
}

/// Normalize path для метрик (заменяем ID на :id)
String _normalizePath(String path) {
  // Remove leading slash
  if (path.startsWith('/')) {
    path = path.substring(1);
  }

  // Split by /
  final parts = path.split('/');

  // Replace UUIDs and numeric IDs with :id
  final normalized = parts.map((part) {
    // UUID pattern
    if (RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$')
        .hasMatch(part)) {
      return ':id';
    }

    // Numeric ID
    if (RegExp(r'^\d+$').hasMatch(part)) {
      return ':id';
    }

    return part;
  }).join('/');

  return '/$normalized';
}
