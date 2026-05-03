// pkgs/aq_security/test/server/logging/context_logger_test.dart

import 'dart:convert';
import 'package:test/test.dart';
import 'package:aq_security/src/server/logging/structured_logger.dart';
import 'package:aq_security/src/server/logging/context_logger.dart';
import 'package:aq_security/src/server/logging/log_context.dart';

void main() {
  group('ContextLogger', () {
    late List<String> logOutput;
    late StructuredLogger structuredLogger;
    late ContextLogger contextLogger;

    setUp(() {
      logOutput = [];
      structuredLogger = StructuredLogger(
        minLevel: LogLevel.debug,
        output: (line) => logOutput.add(line),
      );
      contextLogger = ContextLogger(structuredLogger);
    });

    test('logs with explicit context', () {
      final context = LogContext(
        requestId: 'req-123',
        userId: 'user-456',
        traceId: 'trace-789',
      );

      contextLogger.info('Test message', context: context);

      expect(logOutput.length, 1);
      final log = jsonDecode(logOutput[0]) as Map<String, dynamic>;
      expect(log['message'], 'Test message');
      expect(log['request_id'], 'req-123');
      expect(log['user_id'], 'user-456');
      expect(log['trace_id'], 'trace-789');
    });

    test('logs with zone context', () {
      final context = LogContext(requestId: 'req-123');

      runWithLogContext(context, () {
        contextLogger.info('Test message');
      });

      expect(logOutput.length, 1);
      final log = jsonDecode(logOutput[0]) as Map<String, dynamic>;
      expect(log['request_id'], 'req-123');
    });

    test('explicit context overrides zone context', () {
      final zoneContext = LogContext(requestId: 'req-zone');
      final explicitContext = LogContext(requestId: 'req-explicit');

      runWithLogContext(zoneContext, () {
        contextLogger.info('Test message', context: explicitContext);
      });

      expect(logOutput.length, 1);
      final log = jsonDecode(logOutput[0]) as Map<String, dynamic>;
      expect(log['request_id'], 'req-explicit');
    });

    test('merges metadata from context and call', () {
      final context = LogContext(
        requestId: 'req-123',
        metadata: {'ctx_key': 'ctx_value'},
      );

      contextLogger.info(
        'Test message',
        context: context,
        metadata: {'call_key': 'call_value'},
      );

      expect(logOutput.length, 1);
      final log = jsonDecode(logOutput[0]) as Map<String, dynamic>;
      expect(log['ctx_key'], 'ctx_value');
      expect(log['call_key'], 'call_value');
    });

    test('securityEvent logs with security component', () {
      contextLogger.securityEvent(
        'Access denied',
        action: 'read',
        allowed: false,
        reason: 'insufficient permissions',
      );

      expect(logOutput.length, 1);
      final log = jsonDecode(logOutput[0]) as Map<String, dynamic>;
      expect(log['component'], 'security');
      expect(log['action'], 'read');
      expect(log['allowed'], false);
      expect(log['reason'], 'insufficient permissions');
    });

    test('authEvent logs success as info', () {
      contextLogger.authEvent(
        'Login successful',
        method: 'password',
        success: true,
      );

      expect(logOutput.length, 1);
      final log = jsonDecode(logOutput[0]) as Map<String, dynamic>;
      expect(log['level'], 'info');
      expect(log['component'], 'auth');
      expect(log['method'], 'password');
      expect(log['success'], true);
    });

    test('authEvent logs failure as warn', () {
      contextLogger.authEvent(
        'Login failed',
        method: 'password',
        success: false,
        reason: 'invalid credentials',
      );

      expect(logOutput.length, 1);
      final log = jsonDecode(logOutput[0]) as Map<String, dynamic>;
      expect(log['level'], 'warn');
      expect(log['success'], false);
      expect(log['reason'], 'invalid credentials');
    });

    test('rateLimitEvent logs blocked as warn', () {
      contextLogger.rateLimitEvent(
        'Rate limit exceeded',
        strategy: 'byIp',
        blocked: true,
        limit: 100,
      );

      expect(logOutput.length, 1);
      final log = jsonDecode(logOutput[0]) as Map<String, dynamic>;
      expect(log['level'], 'warn');
      expect(log['component'], 'rate_limiting');
      expect(log['blocked'], true);
    });

    test('rateLimitEvent logs allowed as debug', () {
      contextLogger.rateLimitEvent(
        'Rate limit checked',
        strategy: 'byIp',
        blocked: false,
        remaining: 50,
        limit: 100,
      );

      expect(logOutput.length, 1);
      final log = jsonDecode(logOutput[0]) as Map<String, dynamic>;
      expect(log['level'], 'debug');
      expect(log['blocked'], false);
      expect(log['remaining'], 50);
    });

    test('dosProtectionEvent logs with dos_protection component', () {
      contextLogger.dosProtectionEvent(
        'Connection rejected',
        type: 'connection_limit',
        blocked: true,
        reason: 'max connections reached',
      );

      expect(logOutput.length, 1);
      final log = jsonDecode(logOutput[0]) as Map<String, dynamic>;
      expect(log['component'], 'dos_protection');
      expect(log['type'], 'connection_limit');
      expect(log['blocked'], true);
    });

    test('httpRequest logs 5xx as error', () {
      contextLogger.httpRequest(
        'Request failed',
        method: 'GET',
        path: '/api/test',
        statusCode: 500,
        durationMs: 123.45,
      );

      expect(logOutput.length, 1);
      final log = jsonDecode(logOutput[0]) as Map<String, dynamic>;
      expect(log['level'], 'error');
      expect(log['component'], 'http');
      expect(log['status'], 500);
    });

    test('httpRequest logs 2xx as info', () {
      contextLogger.httpRequest(
        'Request completed',
        method: 'GET',
        path: '/api/test',
        statusCode: 200,
        durationMs: 50.0,
      );

      expect(logOutput.length, 1);
      final log = jsonDecode(logOutput[0]) as Map<String, dynamic>;
      expect(log['level'], 'info');
      expect(log['status'], 200);
      expect(log['duration_ms'], 50.0);
    });
  });

  group('Global context logger', () {
    setUp(() {
      resetContextLogger();
    });

    tearDown(() {
      resetContextLogger();
    });

    test('throws if not initialized', () {
      expect(() => contextLogger, throwsStateError);
    });

    test('can be initialized', () {
      final logOutput = <String>[];
      final structuredLogger = StructuredLogger(
        minLevel: LogLevel.info,
        output: (line) => logOutput.add(line),
      );

      initializeContextLogger(structuredLogger);

      expect(() => contextLogger, returnsNormally);
      contextLogger.info('Test message');
      expect(logOutput.length, 1);
    });
  });
}
