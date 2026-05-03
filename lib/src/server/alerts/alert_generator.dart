// pkgs/aq_security/lib/src/server/alerts/alert_generator.dart
//
// Генератор оповещений безопасности на основе правил.

import 'package:aq_schema/aq_schema.dart';
import 'package:aq_schema/security/security.dart';
import 'alert_rules.dart';

/// Генератор оповещений безопасности.
/// Анализирует события доступа и генерирует оповещения по правилам.
class AlertGenerator {
  AlertGenerator({
    required this.alertRepository,
    List<AlertRule>? rules,
  }) : rules = rules ?? _defaultRules();

  /// Репозиторий для сохранения оповещений.
  final AlertRepository alertRepository;

  /// Правила генерации оповещений.
  final List<AlertRule> rules;

  /// История проверок доступа (для анализа паттернов).
  final Map<String, List<AccessCheck>> _checkHistory = {};

  /// История отказов (для обнаружения подозрительной активности).
  final Map<String, List<AccessDenial>> _denialHistory = {};

  /// Максимальный размер истории на пользователя.
  static const int _maxHistorySize = 1000;

  /// Время хранения истории (1 час).
  static const int _historyRetentionMs = 3600000;

  /// Создать правила по умолчанию.
  static List<AlertRule> _defaultRules() {
    return [
      SuspiciousActivityRule(),
      RateLimitRule(),
      PolicyViolationRule(),
      RoleExpiringRule(),
      PrivilegeEscalationRule(),
    ];
  }

  /// Обработать проверку доступа и сгенерировать оповещения при необходимости.
  Future<List<AccessAlert>> processAccessCheck({
    required String userId,
    required String resource,
    required String action,
    required String scope,
    required bool allowed,
    String? denialReason,
    List<AqUserRole>? userRoles,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;

    // Добавить в историю проверок
    _addToCheckHistory(
        userId,
        AccessCheck(
          timestamp: now,
          resource: resource,
          action: action,
        ));

    // Если отказ - добавить в историю отказов
    if (!allowed) {
      _addToDenialHistory(
          userId,
          AccessDenial(
            timestamp: now,
            resource: resource,
            reason: denialReason ?? 'Unknown',
          ));
    }

    // Очистить старую историю
    _cleanupHistory();

    // Проверить истекающие роли
    final expiringRoles = _findExpiringRoles(userRoles ?? []);

    // Создать контекст для правил
    final context = AlertContext(
      userId: userId,
      resource: resource,
      action: action,
      allowed: allowed,
      denialReason: denialReason,
      recentDenials: _denialHistory[userId] ?? [],
      recentChecks: _checkHistory[userId] ?? [],
      userRoles: userRoles ?? [],
      expiringRoles: expiringRoles,
    );

    // Проверить все правила и сгенерировать оповещения
    final alerts = <AccessAlert>[];
    for (final rule in rules) {
      if (rule.shouldAlert(context)) {
        final alert = rule.createAlert(context);
        alerts.add(alert);

        // Сохранить оповещение
        await alertRepository.save(alert);
      }
    }

    return alerts;
  }

  /// Добавить проверку в историю.
  void _addToCheckHistory(String userId, AccessCheck check) {
    _checkHistory.putIfAbsent(userId, () => []);
    _checkHistory[userId]!.add(check);

    // Ограничить размер истории
    if (_checkHistory[userId]!.length > _maxHistorySize) {
      _checkHistory[userId]!.removeAt(0);
    }
  }

  /// Добавить отказ в историю.
  void _addToDenialHistory(String userId, AccessDenial denial) {
    _denialHistory.putIfAbsent(userId, () => []);
    _denialHistory[userId]!.add(denial);

    // Ограничить размер истории
    if (_denialHistory[userId]!.length > _maxHistorySize) {
      _denialHistory[userId]!.removeAt(0);
    }
  }

  /// Очистить старую историю.
  void _cleanupHistory() {
    final now = DateTime.now().millisecondsSinceEpoch;
    final cutoff = now - _historyRetentionMs;

    // Очистить историю проверок
    for (final entry in _checkHistory.entries) {
      entry.value.removeWhere((check) => check.timestamp < cutoff);
    }
    _checkHistory.removeWhere((_, checks) => checks.isEmpty);

    // Очистить историю отказов
    for (final entry in _denialHistory.entries) {
      entry.value.removeWhere((denial) => denial.timestamp < cutoff);
    }
    _denialHistory.removeWhere((_, denials) => denials.isEmpty);
  }

  /// Найти роли, которые скоро истекут (в течение 1 часа).
  List<AqUserRole> _findExpiringRoles(List<AqUserRole> roles) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final threshold = now + 3600000; // +1 час

    return roles.where((role) {
      if (role.expiresAt == null) return false;
      return role.expiresAt! > now && role.expiresAt! <= threshold;
    }).toList();
  }

