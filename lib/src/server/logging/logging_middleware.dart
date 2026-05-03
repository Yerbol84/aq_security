// pkgs/aq_security/lib/src/server/logging/logging_middleware.dart
//
// Server-only. Middleware для автоматического логирования HTTP запросов.

import 'package:shelf/shelf.dart';
import 'context_logger.dart';
import 'log_context.dart';

/// Logging middleware
///
/// Автоматически логирует все HTTP запросы и создает LogContext
/// для propagation через весь request lifecycle.
Middleware loggingMiddleware({
  ContextLogger? logger,
  bool logRequestBody = false,
  bool logResponseBody = false,
}) {
  final log = logger ?? contextLogger;

  return (Handler innerHandler) {
    return (Request request) async {
      // Generate request ID and trace ID
      final requestId = generateRequestId();
      final traceId = generateTraceId();

      // Extract user ID from context if available
      final userId = _extractUserId(request);

      // Create log context
      final context = LogContext(
        requestId: requestId,
        userId: userId,
        traceId: traceId,
        component: 'http',
      );

      // Add context to request
      final requestWithContext = request.change(context: {
        ...request.context,
        'log_context': context,
        'request_id': requestId,
        'trace_id': traceId,
      });

      final startTime = DateTime.now();

      try {
        // Log incoming request
        await runAsyncWithLogContext(context, () async {
          log.info(
            'Incoming request',
            context: context,
            metadata: {
              'method': request.method,
              'path': request.url.path,
              'query': request.url.query,
              'ip': _getClientIp(request),
              'user_agent': request.headers['user-agent'],
            },
          );
        });

        // Process request
        final response = await runAsyncWithLogContext(
          context,
          () async => innerHandler(requestWithContext),
        );

        // Calculate duration
        final duration = DateTime.now().difference(startTime);
        final durationMs = duration.inMicroseconds / 1000.0;

        // Log response
        await runAsyncWithLogContext(context, () async {
          log.httpRequest(
            'Request completed',
            context: context,
            method: request.method,
            path: request.url.path,
            statusCode: response.statusCode,
            durationMs: durationMs,
            metadata: {
              'ip': _getClientIp(request),
            },
          );
        });

        // Add tracing headers to response
        return response.change(headers: {
          'X-Request-ID': requestId,
          'X-Trace-ID': traceId,
        });
      } catch (error, stackTrace) {
        // Calculate duration
        final duration = DateTime.now().difference(startTime);
        final durationMs = duration.inMicroseconds / 1000.0;

        // Log error
        await runAsyncWithLogContext(context, () async {
          log.error(
            'Request failed',
            context: context,
            metadata: {
              'method': request.method,
              'path': request.url.path,
              'duration_ms': durationMs,
              'ip': _getClientIp(request),
            },
            error: error,
            stackTrace: stackTrace,
          );
        });

        rethrow;
      }
    };
  };
}

/// Extract user ID from request context
String? _extractUserId(Request request) {
  // Try to get from JWT claims
  final claims = request.context['claims'];
  if (claims is Map<String, dynamic>) {
    return claims['sub'] as String?;
  }

  // Try to get from user object
  final user = request.context['user'];
  if (user is Map<String, dynamic>) {
    return user['id'] as String?;
  }

  return null;
}

/// Get client IP address
String _getClientIp(Request request) {
  // Check X-Forwarded-For
  final forwardedFor = request.headers['x-forwarded-for'];
  if (forwardedFor != null) {
    return forwardedFor.split(',').first.trim();
  }

  // Check X-Real-IP
  final realIp = request.headers['x-real-ip'];
  if (realIp != null) {
    return realIp;
  }

  // Fallback to connection IP
  final connectionInfo = request.context['shelf.io.connection_info'];
  if (connectionInfo != null) {
    try {
      return (connectionInfo as dynamic).remoteAddress.address as String;
    } catch (_) {
      // Ignore
    }
  }

  return 'unknown';
}

/// Get log context from request
LogContext? getLogContextFromRequest(Request request) {
  return request.context['log_context'] as LogContext?;
}

/// Get request ID from request
String? getRequestIdFromRequest(Request request) {
  return request.context['request_id'] as String?;
}

/// Get trace ID from request
String? getTraceIdFromRequest(Request request) {
  return request.context['trace_id'] as String?;
}
