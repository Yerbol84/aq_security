// pkgs/aq_security/test/server/logging/structured_logger_test.dart

import 'dart:convert';
import 'package:test/test.dart';
import 'package:aq_security/src/server/logging/structured_logger.dart';

void main() {
  group('StructuredLogger', () {
    late List<String> logOutput;
    late StructuredLogger logger;

    setUp(() {
      logOutput = [];
      logger = StructuredLogger(
        minLevel: LogLevel.debug,
        output: (line) => logOutput.add(line),
      );
    });

    test('logs debug message', () {
      logger.debug('Debug message', component: 'test');

      expect(logOutput.length, 1);
      final log = jsonDecode(logOutput[0]) as Map<String, dynamic>;
      expect(log['level'], 'debug');
      expect(log['message'], 'Debug message');
      expect(log['component'], 'test');
    });

    test('logs info message', () {
      logger.info('Info message', component: 'test');

      expect(logOutput.length, 1);
      final log = jsonDecode(logOutput[0]) as Map<String, dynamic>;
      expect(log['level'], 'info');
      expect(log['message'], 'Info message');
    });

    test('logs warning message with error', () {
      logger.warn(
        'Warning message',
        component: 'test',
        error: Exception('Test error'),
      );

      expect(logOutput.length, 1);
      final log = jsonDecode(logOutput[0]) as Map<String, dynamic>;
      expect(log['level'], 'warn');
      expect(log['message'], 'Warning message');
      expect(log['error'], contains('Test error'));
    });

    test('logs error message with stack trace', () {
      logger.error(
        'Error message',
        component: 'test',
        error: Exception('Test error'),
        stackTrace: StackTrace.current,
      );

      expect(logOutput.length, 1);
      final log = jsonDecode(logOutput[0]) as Map<String, dynamic>;
      expect(log['level'], 'error');
      expect(log['message'], 'Error message');
      expect(log['error'], contains('Test error'));
      expect(log['stack_trace'], isNotNull);
    });

    test('includes request ID and user ID', () {
      logger.info(
        'Test message',
        requestId: 'req-123',
        userId: 'user-456',
      );

      expect(logOutput.length, 1);
      final log = jsonDecode(logOutput[0]) as Map<String, dynamic>;
      expect(log['request_id'], 'req-123');
      expect(log['user_id'], 'user-456');
    });

    test('includes trace ID and span ID', () {
      logger.info(
        'Test message',
        traceId: 'trace-123',
        spanId: 'span-456',
      );

      expect(logOutput.length, 1);
      final log = jsonDecode(logOutput[0]) as Map<String, dynamic>;
      expect(log['trace_id'], 'trace-123');
      expect(log['span_id'], 'span-456');
    });

    test('includes metadata', () {
      logger.info(
        'Test message',
        metadata: {
          'key1': 'value1',
          'key2': 42,
          'key3': true,
        },
      );

      expect(logOutput.length, 1);
      final log = jsonDecode(logOutput[0]) as Map<String, dynamic>;
      expect(log['key1'], 'value1');
      expect(log['key2'], 42);
      expect(log['key3'], true);
    });

    test('respects min level', () {
      final warnLogger = StructuredLogger(
        minLevel: LogLevel.warn,
        output: (line) => logOutput.add(line),
      );

      warnLogger.debug('Debug message');
      warnLogger.info('Info message');
      warnLogger.warn('Warning message');
      warnLogger.error('Error message');

      expect(logOutput.length, 2);
      final log1 = jsonDecode(logOutput[0]) as Map<String, dynamic>;
      final log2 = jsonDecode(logOutput[1]) as Map<String, dynamic>;
      expect(log1['level'], 'warn');
      expect(log2['level'], 'error');
    });

    test('timestamp is in ISO 8601 format', () {
      logger.info('Test message');

      expect(logOutput.length, 1);
      final log = jsonDecode(logOutput[0]) as Map<String, dynamic>;
      final timestamp = log['timestamp'] as String;
      expect(timestamp, matches(r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}'));
    });

    test('can disable stack trace', () {
      final noStackLogger = StructuredLogger(
        minLevel: LogLevel.debug,
        output: (line) => logOutput.add(line),
        includeStackTrace: false,
      );

      noStackLogger.error(
        'Error message',
        error: Exception('Test error'),
        stackTrace: StackTrace.current,
      );

      expect(logOutput.length, 1);
      final log = jsonDecode(logOutput[0]) as Map<String, dynamic>;
      expect(log['stack_trace'], isNull);
    });
  });

  group('Global logger', () {
    setUp(() {
      resetLogger();
    });

    tearDown(() {
      resetLogger();
    });

    test('throws if not initialized', () {
      expect(() => logger, throwsStateError);
    });

    test('can be initialized', () {
      final logOutput = <String>[];
      initializeLogger(
        minLevel: LogLevel.info,
        output: (line) => logOutput.add(line),
      );

      expect(() => logger, returnsNormally);
      logger.info('Test message');
      expect(logOutput.length, 1);
    });
  });

  group('LogLevel', () {
    test('has correct priority', () {
      expect(LogLevel.debug.priority, 0);
      expect(LogLevel.info.priority, 1);
      expect(LogLevel.warn.priority, 2);
      expect(LogLevel.error.priority, 3);
      expect(LogLevel.fatal.priority, 4);
    });
  });
}
