// pkgs/aq_security/lib/src/server/policy_engine.dart
//
// Server-only. Policy evaluation engine.
// Проверяет policies на основе контекста (время, IP, атрибуты).

import 'package:aq_schema/security/security.dart';

final class PolicyEngine {
  PolicyEngine({required this.repo});

  final IPolicyRepository repo;

  /// Evaluate policies для контекста
  Future<PolicyEvaluationResult> evaluate({
    required String tenantId,
    required PolicyContext context,
  }) async {
    // Получить активные policies для tenant
    final policies = await repo.findActive(tenantId);

    // Сортировать по приоритету (выше = первым)
    policies.sort((a, b) => b.priority.compareTo(a.priority));

    final matchedPolicies = <String>[];
    PolicyEffect? finalEffect;

    // Evaluate каждый policy
    for (final policy in policies) {
      final result = _evaluatePolicy(policy, context);

      if (result) {
        matchedPolicies.add(policy.id);

        // Первый matched policy определяет результат
        if (finalEffect == null) {
          // Проверить effect всех statements
          for (final statement in policy.statements) {
            if (_evaluateStatement(statement, context)) {
              finalEffect = statement.effect;
              break;
            }
          }
        }

        // Если нашли deny, сразу возвращаем deny (deny wins)
        if (finalEffect == PolicyEffect.deny) {
          return PolicyEvaluationResult.deny(
            reason: 'Denied by policy: ${policy.name}',
            matchedPolicies: matchedPolicies,
          );
        }
      }
    }

    // Если нашли allow, возвращаем allow
    if (finalEffect == PolicyEffect.allow) {
      return PolicyEvaluationResult.allow(matchedPolicies: matchedPolicies);
    }

    // По умолчанию deny (explicit deny)
    return PolicyEvaluationResult.deny(
      reason: 'No matching allow policy',
      matchedPolicies: matchedPolicies,
    );
  }

  /// Evaluate один policy
  bool _evaluatePolicy(AqPolicy policy, PolicyContext context) {
    if (!policy.isActive) return false;

    // Проверить хотя бы один statement
    for (final statement in policy.statements) {
      if (_evaluateStatement(statement, context)) {
        return true;
      }
    }

    return false;
  }

  /// Evaluate один statement
  bool _evaluateStatement(PolicyStatement statement, PolicyContext context) {
    if (statement.conditions.isEmpty) return true;

    final results = statement.conditions.map((c) => _evaluateCondition(c, context)).toList();

    switch (statement.logic) {
      case PolicyLogic.and:
        return results.every((r) => r);
      case PolicyLogic.or:
        return results.any((r) => r);
      case PolicyLogic.not:
        return !results.first;
    }
  }

  /// Evaluate одно условие
  bool _evaluateCondition(PolicyCondition condition, PolicyContext context) {
    switch (condition.type) {
      case PolicyConditionType.timeRange:
        return _evaluateTimeRange(condition, context);
      case PolicyConditionType.ipAddress:
        return _evaluateIpAddress(condition, context);
      case PolicyConditionType.userAttribute:
        return _evaluateUserAttribute(condition, context);
      case PolicyConditionType.resourceAttribute:
        return _evaluateResourceAttribute(condition, context);
      case PolicyConditionType.scope:
        return _evaluateScope(condition, context);
      case PolicyConditionType.role:
        return _evaluateRole(condition, context);
      case PolicyConditionType.custom:
        return false; // Custom conditions не поддерживаются пока
    }
  }

  bool _evaluateTimeRange(PolicyCondition condition, PolicyContext context) {
    final timestamp = context.timestamp ?? DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final range = condition.value as Map<String, dynamic>;
    final start = range['start'] as int?;
    final end = range['end'] as int?;

    if (start != null && timestamp < start) return false;
    if (end != null && timestamp > end) return false;

    return true;
  }

  bool _evaluateIpAddress(PolicyCondition condition, PolicyContext context) {
    if (context.ipAddress == null) return false;

    return _compareValues(
      context.ipAddress!,
      condition.value,
      condition.operator,
    );
  }

  bool _evaluateUserAttribute(PolicyCondition condition, PolicyContext context) {
    if (condition.field == null) return false;

    final value = context.userAttributes[condition.field];
    if (value == null) return false;

    return _compareValues(value, condition.value, condition.operator);
  }

  bool _evaluateResourceAttribute(PolicyCondition condition, PolicyContext context) {
    if (condition.field == null) return false;

    final value = context.resourceAttributes[condition.field];
    if (value == null) return false;

    return _compareValues(value, condition.value, condition.operator);
  }

  bool _evaluateScope(PolicyCondition condition, PolicyContext context) {
    final requiredScope = condition.value as String;
    return context.scopes.contains(requiredScope);
  }

  bool _evaluateRole(PolicyCondition condition, PolicyContext context) {
    final requiredRole = condition.value as String;
    return context.roles.contains(requiredRole);
  }

  bool _compareValues(dynamic actual, dynamic expected, PolicyOperator operator) {
    switch (operator) {
      case PolicyOperator.equals:
        return actual == expected;
      case PolicyOperator.notEquals:
        return actual != expected;
      case PolicyOperator.contains:
        return actual.toString().contains(expected.toString());
      case PolicyOperator.notContains:
        return !actual.toString().contains(expected.toString());
      case PolicyOperator.greaterThan:
        return _toNumber(actual) > _toNumber(expected);
      case PolicyOperator.lessThan:
        return _toNumber(actual) < _toNumber(expected);
      case PolicyOperator.inList:
        final list = expected as List;
        return list.contains(actual);
      case PolicyOperator.notInList:
        final list = expected as List;
        return !list.contains(actual);
      case PolicyOperator.matches:
        final regex = RegExp(expected.toString());
        return regex.hasMatch(actual.toString());
    }
  }

  num _toNumber(dynamic value) {
    if (value is num) return value;
    if (value is String) return num.parse(value);
    throw ArgumentError('Cannot convert $value to number');
  }
}
