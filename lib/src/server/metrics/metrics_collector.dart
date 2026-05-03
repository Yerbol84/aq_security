// pkgs/aq_security/lib/src/server/metrics/metrics_collector.dart
//
// Сборщик метрик RBAC системы в реальном времени.

import 'package:aq_schema/aq_schema.dart';

/// Сборщик метрик RBAC системы.
/// Собирает метрики в реальном времени для мониторинга и аналитики.
class RbacMetricsCollector {
  RbacMetricsCollector();

  // Performance метрики
  int _totalChecks = 0;
  int _cacheHits = 0;
  int _cacheMisses = 0;
  final List<int> _checkDurations = [];

  // Access patterns
  final Map<String, int> _checksByResource = {};
  final Map<String, int> _checksByAction = {};
  final Map<String, int> _checksByUser = {};

  // Denials
  int _totalDenials = 0;
  final Map<String, int> _denialsByReason = {};
  final Map<String, int> _denialsByResource = {};

  // Roles & Permissions
  final Map<String, int> _roleUsage = {};
  final Map<String, int> _permissionUsage = {};

  // Policies
  final Map<String, int> _policyTriggers = {};
  final Map<String, int> _policyDenials = {};

  // Период сбора
  int? _periodStart;

  /// Записать проверку доступа.
  void recordCheck({
    required String userId,
    required String resource,
    required String action,
    required String scope,
    required bool allowed,
    required int durationMs,
    required bool fromCache,
    String? denialReason,
    List<String>? roles,
    List<String>? permissions,
    List<String>? appliedPolicies,
  }) {
    _periodStart ??= DateTime.now().millisecondsSinceEpoch;

    // Performance
    _totalChecks++;
    if (fromCache) {
      _cacheHits++;
    } else {
      _cacheMisses++;
    }
    _checkDurations.add(durationMs);

    // Access patterns
    _checksByResource[resource] = (_checksByResource[resource] ?? 0) + 1;
    _checksByAction[action] = (_checksByAction[action] ?? 0) + 1;
    _checksByUser[userId] = (_checksByUser[userId] ?? 0) + 1;

    // Denials
    if (!allowed) {
      _totalDenials++;
      if (denialReason != null) {
        _denialsByReason[denialReason] = (_denialsByReason[denialReason] ?? 0) + 1;
      }
      _denialsByResource[resource] = (_denialsByResource[resource] ?? 0) + 1;
    }

    // Roles
    if (roles != null) {
      for (final role in roles) {
        _roleUsage[role] = (_roleUsage[role] ?? 0) + 1;
      }
    }

    // Permissions
    if (permissions != null) {
      for (final permission in permissions) {
        _permissionUsage[permission] = (_permissionUsage[permission] ?? 0) + 1;
      }
    }

    // Policies
    if (appliedPolicies != null) {
      for (final policyId in appliedPolicies) {
        _policyTriggers[policyId] = (_policyTriggers[policyId] ?? 0) + 1;
        if (!allowed) {
          _policyDenials[policyId] = (_policyDenials[policyId] ?? 0) + 1;
        }
      }
    }
  }

  /// Получить текущие метрики и сбросить счётчики.
  RBACMetrics collectAndReset() {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000; // Unix timestamp в секундах
    final periodStart = _periodStart ?? now;

    final metrics = RBACMetrics(
      totalChecks: _totalChecks,
      allowedChecks: _totalChecks - _totalDenials,
      deniedChecks: _totalDenials,
      cacheHits: _cacheHits,
      cacheMisses: _cacheMisses,
      avgEvaluationTimeMs: _calculateAvgDuration(),
      maxEvaluationTimeMs: _checkDurations.isEmpty ? 0 : _checkDurations.reduce((a, b) => a > b ? a : b),
      policyEvaluations: _policyTriggers.values.fold(0, (sum, count) => sum + count),
      timestamp: now,
      avgCheckDuration: _calculateAvgDuration(),
      checksByResource: Map.from(_checksByResource),
      checksByAction: Map.from(_checksByAction),
      checksByUser: Map.from(_checksByUser),
      totalDenials: _totalDenials,
      denialsByReason: Map.from(_denialsByReason),
      denialsByResource: Map.from(_denialsByResource),
      roleUsage: Map.from(_roleUsage),
      permissionUsage: Map.from(_permissionUsage),
      policyTriggers: Map.from(_policyTriggers),
      policyDenials: Map.from(_policyDenials),
    );

    // Сбросить счётчики
    _reset();

    return metrics;
  }

  /// Получить текущие метрики без сброса.
  RBACMetrics snapshot() {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000; // Unix timestamp в секундах
    final periodStart = _periodStart ?? now;

    return RBACMetrics(
      totalChecks: _totalChecks,
      allowedChecks: _totalChecks - _totalDenials,
      deniedChecks: _totalDenials,
      cacheHits: _cacheHits,
      cacheMisses: _cacheMisses,
      avgEvaluationTimeMs: _calculateAvgDuration(),
      maxEvaluationTimeMs: _checkDurations.isEmpty ? 0 : _checkDurations.reduce((a, b) => a > b ? a : b),
      policyEvaluations: _policyTriggers.values.fold(0, (sum, count) => sum + count),
      timestamp: now,
      avgCheckDuration: _calculateAvgDuration(),
      checksByResource: Map.from(_checksByResource),
      checksByAction: Map.from(_checksByAction),
      checksByUser: Map.from(_checksByUser),
      totalDenials: _totalDenials,
      denialsByReason: Map.from(_denialsByReason),
      denialsByResource: Map.from(_denialsByResource),
      roleUsage: Map.from(_roleUsage),
      permissionUsage: Map.from(_permissionUsage),
      policyTriggers: Map.from(_policyTriggers),
      policyDenials: Map.from(_policyDenials),
    );
  }

  /// Вычислить среднюю длительность проверки.
  double _calculateAvgDuration() {
    if (_checkDurations.isEmpty) return 0.0;
    final sum = _checkDurations.reduce((a, b) => a + b);
    return sum / _checkDurations.length;
  }

  /// Сбросить все счётчики.
  void _reset() {
    _totalChecks = 0;
    _cacheHits = 0;
    _cacheMisses = 0;
    _checkDurations.clear();
    _checksByResource.clear();
    _checksByAction.clear();
    _checksByUser.clear();
    _totalDenials = 0;
    _denialsByReason.clear();
    _denialsByResource.clear();
    _roleUsage.clear();
    _permissionUsage.clear();
    _policyTriggers.clear();
    _policyDenials.clear();
    _periodStart = null;
  }

  /// Получить статистику по пользователю.
  UserMetrics? getUserMetrics(String userId) {
    final checks = _checksByUser[userId];
    if (checks == null) return null;

    return UserMetrics(
      userId: userId,
      totalChecks: checks,
      // Можно добавить больше деталей при необходимости
    );
  }

  /// Получить топ N ресурсов по количеству проверок.
  List<MapEntry<String, int>> getTopResources(int limit) {
    final entries = _checksByResource.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return entries.take(limit).toList();
  }

  /// Получить топ N пользователей по количеству проверок.
  List<MapEntry<String, int>> getTopUsers(int limit) {
    final entries = _checksByUser.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return entries.take(limit).toList();
  }

  /// Получить топ N причин отказа.
  List<MapEntry<String, int>> getTopDenialReasons(int limit) {
    final entries = _denialsByReason.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return entries.take(limit).toList();
  }
}

/// Метрики пользователя.
class UserMetrics {
  UserMetrics({
    required this.userId,
    required this.totalChecks,
  });

  final String userId;
  final int totalChecks;
}
