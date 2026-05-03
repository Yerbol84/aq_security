// pkgs/aq_security/test/server/logging/log_context_test.dart

import 'package:test/test.dart';
import 'package:aq_security/src/server/logging/log_context.dart';

void main() {
  group('LogContext', () {
    test('creates context with all fields', () {
      final context = LogContext(
        requestId: 'req-123',
        userId: 'user-456',
        traceId: 'trace-789',
        spanId: 'span-abc',
        component: 'test',
        metadata: {'key': 'value'},
      );

      expect(context.requestId, 'req-123');
      expect(context.userId, 'user-456');
      expect(context.traceId, 'trace-789');
      expect(context.spanId, 'span-abc');
      expect(context.component, 'test');
      expect(context.metadata['key'], 'value');
    });

    test('creates span with new span ID', () {
      final context = LogContext(
        requestId: 'req-123',
        traceId: 'trace-789',
      );

      final span = context.createSpan(component: 'child');

      expect(span.requestId, 'req-123');
      expect(span.traceId, 'trace-789');
      expect(span.spanId, isNotNull);
      expect(span.spanId, isNot(context.spanId));
      expect(span.component, 'child');
    });

    test('creates span with generated trace ID if missing', () {
      final context = LogContext(requestId: 'req-123');

      final span = context.createSpan();

      expect(span.traceId, isNotNull);
      expect(span.traceId!.length, 32); // 128-bit hex
    });

    test('copyWith creates new context with updated fields', () {
      final context = LogContext(
        requestId: 'req-123',
        userId: 'user-456',
      );

      final updated = context.copyWith(
        userId: 'user-789',
        component: 'test',
      );

      expect(updated.requestId, 'req-123');
      expect(updated.userId, 'user-789');
      expect(updated.component, 'test');
    });
  });

  group('Context propagation', () {
    test('currentLogContext returns null outside zone', () {
      expect(currentLogContext, isNull);
    });

    test('runWithLogContext propagates context', () {
      final context = LogContext(requestId: 'req-123');

      final result = runWithLogContext(context, () {
        expect(currentLogContext, isNotNull);
        expect(currentLogContext!.requestId, 'req-123');
        return 42;
      });

      expect(result, 42);
      expect(currentLogContext, isNull);
    });

    test('runAsyncWithLogContext propagates context', () async {
      final context = LogContext(requestId: 'req-123');

      final result = await runAsyncWithLogContext(context, () async {
        expect(currentLogContext, isNotNull);
        expect(currentLogContext!.requestId, 'req-123');
        await Future.delayed(Duration(milliseconds: 10));
        expect(currentLogContext!.requestId, 'req-123');
        return 42;
      });

      expect(result, 42);
      expect(currentLogContext, isNull);
    });

    test('context propagates through nested async calls', () async {
      final context = LogContext(requestId: 'req-123');

      await runAsyncWithLogContext(context, () async {
        expect(currentLogContext!.requestId, 'req-123');

        await Future(() async {
          expect(currentLogContext!.requestId, 'req-123');

          await Future(() {
            expect(currentLogContext!.requestId, 'req-123');
          });
        });
      });
    });
  });

  group('ID generation', () {
    test('generateRequestId creates unique IDs', () {
      final id1 = generateRequestId();
      final id2 = generateRequestId();

      expect(id1, isNotNull);
      expect(id2, isNotNull);
      expect(id1, isNot(id2));
      expect(id1, startsWith('req-'));
    });

    test('generateTraceId creates 128-bit hex', () {
      final traceId = generateTraceId();

      expect(traceId, isNotNull);
      expect(traceId.length, 32); // 128 bits = 32 hex chars
      expect(traceId, matches(r'^[0-9a-f]{32}$'));
    });

    test('generateSpanId creates 64-bit hex', () {
      final spanId = generateSpanId();

      expect(spanId, isNotNull);
      expect(spanId.length, 16); // 64 bits = 16 hex chars
      expect(spanId, matches(r'^[0-9a-f]{16}$'));
    });

    test('generates unique trace IDs', () {
      final id1 = generateTraceId();
      final id2 = generateTraceId();

      expect(id1, isNot(id2));
    });

    test('generates unique span IDs', () {
      final id1 = generateSpanId();
      final id2 = generateSpanId();

      expect(id1, isNot(id2));
    });
  });
}