  /// Получить статистику по пользователю.
  UserAlertStats getUserStats(String userId) {
    final checks = _checkHistory[userId] ?? [];
    final denials = _denialHistory[userId] ?? [];

    final now = DateTime.now().millisecondsSinceEpoch;
    final lastMinute = now - 60000;

    final recentChecks = checks.where((c) => c.timestamp >= lastMinute).length;
    final recentDenials =
        denials.where((d) => d.timestamp >= lastMinute).length;

    return UserAlertStats(
      userId: userId,
      totalChecks: checks.length,
      totalDenials: denials.length,
      recentChecks: recentChecks,
      recentDenials: recentDenials,
    );
  }

  /// Получить все неподтверждённые оповещения.
  Future<List<AccessAlert>> getUnacknowledgedAlerts() async {
    return await alertRepository.getUnacknowledged();
  }

  /// Подтвердить оповещение.
  Future<void> acknowledgeAlert(String alertId, String resolvedBy) async {
    final alert = await alertRepository.getById(alertId);
    if (alert == null) return;

    final updated = alert.copyWith(
      resolved: true,
      resolvedBy: resolvedBy,
      resolvedAt: DateTime.now().millisecondsSinceEpoch,
    );

    await alertRepository.update(updated);
  }

  /// Получить оповещения за период.
  Future<List<AccessAlert>> getAlerts({
    required int startTime,
    required int endTime,
    AlertType? type,
    AlertSeverity? severity,
  }) async {
    return await alertRepository.getInRange(
      startTime: startTime,
      endTime: endTime,
      type: type,
      severity: severity,
    );
  }

  /// Очистить историю (для тестирования).
  void clearHistory() {
    _checkHistory.clear();
    _denialHistory.clear();
  }
}

/// Статистика оповещений пользователя.
class UserAlertStats {
  UserAlertStats({
    required this.userId,
    required this.totalChecks,
    required this.totalDenials,
    required this.recentChecks,
    required this.recentDenials,
  });

  final String userId;
  final int totalChecks;
  final int totalDenials;
  final int recentChecks;
  final int recentDenials;

  /// Есть ли подозрительная активность.
  bool get isSuspicious => recentDenials >= 10;

  /// Превышен ли лимит запросов.
  bool get isRateLimited => recentChecks >= 100;
}

/// Репозиторий оповещений (абстракция).
abstract class AlertRepository {
  /// Сохранить оповещение.
  Future<void> save(AccessAlert alert);

  /// Обновить оповещение.
  Future<void> update(AccessAlert alert);

  /// Получить оповещение по ID.
  Future<AccessAlert?> getById(String id);

  /// Получить все неподтверждённые оповещения.
  Future<List<AccessAlert>> getUnacknowledged();

  /// Получить оповещения за период.
  Future<List<AccessAlert>> getInRange({
    required int startTime,
    required int endTime,
    AlertType? type,
    AlertSeverity? severity,
  });

  /// Удалить старые оповещения.
  Future<void> deleteOlderThan(int timestamp);
}
