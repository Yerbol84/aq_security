// pkgs/aq_security/lib/src/rbac/access_control_engine.dart
//
// Движок проверки доступа с поддержкой wildcards, иерархии и политик.

import 'package:aq_schema/aq_schema.dart';
import '../server/metrics/metrics_collector.dart';
import '../server/alerts/alert_generator.dart';

/// Движок проверки доступа (Access Control Engine).
/// Центральный компонент RBAC системы.
class AccessControlEngine {
  AccessControlEngine({
    required this.roleRepository,
    required this.userRoleRepository,
    required this.policyRepository,
    this.cache,
    this.metricsCollector,
    this.alertGenerator,
  });

  final IRoleRepository roleRepository;
  final IUserRoleRepository userRoleRepository;
  final IPolicyRepository policyRepository;

  /// Кэш решений о доступе (IAQCache).
  final IAQCache? cache;

  /// Сборщик метрик (опционально).
  final RbacMetricsCollector? metricsCollector;

  /// Генератор оповещений (опционально).
  final AlertGenerator? alertGenerator;

  /// Синхронная проверка доступа — всегда false без кэша.
  /// Используй [canAsync] для полной проверки.
  bool canSync(String userId, String permission) => false;

  /// Асинхронная проверка доступа (полная проверка с политиками).
  ///
  /// Формат permission: 'resource:action'.
  /// Scope передаётся через [context].userScopes — не встраивается в ключ.
  Future<AccessDecision> canAsync(
    String userId,
    String resource,
    String action, {
    String scope = '',
    AccessContext? context,
  }) async {
    final startTime = DateTime.now();
    bool fromCache = false;
    AccessDecision? decision;
    List<String>? roleIds;
    List<String>? effectivePermissionStrings;
    List<String>? appliedPolicyIds;

    try {
      // 1. Проверить кэш
      // Ключ кэша: 'resource:action' — scope не является частью permission key.
      final permission = '$resource:$action';
      final cacheKey = 'decision:$userId:$permission';
      if (cache != null) {
        final cached = await cache!.get<AccessDecision>(cacheKey);
        if (cached != null) {
          fromCache = true;
          decision = cached;
          return decision;
        }
      }

      // 2. Получить роли пользователя
      final userRoles = await userRoleRepository.getUserRoles(userId);
      roleIds = userRoles.map((r) => r.roleId).toList();

      if (userRoles.isEmpty) {
        decision = AccessDecision.deny(reason: 'User has no roles');
        _cacheDecision(userId, permission, decision);
        return decision;
      }

      // 3. Собрать все права (с учётом иерархии)
      final effectivePermissions = await _getEffectivePermissions(userRoles);
      effectivePermissionStrings =
          effectivePermissions.map((p) => p.toString()).toList();

      // 4. Проверить права (с wildcards)
      final requestedPermission = AqPermission(
        action: action,
        key: scope,
        resourceType: resource,
      );

      final hasPermission =
          _checkPermission(requestedPermission, effectivePermissions);
      if (!hasPermission) {
        decision = AccessDecision(
          allowed: false,
          reason: 'Permission denied: $permission',
          matchedPermissions: effectivePermissionStrings,
        );
        _cacheDecision(userId, permission, decision);
        return decision;
      }

      // 5. Применить политики
      if (context != null) {
        final policies = await policyRepository.getEnabledPolicies();
        final policyDecision = await _evaluatePolicies(policies, context);
        appliedPolicyIds = policyDecision.appliedPolicies;

        if (!policyDecision.allowed) {
          decision = policyDecision;
          _cacheDecision(userId, permission, decision);
          return decision;
        }
      }

      // 6. Доступ разрешён
      decision = AccessDecision.allow(
        reason: 'Access granted',
        matchedPermissions: effectivePermissionStrings,
        appliedPolicies: appliedPolicyIds,
      );
      _cacheDecision(userId, permission, decision);

      return decision;
    } finally {
      final duration = DateTime.now().difference(startTime);

      // Записать метрику
      if (decision != null) {
        metricsCollector?.recordCheck(
          userId: userId,
          resource: resource,
          action: action,
          scope: scope,
          allowed: decision.allowed,
          durationMs: duration.inMilliseconds,
          fromCache: fromCache,
          denialReason: decision.allowed ? null : decision.reason,
          roles: roleIds,
          permissions: effectivePermissionStrings,
          appliedPolicies: appliedPolicyIds,
        );

        // Генерировать оповещения
        alertGenerator?.processAccessCheck(
          userId: userId,
          resource: resource,
          action: action,
          scope: scope,
          allowed: decision.allowed,
          denialReason: decision.allowed ? null : decision.reason,
          userRoles: await userRoleRepository.getUserRoles(userId),
        );
      }
    }
  }

