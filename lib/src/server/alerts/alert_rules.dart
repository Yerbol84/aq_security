// pkgs/aq_security/lib/src/server/alerts/alert_rules.dart
//
// Правила генерации оповещений безопасности.

import 'package:aq_schema/aq_schema.dart';
import 'package:uuid/uuid.dart';

/// Генератор уникальных ID для оповещений.
final _uuid = Uuid();

String _generateId() => _uuid.v4();

/// Базовый класс для правила оповещения.
abstract class AlertRule {
  /// Проверить, должно ли быть создано оповещение.
  bool shouldAlert(AlertContext context);

  /// Создать оповещение.
  AccessAlert createAlert(AlertContext context);
}

/// Контекст для проверки правил оповещений.
class AlertContext {
  AlertContext({
    required this.userId,
    required this.resource,
    required this.action,
    required this.allowed,
    this.denialReason,
    this.recentDenials = const [],
    this.recentChecks = const [],
    this.userRoles = const [],
    this.expiringRoles = const [],
  });

  final String userId;
  final String resource;
  final String action;
  final bool allowed;
  final String? denialReason;
  final List<AccessDenial> recentDenials;
  final List<AccessCheck> recentChecks;
  final List<AqUserRole> userRoles;
  final List<AqUserRole> expiringRoles;
}

/// Информация об отказе в доступе.
class AccessDenial {
  AccessDenial({
    required this.timestamp,
    required this.resource,
    required this.reason,
  });

  final int timestamp;
  final String resource;
  final String reason;
}

/// Информация о проверке доступа.
class AccessCheck {
  AccessCheck({
    required this.timestamp,
    required this.resource,
    required this.action,
  });

  final int timestamp;
  final String resource;
  final String action;
}

/// Правило: Подозрительная активность (10+ отказов за 1 минуту).
class SuspiciousActivityRule extends AlertRule {
  SuspiciousActivityRule({
    this.denialThreshold = 10,
    this.timeWindowMs = 60000, // 1 минута
  });

  final int denialThreshold;
  final int timeWindowMs;

  @override
  bool shouldAlert(AlertContext context) {
    if (context.allowed) return false;

    final now = DateTime.now().millisecondsSinceEpoch;
    final cutoff = now - timeWindowMs;

    final recentDenials =
        context.recentDenials.where((d) => d.timestamp >= cutoff).length;

    return recentDenials >= denialThreshold;
  }

  @override
  AccessAlert createAlert(AlertContext context) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final cutoff = now - timeWindowMs;
    final denialCount =
        context.recentDenials.where((d) => d.timestamp >= cutoff).length;

    return AccessAlert(
      id: _generateId(),
      type: AlertType.suspiciousActivity,
      severity: AlertSeverity.high,
      title: 'Подозрительная активность',
      description:
          'Подозрительная активность: $denialCount отказов в доступе за последнюю минуту',
      userId: context.userId,
      userEmail: 'unknown@example.com', // TODO: получать из контекста
      tenantId: 'unknown', // TODO: получать из контекста
      resource: context.resource,
      timestamp: now,
    );
  }
}

/// Правило: Превышение лимита запросов (100+ проверок за 1 минуту).
class RateLimitRule extends AlertRule {
  RateLimitRule({
    this.checkThreshold = 100,
    this.timeWindowMs = 60000, // 1 минута
  });

  final int checkThreshold;
  final int timeWindowMs;

  @override
  bool shouldAlert(AlertContext context) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final cutoff = now - timeWindowMs;

    final recentChecks =
        context.recentChecks.where((c) => c.timestamp >= cutoff).length;

    return recentChecks >= checkThreshold;
  }

  @override
  AccessAlert createAlert(AlertContext context) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final cutoff = now - timeWindowMs;
    final checkCount =
        context.recentChecks.where((c) => c.timestamp >= cutoff).length;

    return AccessAlert(
      id: _generateId(),
      type: AlertType.rateLimit,
      severity: AlertSeverity.medium,
      title: 'Превышен лимит запросов',
      description:
          'Превышен лимит запросов: $checkCount проверок за последнюю минуту',
      userId: context.userId,
      userEmail: 'unknown@example.com',
      tenantId: 'unknown',
      resource: context.resource,
      timestamp: now,
    );
  }
}

