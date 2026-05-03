// pkgs/aq_security/lib/src/server/monitoring/metrics.dart
//
// Server-only. Prometheus metrics для мониторинга.

/// Metric type
enum MetricType {
  counter,
  gauge,
  histogram,
  summary,
}

/// Metric value
abstract class MetricValue {
  const MetricValue();
  String toPrometheusFormat();
}

/// Counter value (только увеличивается)
final class CounterValue extends MetricValue {
  const CounterValue(this.value);
  final double value;

  @override
  String toPrometheusFormat() => value.toString();
}

/// Gauge value (может увеличиваться и уменьшаться)
final class GaugeValue extends MetricValue {
  const GaugeValue(this.value);
  final double value;

  @override
  String toPrometheusFormat() => value.toString();
}

/// Histogram value
final class HistogramValue extends MetricValue {
  const HistogramValue({
    required this.sum,
    required this.count,
    required this.buckets,
  });

  final double sum;
  final int count;
  final Map<double, int> buckets; // bucket -> count

  @override
  String toPrometheusFormat() {
    final lines = <String>[];

    // Buckets
    for (final entry in buckets.entries) {
      lines.add('_bucket{le="${entry.key}"} ${entry.value}');
    }
    lines.add('_bucket{le="+Inf"} $count');

    // Sum and count
    lines.add('_sum $sum');
    lines.add('_count $count');

    return lines.join('\n');
  }
}

/// Metric definition
final class Metric {
  Metric({
    required this.name,
    required this.type,
    required this.help,
    this.labels = const {},
  });

  final String name;
  final MetricType type;
  final String help;
  final Map<String, String> labels;

  MetricValue? _value;

  /// Set value
  void setValue(MetricValue value) {
    _value = value;
  }

  /// Get value
  MetricValue? get value => _value;

  /// Format для Prometheus
  String toPrometheusFormat() {
    if (_value == null) return '';

    final lines = <String>[];

    // HELP
    lines.add('# HELP $name $help');

    // TYPE
    final typeStr = type.name.toUpperCase();
    lines.add('# TYPE $name $typeStr');

    // Value
    final labelStr = labels.isEmpty
        ? ''
        : '{${labels.entries.map((e) => '${e.key}="${e.value}"').join(',')}}';

    if (_value is HistogramValue) {
      final histValue = _value as HistogramValue;
      final formatted = histValue.toPrometheusFormat();
      for (final line in formatted.split('\n')) {
        lines.add('$name$labelStr$line');
      }
    } else {
      lines.add('$name$labelStr ${_value!.toPrometheusFormat()}');
    }

    return lines.join('\n');
  }
}

/// Metrics collector
final class MetricsCollector {
  final Map<String, Metric> _metrics = {};

  /// Register metric
  void register(Metric metric) {
    final key = _metricKey(metric.name, metric.labels);
    _metrics[key] = metric;
  }

  /// Increment counter
  void incrementCounter(String name, {Map<String, String> labels = const {}, double value = 1}) {
    final key = _metricKey(name, labels);
    var metric = _metrics[key];

    if (metric == null) {
      metric = Metric(
        name: name,
        type: MetricType.counter,
        help: 'Counter for $name',
        labels: labels,
      );
      _metrics[key] = metric;
    }

    final currentValue = metric.value as CounterValue?;
    final newValue = (currentValue?.value ?? 0) + value;
    metric.setValue(CounterValue(newValue));
  }

  /// Set gauge
  void setGauge(String name, double value, {Map<String, String> labels = const {}}) {
    final key = _metricKey(name, labels);
    var metric = _metrics[key];

    if (metric == null) {
      metric = Metric(
        name: name,
        type: MetricType.gauge,
        help: 'Gauge for $name',
        labels: labels,
      );
      _metrics[key] = metric;
    }

    metric.setValue(GaugeValue(value));
  }

