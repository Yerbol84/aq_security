// pkgs/aq_security/lib/src/server/dos_protection/connection_limiter.dart
//
// Server-only. Connection limiting для защиты от DoS.
// Ограничивает количество одновременных соединений.

import 'dart:async';
import '../monitoring/metrics.dart';

/// Connection limiter configuration
final class ConnectionLimitConfig {
  const ConnectionLimitConfig({
    required this.maxConnections,
    required this.maxConnectionsPerIp,
    this.cleanupIntervalSeconds = 60,
  });

  /// Максимальное количество одновременных соединений
  final int maxConnections;

  /// Максимальное количество соединений с одного IP
  final int maxConnectionsPerIp;

  /// Интервал cleanup в секундах
  final int cleanupIntervalSeconds;
}

/// Connection info
final class ConnectionInfo {
  ConnectionInfo({
    required this.id,
    required this.ip,
    required this.startTime,
  });

  final String id;
  final String ip;
  final int startTime;

  int get duration => _now() - startTime;

  static int _now() => DateTime.now().millisecondsSinceEpoch ~/ 1000;
}

/// Connection limiter
final class ConnectionLimiter {
  ConnectionLimiter({
    required this.config,
    this.metrics,
  }) {
    _startCleanupTimer();
  }

  final ConnectionLimitConfig config;
  final SecurityMetrics? metrics;
  final Map<String, ConnectionInfo> _connections = {};
  final Map<String, Set<String>> _connectionsByIp = {};
  Timer? _cleanupTimer;

  /// Попытаться зарегистрировать новое соединение
  ConnectionLimitResult tryConnect({
    required String connectionId,
    required String ip,
  }) {
    // Проверить global limit
    if (_connections.length >= config.maxConnections) {
      // Record blocked connection
      metrics?.recordConnectionAttempt(allowed: false);

      return ConnectionLimitResult(
        allowed: false,
        reason: 'Global connection limit exceeded',
        currentConnections: _connections.length,
        maxConnections: config.maxConnections,
      );
    }

    // Проверить per-IP limit
    final ipConnections = _connectionsByIp[ip]?.length ?? 0;
    if (ipConnections >= config.maxConnectionsPerIp) {
      // Record blocked connection
      metrics?.recordConnectionAttempt(allowed: false);

      return ConnectionLimitResult(
        allowed: false,
        reason: 'Per-IP connection limit exceeded',
        currentConnections: ipConnections,
        maxConnections: config.maxConnectionsPerIp,
      );
    }

    // Зарегистрировать соединение
    final connection = ConnectionInfo(
      id: connectionId,
      ip: ip,
      startTime: _now(),
    );

    _connections[connectionId] = connection;
    _connectionsByIp.putIfAbsent(ip, () => {}).add(connectionId);

    // Record successful connection
    metrics?.recordConnectionAttempt(allowed: true);
    metrics?.setActiveConnections(_connections.length);

    return ConnectionLimitResult(
      allowed: true,
      reason: null,
      currentConnections: _connections.length,
      maxConnections: config.maxConnections,
    );
  }

  /// Отключить соединение
  void disconnect(String connectionId) {
    final connection = _connections.remove(connectionId);
    if (connection != null) {
      _connectionsByIp[connection.ip]?.remove(connectionId);
      if (_connectionsByIp[connection.ip]?.isEmpty ?? false) {
        _connectionsByIp.remove(connection.ip);
      }

      // Update active connections metric
      metrics?.setActiveConnections(_connections.length);
    }
  }

  /// Получить статистику
  ConnectionStats getStats() {
    final ipStats = <String, int>{};
    for (final entry in _connectionsByIp.entries) {
      ipStats[entry.key] = entry.value.length;
    }

    return ConnectionStats(
      totalConnections: _connections.length,
      connectionsByIp: ipStats,
      maxConnections: config.maxConnections,
      maxConnectionsPerIp: config.maxConnectionsPerIp,
    );
  }

  /// Получить соединения для IP
  List<ConnectionInfo> getConnectionsForIp(String ip) {
    final connectionIds = _connectionsByIp[ip] ?? {};
    return connectionIds
        .map((id) => _connections[id])
        .whereType<ConnectionInfo>()
        .toList();
  }

  /// Cleanup
  void _cleanup() {
    // Удалить старые соединения (> 5 минут)
    final maxAge = 300; // 5 минут

    final toRemove = <String>[];
    for (final entry in _connections.entries) {
      if (entry.value.duration > maxAge) {
        toRemove.add(entry.key);
      }
    }

    for (final id in toRemove) {
      disconnect(id);
    }
  }

  void _startCleanupTimer() {
    _cleanupTimer?.cancel();
    _cleanupTimer = Timer.periodic(
      Duration(seconds: config.cleanupIntervalSeconds),
      (_) => _cleanup(),
    );
  }

  void dispose() {
    _cleanupTimer?.cancel();
    _connections.clear();
    _connectionsByIp.clear();
  }

  static int _now() => DateTime.now().millisecondsSinceEpoch ~/ 1000;
}

/// Connection limit result
final class ConnectionLimitResult {
  const ConnectionLimitResult({
    required this.allowed,
    required this.reason,
    required this.currentConnections,
    required this.maxConnections,
  });

  final bool allowed;
  final String? reason;
  final int currentConnections;
  final int maxConnections;
}

/// Connection statistics
final class ConnectionStats {
  const ConnectionStats({
    required this.totalConnections,
    required this.connectionsByIp,
    required this.maxConnections,
    required this.maxConnectionsPerIp,
  });

  final int totalConnections;
  final Map<String, int> connectionsByIp;
  final int maxConnections;
  final int maxConnectionsPerIp;

  double get utilizationPercent =>
      maxConnections > 0 ? (totalConnections / maxConnections) * 100 : 0;
}
