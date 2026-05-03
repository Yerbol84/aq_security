// pkgs/aq_security/lib/src/server/dos_protection/ip_blacklist.dart
//
// Server-only. IP blacklist для блокировки вредоносных IP.

import 'dart:async';
import '../monitoring/metrics.dart';

/// IP blacklist entry
final class BlacklistEntry {
  BlacklistEntry({
    required this.ip,
    required this.reason,
    required this.addedAt,
    this.expiresAt,
  });

  final String ip;
  final String reason;
  final int addedAt;
  final int? expiresAt;

  bool get isExpired {
    if (expiresAt == null) return false;
    return DateTime.now().millisecondsSinceEpoch ~/ 1000 >= expiresAt!;
  }

  int get duration => _now() - addedAt;

  static int _now() => DateTime.now().millisecondsSinceEpoch ~/ 1000;
}

/// IP blacklist configuration
final class IpBlacklistConfig {
  const IpBlacklistConfig({
    this.defaultBanDuration = 3600, // 1 час
    this.cleanupIntervalSeconds = 300, // 5 минут
  });

  final int defaultBanDuration;
  final int cleanupIntervalSeconds;
}

/// IP blacklist
final class IpBlacklist {
  IpBlacklist({
    required this.config,
    this.metrics,
  }) {
    _startCleanupTimer();
  }

  final IpBlacklistConfig config;
  final SecurityMetrics? metrics;
  final Map<String, BlacklistEntry> _blacklist = {};
  Timer? _cleanupTimer;

  /// Проверить, заблокирован ли IP
  bool isBlocked(String ip) {
    final entry = _blacklist[ip];
    if (entry == null) return false;

    if (entry.isExpired) {
      _blacklist.remove(ip);
      return false;
    }

    return true;
  }

  /// Заблокировать IP
  void block({
    required String ip,
    required String reason,
    int? durationSeconds,
  }) {
    final duration = durationSeconds ?? config.defaultBanDuration;
    final now = _now();

    final entry = BlacklistEntry(
      ip: ip,
      reason: reason,
      addedAt: now,
      expiresAt: now + duration,
    );

    _blacklist[ip] = entry;

    // Record blocked IP
    metrics?.recordIpBlocked(reason: reason);
  }

  /// Заблокировать IP навсегда
  void blockPermanent({
    required String ip,
    required String reason,
  }) {
    final entry = BlacklistEntry(
      ip: ip,
      reason: reason,
      addedAt: _now(),
      expiresAt: null,
    );

    _blacklist[ip] = entry;

    // Record blocked IP
    metrics?.recordIpBlocked(reason: reason);
  }

  /// Разблокировать IP
  void unblock(String ip) {
    _blacklist.remove(ip);
  }

  /// Получить entry для IP
  BlacklistEntry? getEntry(String ip) {
    final entry = _blacklist[ip];
    if (entry == null) return null;

    if (entry.isExpired) {
      _blacklist.remove(ip);
      return null;
    }

    return entry;
  }

  /// Получить все заблокированные IP
  List<BlacklistEntry> getAll() {
    return _blacklist.values.where((e) => !e.isExpired).toList();
  }

  /// Очистить все
  void clear() {
    _blacklist.clear();
  }

  /// Cleanup expired entries
  void _cleanup() {
    final toRemove = <String>[];

    for (final entry in _blacklist.entries) {
      if (entry.value.isExpired) {
        toRemove.add(entry.key);
      }
    }

    for (final ip in toRemove) {
      _blacklist.remove(ip);
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
    _blacklist.clear();
  }

  static int _now() => DateTime.now().millisecondsSinceEpoch ~/ 1000;
}

/// Threat detector для автоматической блокировки
final class ThreatDetector {
  ThreatDetector({
    required this.blacklist,
    this.maxFailedAttempts = 10,
    this.failedAttemptsWindow = 60, // 1 минута
    this.banDuration = 3600, // 1 час
  });

  final IpBlacklist blacklist;
  final int maxFailedAttempts;
  final int failedAttemptsWindow;
  final int banDuration;

  final Map<String, List<int>> _failedAttempts = {};

  /// Зарегистрировать failed attempt
  void recordFailedAttempt(String ip, String reason) {
    final now = _now();

    // Получить attempts для IP
    final attempts = _failedAttempts.putIfAbsent(ip, () => []);

    // Удалить старые attempts (вне окна)
    attempts.removeWhere((timestamp) => now - timestamp > failedAttemptsWindow);

    // Добавить новый attempt
    attempts.add(now);

    // Проверить, превышен ли лимит
    if (attempts.length >= maxFailedAttempts) {
      // Заблокировать IP
      blacklist.block(
        ip: ip,
        reason: 'Too many failed attempts: $reason',
        durationSeconds: banDuration,
      );

      // Очистить attempts
      _failedAttempts.remove(ip);
    }
  }

  /// Очистить attempts для IP
  void clearAttempts(String ip) {
    _failedAttempts.remove(ip);
  }

  /// Получить количество attempts для IP
  int getAttempts(String ip) {
    final now = _now();
    final attempts = _failedAttempts[ip] ?? [];

    // Удалить старые
    attempts.removeWhere((timestamp) => now - timestamp > failedAttemptsWindow);

    return attempts.length;
  }

  static int _now() => DateTime.now().millisecondsSinceEpoch ~/ 1000;
}
