// pkgs/aq_security/test/server/logging/logging_middleware_test.dart

import 'dart:convert';
import 'package:test/test.dart';
import 'package:shelf/shelf.dart';
import 'package:aq_security/src/server/logging/structured_logger.dart';
import 'package:aq_security/src/server/logging/context_logger.dart';
import 'package:aq_security/src/server/logging/log_context.dart';
import 'package:aq_security/src/server/logging/logging_middleware.dart';

void main() {
  group('loggingMiddleware', () {
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

    test('logs incoming request', () async {
      final handler = const Pipeline()
          .addMiddleware(loggingMiddleware(logger: contextLogger))
          .addHandler((request) => Response.ok('OK'));

      final request = Request('GET', Uri.parse('http://localhost/api/test'));
      await handler(request);

      expect(logOutput.length, 2); // Incoming + completed
      final incomingLog = jsonDecode(logOutput[0]) as Map<String, dynamic>;
      expect(incomingLog['message'], 'Incoming request');
      expect(incomingLog['method'], 'GET');
      expect(incomingLog['path'], 'api/test');
    });

    test('logs completed request', () async {
      final handler = const Pipeline()
          .addMiddleware(loggingMiddleware(logger: contextLogger))
          .addHandler((request) => Response.ok('OK'));

      final request = Request('GET', Uri.parse('http://localhost/api/test'));
      await handler(request);

      expect(logOutput.length, 2);
      final completedLog = jsonDecode(logOutput[1]) as Map<String, dynamic>;
      expect(completedLog['message'], 'Request completed');
      expect(completedLog['method'], 'GET');
      expect(completedLog['path'], 'api/test');
      expect(completedLog['status'], 200);
      expect(completedLog['duration_ms'], isA<num>());
    });

    test('adds request ID and trace ID to response headers', () async {
      final handler = const Pipeline()
          .addMiddleware(loggingMiddleware(logger: contextLogger))
          .addHandler((request) => Response.ok('OK'));

      final request = Request('GET', Uri.parse('http://localhost/api/test'));
      final response = await handler(request);

      expect(response.headers['X-Request-ID'], isNotNull);
      expect(response.headers['X-Trace-ID'], isNotNull);
      expect(response.headers['X-Request-ID'], startsWith('req-'));
      expect(response.headers['X-Trace-ID']!.length, 32);
    });

    test('adds log context to request context', () async {
      String? capturedRequestId;
      String? capturedTraceId;

      final handler = const Pipeline()
          .addMiddleware(loggingMiddleware(logger: contextLogger))
          .addHandler((request) {
            capturedRequestId = getRequestIdFromRequest(request);
            capturedTraceId = getTraceIdFromRequest(request);
            return Response.ok('OK');
          });

      final request = Request('GET', Uri.parse('http://localhost/api/test'));
      await handler(request);

      expect(capturedRequestId, isNotNull);
      expect(capturedTraceId, isNotNull);
      expect(capturedRequestId, startsWith('req-'));
    });

    test('logs failed request', () async {
      final handler = const Pipeline()
          .addMiddleware(loggingMiddleware(logger: contextLogger))
          .addHandler((request) => throw Exception('Test error'));

      final request = Request('GET', Uri.parse('http://localhost/api/test'));

      try {
        await handler(request);
        fail('Should throw exception');
      } catch (e) {
        // Expected
      }

      expect(logOutput.length, 2); // Incoming + failed
      final failedLog = jsonDecode(logOutput[1]) as Map<String, dynamic>;
      expect(failedLog['message'], 'Request failed');
      expect(failedLog['level'], 'error');
      expect(failedLog['error'], contains('Test error'));
    });

    test('extracts user ID from JWT claims', () async {
      final handler = const Pipeline()
          .addMiddleware(loggingMiddleware(logger: contextLogger))
          .addHandler((request) => Response.ok('OK'));

      final request = Request(
        'GET',
        Uri.parse('http://localhost/api/test'),
        context: {
          'claims': {'sub': 'user-123'},
        },
      );
      await handler(request);

      final completedLog = jsonDecode(logOutput[1]) as Map<String, dynamic>;
      expect(completedLog['user_id'], 'user-123');
    });

    test('extracts client IP from X-Forwarded-For', () async {
      final handler = const Pipeline()
          .addMiddleware(loggingMiddleware(logger: contextLogger))
          .addHandler((request) => Response.ok('OK'));

      final request = Request(
        'GET',
        Uri.parse('http://localhost/api/test'),
        headers: {'x-forwarded-for': '192.168.1.1, 10.0.0.1'},
      );
      await handler(request);

      final incomingLog = jsonDecode(logOutput[0]) as Map<String, dynamic>;
      expect(incomingLog['ip'], '192.168.1.1');
    });

    test('extracts client IP from X-Real-IP', () async {
      final handler = const Pipeline()
          .addMiddleware(loggingMiddleware(logger: contextLogger))
          .addHandler((request) => Response.ok('OK'));

      final request = Request(
        'GET',
        Uri.parse('http://localhost/api/test'),
        headers: {'x-real-ip': '192.168.1.1'},
      );
      await handler(request);

      final incomingLog = jsonDecode(logOutput[0]) as Map<String, dynamic>;
      expect(incomingLog['ip'], '192.168.1.1');
    });

    test('includes query parameters in log', () async {
      final handler = const Pipeline()
          .addMiddleware(loggingMiddleware(logger: contextLogger))
          .addHandler((request) => Response.ok('OK'));

      final request = Request(
        'GET',
        Uri.parse('http://localhost/api/test?foo=bar&baz=qux'),
      );
      await handler(request);

      final incomingLog = jsonDecode(logOutput[0]) as Map<String, dynamic>;
      expect(incomingLog['query'], 'foo=bar&baz=qux');
    });

    test('includes user agent in log', () async {
      final handler = const Pipeline()
          .addMiddleware(loggingMiddleware(logger: contextLogger))
          .addHandler((request) => Response.ok('OK'));

      final request = Request(
        'GET',
        Uri.parse('http://localhost/api/test'),
        headers: {'user-agent': 'Test Agent/1.0'},
      );
      await handler(request);

      final incomingLog = jsonDecode(logOutput[0]) as Map<String, dynamic>;
      expect(incomingLog['user_agent'], 'Test Agent/1.0');
    });

    test('measures request duration', () async {
      final handler = const Pipeline()
          .addMiddleware(loggingMiddleware(logger: contextLogger))
          .addHandler((request) async {
            await Future.delayed(Duration(milliseconds: 50));
            return Response.ok('OK');
          });

      final request = Request('GET', Uri.parse('http://localhost/api/test'));
      await handler(request);

      final completedLog = jsonDecode(logOutput[1]) as Map<String, dynamic>;
      final durationMs = completedLog['duration_ms'] as num;
      expect(durationMs, greaterThan(40)); // Should be ~50ms
    });
  });

  group('Helper functions', () {
    test('getLogContextFromRequest returns context', () {
      final context = LogContext(requestId: 'req-123');
      final request = Request(
        'GET',
        Uri.parse('http://localhost/test'),
        context: {'log_context': context},
      );

      final extracted = getLogContextFromRequest(request);
      expect(extracted, isNotNull);
      expect(extracted!.requestId, 'req-123');
    });

    test('getRequestIdFromRequest returns request ID', () {
      final request = Request(
        'GET',
        Uri.parse('http://localhost/test'),
        context: {'request_id': 'req-123'},
      );

      final requestId = getRequestIdFromRequest(request);
      expect(requestId, 'req-123');
    });

    test('getTraceIdFromRequest returns trace ID', () {
      final request = Request(
        'GET',
        Uri.parse('http://localhost/test'),
        context: {'trace_id': 'trace-123'},
      );

      final traceId = getTraceIdFromRequest(request);
      expect(traceId, 'trace-123');
    });
  });
}