  /// Observe histogram
  void observeHistogram(
    String name,
    double value, {
    Map<String, String> labels = const {},
    List<double> buckets = const [0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5, 10],
  }) {
    final key = _metricKey(name, labels);
    var metric = _metrics[key];

    if (metric == null) {
      metric = Metric(
        name: name,
        type: MetricType.histogram,
        help: 'Histogram for $name',
        labels: labels,
      );
      _metrics[key] = metric;
    }

    final currentValue = metric.value as HistogramValue?;
    final currentSum = currentValue?.sum ?? 0;
    final currentCount = currentValue?.count ?? 0;
    final currentBuckets = Map<double, int>.from(currentValue?.buckets ?? {});

    // Update buckets
    for (final bucket in buckets) {
      if (value <= bucket) {
        currentBuckets[bucket] = (currentBuckets[bucket] ?? 0) + 1;
      }
    }

    metric.setValue(HistogramValue(
      sum: currentSum + value,
      count: currentCount + 1,
      buckets: currentBuckets,
    ));
  }

  /// Get all metrics
  List<Metric> getAll() => _metrics.values.toList();

  /// Get metric
  Metric? get(String name, {Map<String, String> labels = const {}}) {
    final key = _metricKey(name, labels);
    return _metrics[key];
  }

  /// Clear all metrics
  void clear() {
    _metrics.clear();
  }

  /// Export to Prometheus format
  String toPrometheusFormat() {
    final lines = <String>[];

    for (final metric in _metrics.values) {
      final formatted = metric.toPrometheusFormat();
      if (formatted.isNotEmpty) {
        lines.add(formatted);
        lines.add(''); // Empty line between metrics
      }
    }

    return lines.join('\n');
  }

  String _metricKey(String name, Map<String, String> labels) {
    if (labels.isEmpty) return name;
    final labelStr = labels.entries.map((e) => '${e.key}:${e.value}').join(',');
    return '$name{$labelStr}';
  }
}

/// Security metrics
final class SecurityMetrics {
  SecurityMetrics(this.collector);

  final MetricsCollector collector;

  // Auth metrics
  void recordAuthAttempt({required bool success, required String method}) {
    collector.incrementCounter(
      'auth_attempts_total',
      labels: {
        'success': success.toString(),
        'method': method,
      },
    );
  }

  void recordTokenIssued({required String type}) {
    collector.incrementCounter(
      'tokens_issued_total',
      labels: {'type': type},
    );
  }

  void recordTokenValidation({required bool valid}) {
    collector.incrementCounter(
      'token_validations_total',
      labels: {'valid': valid.toString()},
    );
  }

  // Rate limiting metrics
  void recordRateLimitHit({required String strategy}) {
    collector.incrementCounter(
      'rate_limit_hits_total',
      labels: {'strategy': strategy},
    );
  }

  void recordRateLimitBlocked({required String strategy}) {
    collector.incrementCounter(
      'rate_limit_blocked_total',
      labels: {'strategy': strategy},
    );
  }

  void setRateLimitRemaining(String key, int remaining) {
    collector.setGauge(
      'rate_limit_remaining',
      remaining.toDouble(),
      labels: {'key': key},
    );
  }

  // DoS protection metrics
  void recordConnectionAttempt({required bool allowed}) {
    collector.incrementCounter(
      'connection_attempts_total',
      labels: {'allowed': allowed.toString()},
    );
  }

  void setActiveConnections(int count) {
    collector.setGauge('active_connections', count.toDouble());
  }

  void recordIpBlocked({required String reason}) {
    collector.incrementCounter(
      'ip_blocked_total',
      labels: {'reason': reason},
    );
  }

  // Request metrics
  void recordRequest({
    required String method,
    required String path,
    required int statusCode,
    required double durationSeconds,
  }) {
    collector.incrementCounter(
      'http_requests_total',
      labels: {
        'method': method,
        'path': path,
        'status': statusCode.toString(),
      },
    );

    collector.observeHistogram(
      'http_request_duration_seconds',
      durationSeconds,
      labels: {
        'method': method,
        'path': path,
      },
    );
  }

  // Policy metrics
  void recordPolicyEvaluation({required bool allowed}) {
    collector.incrementCounter(
      'policy_evaluations_total',
      labels: {'allowed': allowed.toString()},
    );
  }

  // Permission metrics
  void recordPermissionCheck({required bool granted, required String resource}) {
    collector.incrementCounter(
      'permission_checks_total',
      labels: {
        'granted': granted.toString(),
        'resource': resource,
      },
    );
  }
}
