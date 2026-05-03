// pkgs/aq_security/example/logging_example.dart
//
// Пример использования structured logging и tracing в aq_security

import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as io;
import 'package:aq_security/aq_security_server.dart';

void main() async {
  // 1. Инициализировать logger
  initializeLogger(
    minLevel: LogLevel.info,
    includeStackTrace: true,
  );

  // 2. Инициализировать context logger
  initializeContextLogger(logger);

  // 3. Инициализировать security logger
  initializeSecurityLogger(contextLogger);

  // 4. Создать metrics (опционально)
  final collector = MetricsCollector();
  final metrics = SecurityMetrics(collector);

  // 5. Создать handler с logging middleware
  final handler = const Pipeline()
      // Logging middleware (должен быть первым)
      .addMiddleware(loggingMiddleware())
      // Metrics middleware
      .addMiddleware(metricsMiddleware(metrics))
      // Application handler
      .addHandler(_applicationHandler);

  // 6. Запустить сервер
  final server = await io.serve(handler, 'localhost', 8080);
  print('Server running on http://localhost:8080');
  print('Logs are written to stdout in JSON format');
}

/// Application handler
Response _applicationHandler(Request request) {
  // Context автоматически propagates через zone
  final context = getLogContextFromRequest(request);

  // Логирование с context
  contextLogger.info(
    'Processing request',
    context: context,
    metadata: {'custom_field': 'value'},
  );

  // Security logging
  securityLogger.logAuthAttempt(
    context: context,
    method: 'password',
    success: true,
    userId: 'user-123',
  );

  return Response.ok('Hello, World!');
}

/// Пример логов в JSON формате:
///
/// ```json
/// {
///   "timestamp": "2026-04-10T18:30:00.000Z",
///   "level": "info",
///   "message": "Incoming request",
///   "request_id": "req-1a2b3c",
///   "trace_id": "a1b2c3d4e5f6g7h8i9j0k1l2m3n4o5p6",
///   "component": "http",
///   "method": "GET",
///   "path": "/api/users",
///   "query": "limit=10",
///   "ip": "192.168.1.1",
///   "user_agent": "Mozilla/5.0..."
/// }
///
/// {
///   "timestamp": "2026-04-10T18:30:00.050Z",
///   "level": "info",
///   "message": "Request completed",
///   "request_id": "req-1a2b3c",
///   "trace_id": "a1b2c3d4e5f6g7h8i9j0k1l2m3n4o5p6",
///   "component": "http",
///   "method": "GET",
///   "path": "/api/users",
///   "status": 200,
///   "duration_ms": 45.5,
///   "ip": "192.168.1.1"
/// }
/// ```

/// Пример использования в async функциях:
Future<void> exampleAsyncFunction() async {
  // Создать context
  final context = LogContext(
    requestId: generateRequestId(),
    traceId: generateTraceId(),
    userId: 'user-123',
    component: 'background_job',
  );

  // Запустить с context
  await runAsyncWithLogContext(context, () async {
    contextLogger.info('Starting background job');

    // Context автоматически propagates
    await _doWork();

    contextLogger.info('Background job completed');
  });
}

Future<void> _doWork() async {
  // Context доступен через zone
  contextLogger.debug('Doing work...');
  await Future.delayed(Duration(seconds: 1));
}

/// Пример создания spans для трейсинга:
Future<void> exampleWithSpans() async {
  final context = LogContext(
    requestId: generateRequestId(),
    traceId: generateTraceId(),
  );

  await runAsyncWithLogContext(context, () async {
    contextLogger.info('Parent operation started');

    // Создать child span
    final childContext = context.createSpan(component: 'database');
    await runAsyncWithLogContext(childContext, () async {
      contextLogger.info('Database query started');
      await Future.delayed(Duration(milliseconds: 100));
      contextLogger.info('Database query completed');
    });

    // Создать другой child span
    final anotherContext = context.createSpan(component: 'cache');
    await runAsyncWithLogContext(anotherContext, () async {
      contextLogger.info('Cache operation started');
      await Future.delayed(Duration(milliseconds: 50));
      contextLogger.info('Cache operation completed');
    });

    contextLogger.info('Parent operation completed');
  });
}

/// Пример security logging:
void exampleSecurityLogging() {
  final context = LogContext(
    requestId: generateRequestId(),
    traceId: generateTraceId(),
    userId: 'user-123',
  );

  // Auth events
  securityLogger.logAuthAttempt(
    context: context,
    method: 'password',
    success: true,
    userId: 'user-123',
    ip: '192.168.1.1',
  );

  // Rate limiting
  securityLogger.logRateLimitBlocked(
    context: context,
    strategy: 'byIp',
    key: 'ip:192.168.1.1',
    limit: 100,
    retryAfter: 60,
  );

  // DoS protection
  securityLogger.logIpBlocked(
    context: context,
    ip: '192.168.1.1',
    reason: 'too_many_requests',
    durationSeconds: 3600,
  );

  // Suspicious activity
  securityLogger.logSuspiciousActivity(
    context: context,
    activity: 'multiple_failed_logins',
    reason: '10 failed login attempts in 5 minutes',
    ip: '192.168.1.1',
    userId: 'user-123',
  );

  // Security incident
  securityLogger.logSecurityIncident(
    context: context,
    incident: 'sql_injection_attempt',
    severity: 'high',
    ip: '192.168.1.1',
    details: {
      'query': 'SELECT * FROM users WHERE id = 1 OR 1=1',
      'blocked': true,
    },
  );
}

/// Пример error logging:
void exampleErrorLogging() {
  final context = LogContext(
    requestId: generateRequestId(),
    traceId: generateTraceId(),
  );

  try {
    throw Exception('Something went wrong');
  } catch (error, stackTrace) {
    contextLogger.error(
      'Operation failed',
      context: context,
      component: 'payment',
      error: error,
      stackTrace: stackTrace,
      metadata: {
        'user_id': 'user-123',
        'amount': 100.0,
        'currency': 'USD',
      },
    );
  }
}

/// Пример log aggregation в Docker/Kubernetes:
///
/// Логи пишутся в stdout в JSON формате, что позволяет:
/// - Собирать через Docker logs
/// - Агрегировать через Fluentd/Fluent Bit
/// - Отправлять в Elasticsearch/Loki
/// - Анализировать в Kibana/Grafana
///
/// Docker Compose example:
/// ```yaml
/// services:
///   app:
///     image: my-app
///     logging:
///       driver: "json-file"
///       options:
///         max-size: "10m"
///         max-file: "3"
///
///   fluentd:
///     image: fluent/fluentd
///     volumes:
///       - ./fluentd.conf:/fluentd/etc/fluent.conf
///     depends_on:
///       - elasticsearch
/// ```
///
/// Kubernetes example:
/// ```yaml
/// apiVersion: v1
/// kind: Pod
/// metadata:
///   name: my-app
/// spec:
///   containers:
///   - name: app
///     image: my-app
///     # Logs go to stdout, collected by kubelet
/// ```
