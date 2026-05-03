// pkgs/aq_security/lib/src/server/logging/context_logger.dart
//
// Server-only. Logger с автоматическим context propagation.

import 'structured_logger.dart';
import 'log_context.dart';

/// Context-aware logger
final class ContextLogger {
  ContextLogger(this.logger);

  final StructuredLogger logger;

  /// Get context from zone or use provided
  LogContext? _getContext(LogContext? context) {
    return context ?? currentLogContext;
  }

  /// Debug log with context
  void debug(
    String message, {
    LogContext? context,
    String? component,
    Map<String, dynamic> metadata = const {},
  }) {
    final ctx = _getContext(context);
    logger.debug(
      message,
      requestId: ctx?.requestId,
      userId: ctx?.userId,
      traceId: ctx?.traceId,
      spanId: ctx?.spanId,
      component: component ?? ctx?.component,
      metadata: {...?ctx?.metadata, ...metadata},
    );
  }

  /// Info log with context
  void info(
    String message, {
    LogContext? context,
    String? component,
    Map<String, dynamic> metadata = const {},
  }) {
    final ctx = _getContext(context);
    logger.info(
      message,
      requestId: ctx?.requestId,
      userId: ctx?.userId,
      traceId: ctx?.traceId,
      spanId: ctx?.spanId,
      component: component ?? ctx?.component,
      metadata: {...?ctx?.metadata, ...metadata},
    );
  }

  /// Warning log with context
  void warn(
    String message, {
    LogContext? context,
    String? component,
    Map<String, dynamic> metadata = const {},
    Object? error,
  }) {
    final ctx = _getContext(context);
    logger.warn(
      message,
      requestId: ctx?.requestId,
      userId: ctx?.userId,
      traceId: ctx?.traceId,
      spanId: ctx?.spanId,
      component: component ?? ctx?.component,
      metadata: {...?ctx?.metadata, ...metadata},
      error: error,
    );
  }

  /// Error log with context
  void error(
    String message, {
    LogContext? context,
    String? component,
    Map<String, dynamic> metadata = const {},
    Object? error,
    StackTrace? stackTrace,
  }) {
    final ctx = _getContext(context);
    logger.error(
      message,
      requestId: ctx?.requestId,
      userId: ctx?.userId,
      traceId: ctx?.traceId,
      spanId: ctx?.spanId,
      component: component ?? ctx?.component,
      metadata: {...?ctx?.metadata, ...metadata},
      error: error,
      stackTrace: stackTrace,
    );
  }

  /// Fatal log with context
  void fatal(
    String message, {
    LogContext? context,
    String? component,
    Map<String, dynamic> metadata = const {},
    Object? error,
    StackTrace? stackTrace,
  }) {
    final ctx = _getContext(context);
    logger.fatal(
      message,
      requestId: ctx?.requestId,
      userId: ctx?.userId,
      traceId: ctx?.traceId,
      spanId: ctx?.spanId,
      component: component ?? ctx?.component,
      metadata: {...?ctx?.metadata, ...metadata},
      error: error,
      stackTrace: stackTrace,
    );
  }

  /// Log security event
  void securityEvent(
    String event, {
    LogContext? context,
    required String action,
    required bool allowed,
    String? reason,
    Map<String, dynamic> metadata = const {},
  }) {
    final ctx = _getContext(context);
    logger.info(
      event,
      requestId: ctx?.requestId,
      userId: ctx?.userId,
      traceId: ctx?.traceId,
      spanId: ctx?.spanId,
      component: 'security',
      metadata: {
        ...?ctx?.metadata,
        ...metadata,
        'action': action,
        'allowed': allowed,
        if (reason != null) 'reason': reason,
      },
    );
  }

  /// Log auth event
  void authEvent(
    String message, {
    LogContext? context,
    required String method,
    required bool success,
    String? reason,
    Map<String, dynamic> metadata = const {},
  }) {
    final ctx = _getContext(context);
    final level = success ? LogLevel.info : LogLevel.warn;

    logger.log(LogEntry(
      timestamp: DateTime.now(),
      level: level,
      message: message,
      requestId: ctx?.requestId,
      userId: ctx?.userId,
      traceId: ctx?.traceId,
      spanId: ctx?.spanId,
      component: 'auth',
      metadata: {
        ...?ctx?.metadata,
        ...metadata,
        'method': method,
        'success': success,
        if (reason != null) 'reason': reason,
      },
    ));
  }

  /// Log rate limit event
  void rateLimitEvent(
    String message, {
    LogContext? context,
    required String strategy,
    required bool blocked,
    int? remaining,
    int? limit,
    Map<String, dynamic> metadata = const {},
  }) {
    final ctx = _getContext(context);
    final level = blocked ? LogLevel.warn : LogLevel.debug;

    logger.log(LogEntry(
      timestamp: DateTime.now(),
      level: level,
      message: message,
      requestId: ctx?.requestId,
      userId: ctx?.userId,
      traceId: ctx?.traceId,
      spanId: ctx?.spanId,
      component: 'rate_limiting',
      metadata: {
        ...?ctx?.metadata,
        ...metadata,
        'strategy': strategy,
        'blocked': blocked,
        if (remaining != null) 'remaining': remaining,
        if (limit != null) 'limit': limit,
      },
    ));
  }

  /// Log DoS protection event
  void dosProtectionEvent(
    String message, {
    LogContext? context,
    required String type,
    required bool blocked,
    String? reason,
    Map<String, dynamic> metadata = const {},
  }) {
    final ctx = _getContext(context);
    final level = blocked ? LogLevel.warn : LogLevel.debug;

    logger.log(LogEntry(
      timestamp: DateTime.now(),
      level: level,
      message: message,
      requestId: ctx?.requestId,
      userId: ctx?.userId,
      traceId: ctx?.traceId,
      spanId: ctx?.spanId,
      component: 'dos_protection',
      metadata: {
        ...?ctx?.metadata,
        ...metadata,
        'type': type,
        'blocked': blocked,
        if (reason != null) 'reason': reason,
      },
    ));
  }

  /// Log HTTP request
  void httpRequest(
    String message, {
    LogContext? context,
    required String method,
    required String path,
    required int statusCode,
    required double durationMs,
    Map<String, dynamic> metadata = const {},
  }) {
    final ctx = _getContext(context);
    final level = statusCode >= 500 ? LogLevel.error : LogLevel.info;

    logger.log(LogEntry(
      timestamp: DateTime.now(),
      level: level,
      message: message,
      requestId: ctx?.requestId,
      userId: ctx?.userId,
      traceId: ctx?.traceId,
      spanId: ctx?.spanId,
      component: 'http',
      metadata: {
        ...?ctx?.metadata,
        ...metadata,
        'method': method,
        'path': path,
        'status': statusCode,
        'duration_ms': durationMs,
      },
    ));
  }
}

/// Global context logger instance
ContextLogger? _globalContextLogger;

/// Get global context logger
ContextLogger get contextLogger {
  if (_globalContextLogger == null) {
    throw StateError(
      'Context logger not initialized. Call initializeContextLogger() first.',
    );
  }
  return _globalContextLogger!;
}

/// Initialize global context logger
void initializeContextLogger(StructuredLogger logger) {
  _globalContextLogger = ContextLogger(logger);
}

/// Reset context logger (для тестов)
void resetContextLogger() {
  _globalContextLogger = null;
}
