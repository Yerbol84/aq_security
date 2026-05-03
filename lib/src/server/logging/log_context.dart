// pkgs/aq_security/lib/src/server/logging/log_context.dart
//
// Server-only. Context propagation для логирования (request ID, trace ID, user ID).

import 'dart:async';
import 'dart:math';

/// Log context для propagation через async boundaries
final class LogContext {
  const LogContext({
    this.requestId,
    this.userId,
    this.traceId,
    this.spanId,
    this.component,
    this.metadata = const {},
  });

  final String? requestId;
  final String? userId;
  final String? traceId;
  final String? spanId;
  final String? component;
  final Map<String, dynamic> metadata;

  /// Create child context with new span
  LogContext createSpan({String? component}) {
    return LogContext(
      requestId: requestId,
      userId: userId,
      traceId: traceId ?? _generateTraceId(),
      spanId: _generateSpanId(),
      component: component ?? this.component,
      metadata: metadata,
    );
  }

  /// Copy with new values
  LogContext copyWith({
    String? requestId,
    String? userId,
    String? traceId,
    String? spanId,
    String? component,
    Map<String, dynamic>? metadata,
  }) {
    return LogContext(
      requestId: requestId ?? this.requestId,
      userId: userId ?? this.userId,
      traceId: traceId ?? this.traceId,
      spanId: spanId ?? this.spanId,
      component: component ?? this.component,
      metadata: metadata ?? this.metadata,
    );
  }

  /// Generate trace ID
  static String _generateTraceId() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  /// Generate span ID
  static String _generateSpanId() {
    final random = Random.secure();
    final bytes = List<int>.generate(8, (_) => random.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }
}

/// Zone-local storage для LogContext
final _contextKey = #logContext;

/// Get current log context
LogContext? get currentLogContext {
  return Zone.current[_contextKey] as LogContext?;
}

/// Run with log context
R runWithLogContext<R>(LogContext context, R Function() fn) {
  return runZoned(
    fn,
    zoneValues: {_contextKey: context},
  );
}

/// Run async with log context
Future<R> runAsyncWithLogContext<R>(
  LogContext context,
  Future<R> Function() fn,
) {
  return runZoned(
    fn,
    zoneValues: {_contextKey: context},
  );
}

/// Generate request ID
String generateRequestId() {
  final timestamp = DateTime.now().millisecondsSinceEpoch;
  final random = Random.secure().nextInt(0xFFFFFF);
  return 'req-${timestamp.toRadixString(36)}-${random.toRadixString(36)}';
}

/// Generate trace ID (128-bit hex)
String generateTraceId() {
  return LogContext._generateTraceId();
}

/// Generate span ID (64-bit hex)
String generateSpanId() {
  return LogContext._generateSpanId();
}