  /// Batch проверка нескольких прав.
  Future<Map<String, bool>> canBatch(
    String userId,
    List<String> permissions,
  ) async {
    final results = <String, bool>{};

    // Получаем роли один раз
    final userRoles = await userRoleRepository.getUserRoles(userId);
    if (userRoles.isEmpty) {
      return {for (final p in permissions) p: false};
    }

    // Получаем эффективные права один раз
    final effectivePermissions = await _getEffectivePermissions(userRoles);

    // Проверяем каждое право
    for (final permissionStr in permissions) {
      try {
        final permission = AqPermission.fromKey(permissionStr);
        results[permissionStr] =
            _checkPermission(permission, effectivePermissions);
      } catch (e) {
        results[permissionStr] = false;
      }
    }

    return results;
  }

  /// Получить все эффективные права пользователя.
  Future<List<String>> getEffectivePermissions(String userId) async {
    final userRoles = await userRoleRepository.getUserRoles(userId);
    if (userRoles.isEmpty) return [];

    final permissions = await _getEffectivePermissions(userRoles);
    return permissions.map((p) => p.toString()).toList();
  }

  /// Получить эффективные права с учётом иерархии ролей.
  Future<List<AqPermission>> _getEffectivePermissions(
      List<AqUserRole> userRoles) async {
    final allPermissions = <String>{};
    final processedRoles = <String>{};

    for (final userRole in userRoles) {
      // Пропустить истёкшие роли
      if (userRole.isExpired) continue;

      await _collectPermissionsRecursive(
        userRole.roleId,
        allPermissions,
        processedRoles,
      );
    }

    return allPermissions.map((p) => AqPermission.fromKey(p)).toList();
  }

  /// Рекурсивно собрать права роли и её родителей.
  Future<void> _collectPermissionsRecursive(
    String roleId,
    Set<String> permissions,
    Set<String> processedRoles, {
    int depth = 0,
  }) async {
    // Защита от циклов и глубокой рекурсии
    if (processedRoles.contains(roleId) || depth > 5) {
      return;
    }

    processedRoles.add(roleId);

    final role = await roleRepository.findById(roleId);
    if (role == null) return;

    // Добавить прямые права роли
    permissions.addAll(role.permissions);

    // Рекурсивно добавить права родительских ролей
    for (final parentRoleId in role.inheritsFrom) {
      await _collectPermissionsRecursive(
        parentRoleId,
        permissions,
        processedRoles,
        depth: depth + 1,
      );
    }
  }

  /// Проверить право с учётом wildcards.
  bool _checkPermission(
    AqPermission requested,
    List<AqPermission> available,
  ) {
    for (final permission in available) {
      if (permission.matches(requested.key)) {
        return true;
      }
    }
    return false;
  }

  /// Применить политики.
  Future<AccessDecision> _evaluatePolicies(
    List<AqAccessPolicy> policies,
    AccessContext context,
  ) async {
    // Сортировать по приоритету (больше = выше)
    policies.sort((a, b) => b.priority.compareTo(a.priority));

    final appliedPolicies = <String>[];

    for (final policy in policies) {
      // Проверяем каждый statement в политике
      for (final statement in policy.statements) {
        final matches =
            await _evaluatePolicyConditions(statement.conditions, context);
        if (matches) {
          appliedPolicies.add(policy.id);

          if (statement.effect == PolicyEffect.deny) {
            return AccessDecision.deny(
              reason: 'Denied by policy: ${policy.name}',
              appliedPolicies: appliedPolicies,
            );
          }
        }
      }
    }

    return AccessDecision.allow(
      appliedPolicies: appliedPolicies,
    );
  }

  /// Проверить условия политики.
  Future<bool> _evaluatePolicyConditions(
    List<PolicyCondition> conditions,
    AccessContext context,
  ) async {
    for (final condition in conditions) {
      final matches = await _evaluateCondition(condition, context);
      if (!matches) return false;
    }
    return true;
  }

  /// Проверить одно условие.
  Future<bool> _evaluateCondition(
    PolicyCondition condition,
    AccessContext context,
  ) async {
    switch (condition.type) {
      case PolicyConditionType.timeRange:
        return _evaluateTimeRangeCondition(condition, context);
      case PolicyConditionType.ipAddress:
        return _evaluateIpAddressCondition(condition, context);
      case PolicyConditionType.userAttribute:
        return _evaluateUserAttributeCondition(condition, context);
      case PolicyConditionType.resourceAttribute:
        return _evaluateResourceAttributeCondition(condition, context);
      case PolicyConditionType.scope:
        return _evaluateScopeCondition(condition, context);
      case PolicyConditionType.role:
        return _evaluateRoleCondition(condition, context);
      case PolicyConditionType.custom:
        return true; // Custom conditions not implemented yet
    }
  }

