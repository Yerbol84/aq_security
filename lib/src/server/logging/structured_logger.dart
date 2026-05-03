// pkgs/aq_security/lib/src/server/logging/structured_logger.dart
//
// Server-only. Structured logging с JSON форматом для production.

import 'dart:convert';
import 'dart:io';

/// Log level
enum LogLevel {
  debug,
  info,
  warn,
  error,
  fatal;

  int get priority {
    switch (this) {
      case LogLevel.debug:
        return 0;
      case LogLevel.info:
        return 1;
      case LogLevel.warn:
        return 2;
      case LogLevel.error:
        return 3;
      case LogLevel.fatal:
        return 4;
    }
  }
}

/// Log entry
final class LogEntry {
  LogEntry({
    required this.timestamp,
    required this.level,
    required this.message,
    this.requestId,
    this.userId,
    this.traceId,
    this.spanId,
    this.component,
    this.metadata = const {},
    this.error,
    this.stackTrace,
  });

  final DateTime timestamp;
  final LogLevel level;
  final String message;
  final String? requestId;
  final String? userId;
  final String? traceId;
  final String? spanId;
  final String? component;
  final Map<String, dynamic> metadata;
  final Object? error;
  final StackTrace? stackTrace;

  /// Convert to JSON
  Map<String, dynamic> toJson() {
    return {
      'timestamp': timestamp.toUtc().toIso8601String(),
      'level': level.name,
      'message': message,
      if (requestId != null) 'request_id': requestId,
      if (userId != null) 'user_id': userId,
      if (traceId != null) 'trace_id': traceId,
      if (spanId != null) 'span_id': spanId,
      if (component != null) 'component': component,
      if (metadata.isNotEmpty) ...metadata,
      if (error != null) 'error': error.toString(),
      if (stackTrace != null) 'stack_trace': stackTrace.toString(),
    };
  }

  /// Convert to JSON string
  String toJsonString() => jsonEncode(toJson());
}

/// Structured logger
final class StructuredLogger {
  StructuredLogger({
    this.minLevel = LogLevel.info,
    this.output = _defaultOutput,
    this.includeStackTrace = true,
  });

  final LogLevel minLevel;
  final void Function(String) output;
  final bool includeStackTrace;

  /// Log entry
  void log(LogEntry entry) {
    if (entry.level.priority < minLevel.priority) {
      return;
    }

    output(entry.toJsonString());
  }

  /// Debug log
  void debug(
    String message, {
    String? requestId,
    String? userId,
    String? traceId,
    String? spanId,
    String? component,
    Map<String, dynamic> metadata = const {},
  }) {
    log(LogEntry(
      timestamp: DateTime.now(),
      level: LogLevel.debug,
      message: message,
      requestId: requestId,
      userId: userId,
      traceId: traceId,
      spanId: spanId,
      component: component,
      metadata: metadata,
    ));
  }

  /// Info log
  void info(
    String message, {
    String? requestId,
    String? userId,
    String? traceId,
    String? spanId,
    String? component,
    Map<String, dynamic> metadata = const {},
  }) {
    log(LogEntry(
      timestamp: DateTime.now(),
      level: LogLevel.info,
      message: message,
      requestId: requestId,
      userId: userId,
      traceId: traceId,
      spanId: spanId,
      component: component,
      metadata: metadata,
    ));
  }

  /// Warning log
  void warn(
    String message, {
    String? requestId,
    String? userId,
    String? traceId,
    String? spanId,
    String? component,
    Map<String, dynamic> metadata = const {},
    Object? error,
  }) {
    log(LogEntry(
      timestamp: DateTime.now(),
      level: LogLevel.warn,
      message: message,
      requestId: requestId,
      userId: userId,
      traceId: traceId,
      spanId: spanId,
      component: component,
      metadata: metadata,
      error: error,
    ));
  }

  /// Error log
  void error(
    String message, {
    String? requestId,
    String? userId,
    String? traceId,
    String? spanId,
    String? component,
    Map<String, dynamic> metadata = const {},
    Object? error,
    StackTrace? stackTrace,
  }) {
    log(LogEntry(
      timestamp: DateTime.now(),
      level: LogLevel.error,
      message: message,
      requestId: requestId,
      userId: userId,
      traceId: traceId,
      spanId: spanId,
      component: component,
      metadata: metadata,
      error: error,
      stackTrace: includeStackTrace ? stackTrace : null,
    ));
  }

  /// Fatal log
  void fatal(
    String message, {
    String? requestId,
    String? userId,
    String? traceId,
    String? spanId,
    String? component,
    Map<String, dynamic> metadata = const {},
    Object? error,
    StackTrace? stackTrace,
  }) {
    log(LogEntry(
      timestamp: DateTime.now(),
      level: LogLevel.fatal,
      message: message,
      requestId: requestId,
      userId: userId,
      traceId: traceId,
      spanId: spanId,
      component: component,
      metadata: metadata,
      error: error,
      stackTrace: includeStackTrace ? stackTrace : null,
    ));
  }

  /// Default output (stdout)
  static void _defaultOutput(String line) {
    stdout.writeln(line);
  }
}

/// Global logger instance
StructuredLogger? _globalLogger;

/// Get global logger
StructuredLogger get logger {
  if (_globalLogger == null) {
    throw StateError(
      'Logger not initialized. Call initializeLogger() first.',
    );
  }
  return _globalLogger!;
}

/// Initialize global logger
void initializeLogger({
  LogLevel minLevel = LogLevel.info,
  void Function(String)? output,
  bool includeStackTrace = true,
}) {
  _globalLogger = StructuredLogger(
    minLevel: minLevel,
    output: output ?? StructuredLogger._defaultOutput,
    includeStackTrace: includeStackTrace,
  );
}

/// Reset logger (для тестов)
void resetLogger() {
  _globalLogger = null;
}
