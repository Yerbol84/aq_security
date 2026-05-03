// pkgs/aq_security/lib/src/server/metrics/metrics_aggregator.dart
//
// Агрегатор метрик с периодическим сохранением в Vault.

import 'dart:async';
import 'package:aq_schema/aq_schema.dart';
import 'metrics_collector.dart';

/// Агрегатор метрик RBAC системы.
/// Периодически собирает метрики из RbacMetricsCollector и сохраняет в Vault.
class MetricsAggregator {
  MetricsAggregator({
    required this.collector,
    required this.repository,
    this.aggregationInterval = const Duration(minutes: 5),
  });

  /// Сборщик метрик.
  final RbacMetricsCollector collector;

  /// Репозиторий для сохранения метрик.
  final MetricsRepository repository;

  /// Интервал агрегации (по умолчанию 5 минут).
  final Duration aggregationInterval;

  Timer? _timer;
  bool _isRunning = false;

  /// Запустить периодическую агрегацию.
  void start() {
    if (_isRunning) return;

    _isRunning = true;
    _timer = Timer.periodic(aggregationInterval, (_) => _aggregate());
  }

  /// Остановить агрегацию.
  void stop() {
    _timer?.cancel();
    _timer = null;
    _isRunning = false;
  }

  /// Выполнить агрегацию вручную.
  Future<RBACMetrics> aggregateNow() async {
    return await _aggregate();
  }

  /// Внутренний метод агрегации.
  Future<RBACMetrics> _aggregate() async {
    try {
      // Собрать метрики и сбросить счётчики
      final metrics = collector.collectAndReset();

      // Сохранить в Vault
      await repository.save(metrics);

      return metrics;
    } catch (e) {
      // Логируем ошибку, но не прерываем работу
      print('Ошибка агрегации метрик: $e');
      rethrow;
    }
  }

  /// Получить метрики за период.
  Future<List<RBACMetrics>> getMetrics({
    required int startTime,
    required int endTime,
  }) async {
    return await repository.getMetricsInRange(startTime, endTime);
  }

  /// Получить агрегированные метрики за период.
  Future<RBACMetrics> getAggregatedMetrics({
    required int startTime,
    required int endTime,
  }) async {
    final metricsList = await repository.getMetricsInRange(startTime, endTime);

    if (metricsList.isEmpty) {
      return RBACMetrics(
        totalChecks: 0,
        allowedChecks: 0,
        deniedChecks: 0,
        cacheHits: 0,
        cacheMisses: 0,
        avgEvaluationTimeMs: 0.0,
        maxEvaluationTimeMs: 0,
        policyEvaluations: 0,
        timestamp: endTime,
        avgCheckDuration: 0.0,
        checksByResource: {},
        checksByAction: {},
        checksByUser: {},
        totalDenials: 0,
        denialsByReason: {},
        denialsByResource: {},
        roleUsage: {},
        permissionUsage: {},
        policyTriggers: {},
        policyDenials: {},
      );
    }

    // Агрегировать все метрики
    return _aggregateMetrics(metricsList, startTime, endTime);
  }

  /// Агрегировать список метрик в одну.
  RBACMetrics _aggregateMetrics(
    List<RBACMetrics> metricsList,
    int periodStart,
    int periodEnd,
  ) {
    int totalChecks = 0;
    int cacheHits = 0;
    int cacheMisses = 0;
    double totalDuration = 0.0;
    int totalDenials = 0;
    int maxEvalTime = 0;
    int totalPolicyEvals = 0;

    final checksByResource = <String, int>{};
    final checksByAction = <String, int>{};
    final checksByUser = <String, int>{};
    final denialsByReason = <String, int>{};
    final denialsByResource = <String, int>{};
    final roleUsage = <String, int>{};
    final permissionUsage = <String, int>{};
    final policyTriggers = <String, int>{};
    final policyDenials = <String, int>{};

    for (final metrics in metricsList) {
      totalChecks += metrics.totalChecks;
      cacheHits += metrics.cacheHits;
      cacheMisses += metrics.cacheMisses;
      totalDuration += metrics.avgCheckDuration * metrics.totalChecks;
      totalDenials += metrics.totalDenials;
      if (metrics.maxEvaluationTimeMs > maxEvalTime) {
        maxEvalTime = metrics.maxEvaluationTimeMs;
      }
      totalPolicyEvals += metrics.policyEvaluations;

      _mergeMaps(checksByResource, metrics.checksByResource);
      _mergeMaps(checksByAction, metrics.checksByAction);
      _mergeMaps(checksByUser, metrics.checksByUser);
      _mergeMaps(denialsByReason, metrics.denialsByReason);
      _mergeMaps(denialsByResource, metrics.denialsByResource);
      _mergeMaps(roleUsage, metrics.roleUsage);
      _mergeMaps(permissionUsage, metrics.permissionUsage);
      _mergeMaps(policyTriggers, metrics.policyTriggers);
      _mergeMaps(policyDenials, metrics.policyDenials);
    }

    final avgCheckDuration =
        totalChecks > 0 ? totalDuration / totalChecks : 0.0;

    return RBACMetrics(
      totalChecks: totalChecks,
      allowedChecks: totalChecks - totalDenials,
      deniedChecks: totalDenials,
      cacheHits: cacheHits,
      cacheMisses: cacheMisses,
      avgEvaluationTimeMs: avgCheckDuration,
      maxEvaluationTimeMs: maxEvalTime,
      policyEvaluations: totalPolicyEvals,
      timestamp: periodEnd,
      avgCheckDuration: avgCheckDuration,
      checksByResource: checksByResource,
      checksByAction: checksByAction,
      checksByUser: checksByUser,
      totalDenials: totalDenials,
      denialsByReason: denialsByReason,
      denialsByResource: denialsByResource,
      roleUsage: roleUsage,
      permissionUsage: permissionUsage,
      policyTriggers: policyTriggers,
      policyDenials: policyDenials,
    );
  }

  /// Объединить две Map<String, int>.
  void _mergeMaps(Map<String, int> target, Map<String, int> source) {
    for (final entry in source.entries) {
      target[entry.key] = (target[entry.key] ?? 0) + entry.value;
    }
  }

  /// Очистить старые метрики (старше указанного периода).
  Future<void> cleanupOldMetrics(Duration retentionPeriod) async {
    final cutoffTime =
        DateTime.now().subtract(retentionPeriod).millisecondsSinceEpoch;

    await repository.deleteOlderThan(cutoffTime);
  }
}

/// Репозиторий метрик (абстракция).
abstract class MetricsRepository {
  /// Сохранить метрики.
  Future<void> save(RBACMetrics metrics);

  /// Получить метрики за период.
  Future<List<RBACMetrics>> getMetricsInRange(int startTime, int endTime);

  /// Удалить метрики старше указанного времени.
  Future<void> deleteOlderThan(int timestamp);
}