  bool _evaluateTimeRangeCondition(
      PolicyCondition condition, AccessContext context) {
    final now = DateTime.fromMillisecondsSinceEpoch(
        context.effectiveTimestamp * 1000);

    switch (condition.operator) {
      case PolicyOperator.inList:
        // value - список дней недели [1,2,3,4,5]
        final allowedDays = (condition.value as List).cast<int>();
        return allowedDays.contains(now.weekday);

      case PolicyOperator.greaterThan:
        // value - час начала (для проверки рабочих часов)
        final startHour = condition.value as int;
        return now.hour >= startHour;

      case PolicyOperator.lessThan:
        // value - час окончания
        final endHour = condition.value as int;
        return now.hour < endHour;

      default:
        return true;
    }
  }

  bool _evaluateIpAddressCondition(
      PolicyCondition condition, AccessContext context) {
    if (context.ipAddress == null) return false;

    switch (condition.operator) {
      case PolicyOperator.inList:
        // Whitelist
        final whitelist = (condition.value as List).cast<String>();
        return whitelist.contains(context.ipAddress);

      case PolicyOperator.notInList:
        // Blacklist
        final blacklist = (condition.value as List).cast<String>();
        return !blacklist.contains(context.ipAddress);

      case PolicyOperator.equals:
        return context.ipAddress == condition.value;

      case PolicyOperator.notEquals:
        return context.ipAddress != condition.value;

      default:
        return true;
    }
  }

  bool _evaluateUserAttributeCondition(
      PolicyCondition condition, AccessContext context) {
    final field = condition.field;
    if (field == null) return false;

    // Специальная обработка для mfaVerified
    if (field == 'mfaVerified') {
      final required = condition.value as bool? ?? false;
      return condition.operator == PolicyOperator.equals
          ? context.mfaVerified == required
          : context.mfaVerified != required;
    }

    // Общая обработка атрибутов пользователя
    final attributeValue = context.userAttributes[field];
    return _evaluateOperator(condition.operator, attributeValue, condition.value);
  }

  bool _evaluateResourceAttributeCondition(
      PolicyCondition condition, AccessContext context) {
    final field = condition.field;
    if (field == null) return false;

    final attributeValue = context.resourceAttributes[field];
    return _evaluateOperator(condition.operator, attributeValue, condition.value);
  }

  bool _evaluateScopeCondition(
      PolicyCondition condition, AccessContext context) {
    switch (condition.operator) {
      case PolicyOperator.inList:
        final requiredScopes = (condition.value as List).cast<String>();
        return requiredScopes.any((scope) => context.userScopes.contains(scope));

      case PolicyOperator.contains:
        return context.userScopes.contains(condition.value as String);

      default:
        return true;
    }
  }

  bool _evaluateRoleCondition(
      PolicyCondition condition, AccessContext context) {
    switch (condition.operator) {
      case PolicyOperator.inList:
        final requiredRoles = (condition.value as List).cast<String>();
        return requiredRoles.any((role) => context.userRoles.contains(role));

      case PolicyOperator.contains:
        return context.userRoles.contains(condition.value as String);

      default:
        return true;
    }
  }

  /// Универсальный метод для оценки операторов
  bool _evaluateOperator(PolicyOperator operator, dynamic actual, dynamic expected) {
    switch (operator) {
      case PolicyOperator.equals:
        return actual == expected;

      case PolicyOperator.notEquals:
        return actual != expected;

      case PolicyOperator.contains:
        if (actual is String && expected is String) {
          return actual.contains(expected);
        }
        if (actual is List) {
          return actual.contains(expected);
        }
        return false;

      case PolicyOperator.notContains:
        if (actual is String && expected is String) {
          return !actual.contains(expected);
        }
        if (actual is List) {
          return !actual.contains(expected);
        }
        return true;

      case PolicyOperator.greaterThan:
        if (actual is num && expected is num) {
          return actual > expected;
        }
        return false;

      case PolicyOperator.lessThan:
        if (actual is num && expected is num) {
          return actual < expected;
        }
        return false;

      case PolicyOperator.inList:
        if (expected is List) {
          return expected.contains(actual);
        }
        return false;

      case PolicyOperator.notInList:
        if (expected is List) {
          return !expected.contains(actual);
        }
        return true;

      case PolicyOperator.matches:
        if (actual is String && expected is String) {
          try {
            final regex = RegExp(expected);
            return regex.hasMatch(actual);
          } catch (e) {
            return false;
          }
        }
        return false;
    }
  }

  void _cacheDecision(
      String userId, String permission, AccessDecision decision) {
    if (cache == null) return;
    final cacheable = AccessDecision.withCacheKey(
      userId: userId,
      permission: permission,
      allowed: decision.allowed,
      reason: decision.reason,
      matchedRoles: decision.matchedRoles,
      matchedPermissions: decision.matchedPermissions,
      appliedPolicies: decision.appliedPolicies,
      evaluationTimeMs: decision.evaluationTimeMs,
    );
    cache!.put(cacheable);
  }

  /// Инвалидировать весь кэш.
  void invalidateAllCache() {
    cache?.clear();
  }

  /// Инвалидировать кэш для конкретного пользователя.
  /// IAQCache не поддерживает wildcard evict — очищаем весь кэш.
  void invalidateUser(String userId) {
    cache?.clear();
  }
}