/// Правило: Нарушение политики доступа.
class PolicyViolationRule extends AlertRule {
  PolicyViolationRule({
    this.criticalResources = const ['users', 'roles', 'policies'],
  });

  final List<String> criticalResources;

  @override
  bool shouldAlert(AlertContext context) {
    if (context.allowed) return false;
    if (context.denialReason == null) return false;

    // Проверяем, связан ли отказ с политикой
    final isPolicyDenial =
        context.denialReason!.toLowerCase().contains('policy');

    // Проверяем, критичный ли ресурс
    final isCriticalResource = criticalResources.contains(context.resource);

    return isPolicyDenial || isCriticalResource;
  }

  @override
  AccessAlert createAlert(AlertContext context) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final isCritical = criticalResources.contains(context.resource);

    return AccessAlert(
      id: _generateId(),
      type: AlertType.policyViolation,
      severity: isCritical ? AlertSeverity.high : AlertSeverity.medium,
      title: 'Нарушение политики доступа',
      description:
          'Нарушение политики доступа: ${context.denialReason ?? "неизвестная причина"}',
      userId: context.userId,
      userEmail: 'unknown@example.com',
      tenantId: 'unknown',
      resource: context.resource,
      timestamp: now,
    );
  }
}

/// Правило: Истекающая временная роль (истекает через 1 час).
class RoleExpiringRule extends AlertRule {
  RoleExpiringRule({
    this.warningThresholdMs = 3600000, // 1 час
  });

  final int warningThresholdMs;

  @override
  bool shouldAlert(AlertContext context) {
    return context.expiringRoles.isNotEmpty;
  }

  @override
  AccessAlert createAlert(AlertContext context) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final expiringRole = context.expiringRoles.first;
    final timeLeft = expiringRole.expiresAt! - now;
    final minutesLeft = (timeLeft / 60000).round();

    return AccessAlert(
      id: _generateId(),
      type: AlertType.roleExpiring,
      severity: AlertSeverity.low,
      title: 'Истекающая временная роль',
      description:
          'Временная роль "${expiringRole.roleId}" истекает через $minutesLeft минут',
      userId: context.userId,
      userEmail: 'unknown@example.com',
      tenantId: 'unknown',
      resource: 'roles',
      timestamp: now,
    );
  }
}

/// Правило: Эскалация привилегий (попытка получить права администратора).
class PrivilegeEscalationRule extends AlertRule {
  PrivilegeEscalationRule({
    this.adminResources = const ['users', 'roles', 'policies', 'system'],
    this.adminActions = const ['create', 'delete', 'update'],
  });

  final List<String> adminResources;
  final List<String> adminActions;

  @override
  bool shouldAlert(AlertContext context) {
    if (context.allowed) return false;

    final isAdminResource = adminResources.contains(context.resource);
    final isAdminAction = adminActions.contains(context.action);

    // Проверяем, есть ли у пользователя хотя бы одна роль
    final hasRoles = context.userRoles.isNotEmpty;

    // Оповещение, если пользователь с ролями пытается получить админские права
    return isAdminResource && isAdminAction && hasRoles;
  }

  @override
  AccessAlert createAlert(AlertContext context) {
    final now = DateTime.now().millisecondsSinceEpoch;

    return AccessAlert(
      id: _generateId(),
      type: AlertType.privilegeEscalation,
      severity: AlertSeverity.critical,
      title: 'Попытка эскалации привилегий',
      description:
          'Попытка эскалации привилегий: ${context.action} на ${context.resource}',
      userId: context.userId,
      userEmail: 'unknown@example.com',
      tenantId: 'unknown',
      resource: context.resource,
      timestamp: now,
    );
  }
}
