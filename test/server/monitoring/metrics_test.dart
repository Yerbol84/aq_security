// pkgs/aq_security/test/server/monitoring/metrics_test.dart

import 'package:test/test.dart';
import 'package:aq_security/src/server/monitoring/metrics.dart';

void main() {
  group('MetricsCollector', () {
    late MetricsCollector collector;

    setUp(() {
      collector = MetricsCollector();
    });

    test('incrementCounter creates and increments counter', () {
      collector.incrementCounter('test_counter');
      collector.incrementCounter('test_counter');
      collector.incrementCounter('test_counter', value: 3);

      final metric = collector.get('test_counter');
      expect(metric, isNotNull);
      expect(metric!.type, MetricType.counter);
      expect((metric.value as CounterValue).value, 5);
    });

    test('incrementCounter with labels creates separate metrics', () {
      collector.incrementCounter('test_counter', labels: {'status': 'success'});
      collector.incrementCounter('test_counter', labels: {'status': 'error'});

      final successMetric = collector.get('test_counter', labels: {'status': 'success'});
      final errorMetric = collector.get('test_counter', labels: {'status': 'error'});

      expect(successMetric, isNotNull);
      expect(errorMetric, isNotNull);
      expect((successMetric!.value as CounterValue).value, 1);
      expect((errorMetric!.value as CounterValue).value, 1);
    });

    test('setGauge sets gauge value', () {
      collector.setGauge('test_gauge', 42.5);
      collector.setGauge('test_gauge', 100.0);

      final metric = collector.get('test_gauge');
      expect(metric, isNotNull);
      expect(metric!.type, MetricType.gauge);
      expect((metric.value as GaugeValue).value, 100.0);
    });

    test('observeHistogram records observations', () {
      collector.observeHistogram('test_histogram', 0.003);
      collector.observeHistogram('test_histogram', 0.015);
      collector.observeHistogram('test_histogram', 0.5);

      final metric = collector.get('test_histogram');
      expect(metric, isNotNull);
      expect(metric!.type, MetricType.histogram);

      final histValue = metric.value as HistogramValue;
      expect(histValue.count, 3);
      expect(histValue.sum, closeTo(0.518, 0.001));
      expect(histValue.buckets[0.005], 1); // 0.003 <= 0.005
      expect(histValue.buckets[0.025], 2); // 0.003, 0.015 <= 0.025
      expect(histValue.buckets[1], 3); // all <= 1
    });

    test('toPrometheusFormat exports counter correctly', () {
      collector.incrementCounter('http_requests_total',
        labels: {'method': 'GET', 'status': '200'},
        value: 42,
      );

      final output = collector.toPrometheusFormat();

      expect(output, contains('# HELP http_requests_total'));
      expect(output, contains('# TYPE http_requests_total COUNTER'));
      expect(output, contains('http_requests_total{method="GET",status="200"} 42'));
    });

    test('toPrometheusFormat exports gauge correctly', () {
      collector.setGauge('active_connections', 15);

      final output = collector.toPrometheusFormat();

      expect(output, contains('# HELP active_connections'));
      expect(output, contains('# TYPE active_connections GAUGE'));
      expect(output, contains('active_connections 15'));
    });

    test('toPrometheusFormat exports histogram correctly', () {
      collector.observeHistogram('request_duration_seconds', 0.5);

      final output = collector.toPrometheusFormat();

      expect(output, contains('# HELP request_duration_seconds'));
      expect(output, contains('# TYPE request_duration_seconds HISTOGRAM'));
      expect(output, contains('_bucket{le="0.5"} 1'));
      expect(output, contains('_bucket{le="+Inf"} 1'));
      expect(output, contains('_sum 0.5'));
      expect(output, contains('_count 1'));
    });

    test('clear removes all metrics', () {
      collector.incrementCounter('test1');
      collector.setGauge('test2', 42);

      expect(collector.getAll().length, 2);

      collector.clear();

      expect(collector.getAll().length, 0);
    });
  });

  group('SecurityMetrics', () {
    late MetricsCollector collector;
    late SecurityMetrics metrics;

    setUp(() {
      collector = MetricsCollector();
      metrics = SecurityMetrics(collector);
    });

    test('recordAuthAttempt increments counter', () {
      metrics.recordAuthAttempt(success: true, method: 'password');
      metrics.recordAuthAttempt(success: false, method: 'password');

      final successMetric = collector.get('auth_attempts_total',
        labels: {'success': 'true', 'method': 'password'});
      final failMetric = collector.get('auth_attempts_total',
        labels: {'success': 'false', 'method': 'password'});

      expect((successMetric!.value as CounterValue).value, 1);
      expect((failMetric!.value as CounterValue).value, 1);
    });

    test('recordTokenIssued increments counter', () {
      metrics.recordTokenIssued(type: 'access');
      metrics.recordTokenIssued(type: 'refresh');

      final accessMetric = collector.get('tokens_issued_total',
        labels: {'type': 'access'});
      final refreshMetric = collector.get('tokens_issued_total',
        labels: {'type': 'refresh'});

      expect((accessMetric!.value as CounterValue).value, 1);
      expect((refreshMetric!.value as CounterValue).value, 1);
    });

    test('recordRateLimitHit and recordRateLimitBlocked', () {
      metrics.recordRateLimitHit(strategy: 'byIp');
      metrics.recordRateLimitBlocked(strategy: 'byIp');

      final hitMetric = collector.get('rate_limit_hits_total',
        labels: {'strategy': 'byIp'});
      final blockedMetric = collector.get('rate_limit_blocked_total',
        labels: {'strategy': 'byIp'});

      expect((hitMetric!.value as CounterValue).value, 1);
      expect((blockedMetric!.value as CounterValue).value, 1);
    });

    test('setRateLimitRemaining sets gauge', () {
      metrics.setRateLimitRemaining('user:123', 50);

      final metric = collector.get('rate_limit_remaining',
        labels: {'key': 'user:123'});

      expect((metric!.value as GaugeValue).value, 50);
    });

    test('recordConnectionAttempt increments counter', () {
      metrics.recordConnectionAttempt(allowed: true);
      metrics.recordConnectionAttempt(allowed: false);

      final allowedMetric = collector.get('connection_attempts_total',
        labels: {'allowed': 'true'});
      final blockedMetric = collector.get('connection_attempts_total',
        labels: {'allowed': 'false'});

      expect((allowedMetric!.value as CounterValue).value, 1);
      expect((blockedMetric!.value as CounterValue).value, 1);
    });

    test('setActiveConnections sets gauge', () {
      metrics.setActiveConnections(25);

      final metric = collector.get('active_connections');
      expect((metric!.value as GaugeValue).value, 25);
    });

    test('recordIpBlocked increments counter', () {
      metrics.recordIpBlocked(reason: 'too_many_requests');

      final metric = collector.get('ip_blocked_total',
        labels: {'reason': 'too_many_requests'});

      expect((metric!.value as CounterValue).value, 1);
    });

    test('recordRequest increments counter and observes histogram', () {
      metrics.recordRequest(
        method: 'GET',
        path: '/api/users',
        statusCode: 200,
        durationSeconds: 0.05,
      );

      final counterMetric = collector.get('http_requests_total',
        labels: {'method': 'GET', 'path': '/api/users', 'status': '200'});
      final histogramMetric = collector.get('http_request_duration_seconds',
        labels: {'method': 'GET', 'path': '/api/users'});

      expect((counterMetric!.value as CounterValue).value, 1);
      expect(histogramMetric, isNotNull);
      expect((histogramMetric!.value as HistogramValue).count, 1);
    });

    test('recordPolicyEvaluation increments counter', () {
      metrics.recordPolicyEvaluation(allowed: true);
      metrics.recordPolicyEvaluation(allowed: false);

      final allowedMetric = collector.get('policy_evaluations_total',
        labels: {'allowed': 'true'});
      final deniedMetric = collector.get('policy_evaluations_total',
        labels: {'allowed': 'false'});

      expect((allowedMetric!.value as CounterValue).value, 1);
      expect((deniedMetric!.value as CounterValue).value, 1);
    });

    test('recordPermissionCheck increments counter', () {
      metrics.recordPermissionCheck(granted: true, resource: 'users');
      metrics.recordPermissionCheck(granted: false, resource: 'admin');

      final grantedMetric = collector.get('permission_checks_total',
        labels: {'granted': 'true', 'resource': 'users'});
      final deniedMetric = collector.get('permission_checks_total',
        labels: {'granted': 'false', 'resource': 'admin'});

      expect((grantedMetric!.value as CounterValue).value, 1);
      expect((deniedMetric!.value as CounterValue).value, 1);
    });
  });
}
