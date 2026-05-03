// pkgs/aq_security/example/monitoring_example.dart
//
// Пример использования Prometheus метрик в aq_security

import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as io;
import 'package:aq_security/aq_security_server.dart';

void main() async {
  // 1. Создать MetricsCollector
  final collector = MetricsCollector();
  final metrics = SecurityMetrics(collector);

  // 2. Создать rate limiter с метриками
  final rateLimiter = RateLimiter(
    config: RateLimitConfig(
      maxRequests: 100,
      windowSeconds: 60,
    ),
  );

  // 3. Создать connection limiter с метриками
  final connectionLimiter = ConnectionLimiter(
    config: ConnectionLimitConfig(
      maxConnections: 1000,
      maxConnectionsPerIp: 10,
    ),
    metrics: metrics,
  );

  // 4. Создать IP blacklist с метриками
  final ipBlacklist = IpBlacklist(
    config: IpBlacklistConfig(),
    metrics: metrics,
  );

  // 5. Создать request validator
  final requestValidator = RequestValidator(
    config: RequestValidationConfig(
      maxBodySize: 1024 * 1024, // 1MB
      maxHeaderSize: 8192, // 8KB
    ),
  );

  // 6. Создать handler с middleware
  final handler = const Pipeline()
      // Metrics middleware (должен быть первым для точного измерения времени)
      .addMiddleware(metricsMiddleware(metrics))
      // Rate limiting middleware
      .addMiddleware(rateLimitMiddleware(
        limiter: rateLimiter,
        strategy: RateLimitStrategy.byIp,
        metrics: metrics,
      ))
      // DoS protection middleware
      .addMiddleware(dosProtectionMiddleware(
        connectionLimiter: connectionLimiter,
        requestValidator: requestValidator,
        ipBlacklist: ipBlacklist,
      ))
      // Security headers
      .addMiddleware(securityHeadersMiddleware(
        config: const SecurityHeadersConfig(),
      ))
      // Application handler
      .addHandler(_applicationHandler);

  // 6. Создать /metrics endpoint
  final metricsHandler = createMetricsEndpoint(collector);

  // 7. Роутинг
  final router = (Request request) async {
    if (request.url.path == 'metrics') {
      return await metricsHandler(request);
    }
    return await handler(request);
  };

  // 8. Запустить сервер
  final server = await io.serve(router, 'localhost', 8080);
  print('Server running on http://localhost:8080');
  print('Metrics available at http://localhost:8080/metrics');

  // 9. Пример ручной записи метрик
  _recordCustomMetrics(metrics);
}

/// Application handler
Response _applicationHandler(Request request) {
  return Response.ok('Hello, World!');
}

/// Пример ручной записи метрик
void _recordCustomMetrics(SecurityMetrics metrics) {
  // Auth metrics
  metrics.recordAuthAttempt(success: true, method: 'password');
  metrics.recordTokenIssued(type: 'access');
  metrics.recordTokenValidation(valid: true);

  // Rate limiting metrics (автоматически записываются middleware)
  // metrics.recordRateLimitHit(strategy: 'byIp');
  // metrics.recordRateLimitBlocked(strategy: 'byIp');

  // DoS protection metrics (автоматически записываются middleware)
  // metrics.recordConnectionAttempt(allowed: true);
  // metrics.setActiveConnections(50);
  // metrics.recordIpBlocked(reason: 'too_many_requests');

  // Policy metrics
  metrics.recordPolicyEvaluation(allowed: true);

  // Permission metrics
  metrics.recordPermissionCheck(granted: true, resource: 'users');
}

/// Пример Prometheus scrape config
///
/// ```yaml
/// scrape_configs:
///   - job_name: 'aq_security'
///     scrape_interval: 15s
///     static_configs:
///       - targets: ['localhost:8080']
///     metrics_path: '/metrics'
/// ```
///
/// Пример метрик в Prometheus format:
///
/// ```
/// # HELP auth_attempts_total Counter for auth_attempts_total
/// # TYPE auth_attempts_total COUNTER
/// auth_attempts_total{success="true",method="password"} 1
///
/// # HELP tokens_issued_total Counter for tokens_issued_total
/// # TYPE tokens_issued_total COUNTER
/// tokens_issued_total{type="access"} 1
///
/// # HELP rate_limit_hits_total Counter for rate_limit_hits_total
/// # TYPE rate_limit_hits_total COUNTER
/// rate_limit_hits_total{strategy="byIp"} 42
///
/// # HELP rate_limit_blocked_total Counter for rate_limit_blocked_total
/// # TYPE rate_limit_blocked_total COUNTER
/// rate_limit_blocked_total{strategy="byIp"} 5
///
/// # HELP active_connections Gauge for active_connections
/// # TYPE active_connections GAUGE
/// active_connections 50
///
/// # HELP http_requests_total Counter for http_requests_total
/// # TYPE http_requests_total COUNTER
/// http_requests_total{method="GET",path="/api/users",status="200"} 1000
///
/// # HELP http_request_duration_seconds Histogram for http_request_duration_seconds
/// # TYPE http_request_duration_seconds HISTOGRAM
/// http_request_duration_seconds_bucket{method="GET",path="/api/users",le="0.005"} 100
/// http_request_duration_seconds_bucket{method="GET",path="/api/users",le="0.01"} 200
/// http_request_duration_seconds_bucket{method="GET",path="/api/users",le="0.025"} 500
/// http_request_duration_seconds_bucket{method="GET",path="/api/users",le="0.05"} 800
/// http_request_duration_seconds_bucket{method="GET",path="/api/users",le="0.1"} 950
/// http_request_duration_seconds_bucket{method="GET",path="/api/users",le="+Inf"} 1000
/// http_request_duration_seconds_sum{method="GET",path="/api/users"} 45.5
/// http_request_duration_seconds_count{method="GET",path="/api/users"} 1000
/// ```
