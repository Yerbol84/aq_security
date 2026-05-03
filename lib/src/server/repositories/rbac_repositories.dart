// pkgs/aq_security/lib/src/server/repositories/rbac_repositories.dart
//
// ⚠️ THIN WRAPPERS - НЕ ДОБАВЛЯТЬ БИЗНЕС-ЛОГИКУ!
//
// Реализации репозиториев RBAC через Vault.
// Это тонкие обёртки над VaultStorage для удобства API.
//
// ЗАПРЕЩЕНО добавлять сюда бизнес-логику, валидацию, вычисления.
// Только простые CRUD операции через VaultQuery.

import 'package:aq_schema/aq_schema.dart';
import '../../rbac/access_control_engine.dart';
import '../metrics/metrics_aggregator.dart';
import '../alerts/alert_generator.dart';

/// Репозиторий ролей через Vault (для RBAC).
class RBACVaultRoleRepository implements RoleRepository {
  RBACVaultRoleRepository(this.vault);

  final dynamic vault; // VaultStorage

  @override
  Future<AqRole?> getRole(String roleId) async {
    try {
      final data = await vault.findById(AqRole.kCollection, roleId);
      if (data == null) return null;
      return AqRole.fromJson(data);
    } catch (e) {
      return null;
    }
  }

  @override
  Future<List<AqRole>> getAllRoles() async {
    final results = await vault.query(
      AqRole.kCollection,
      VaultQuery(filters: []),
    );
    return results.map((data) => AqRole.fromJson(data)).toList();
  }

  @override
  Future<void> saveRole(AqRole role) async {
    await vault.save(AqRole.kCollection, role.id, role.toJson());
  }

  @override
  Future<void> deleteRole(String roleId) async {
    await vault.delete(AqRole.kCollection, roleId);
  }

  /// Получить роли по tenant.
  Future<List<AqRole>> getRolesByTenant(String tenantId) async {
    final results = await vault.query(
      AqRole.kCollection,
      VaultQuery().where('tenantId', VaultOperator.equals, tenantId),
    );
    return results.map((data) => AqRole.fromJson(data)).toList();
  }
}

/// Репозиторий назначений ролей через Vault.
class VaultUserRoleRepository implements UserRoleRepository {
  VaultUserRoleRepository(this.vault);

  final dynamic vault;

  @override
  Future<List<AqUserRole>> getUserRoles(String userId) async {
    final results = await vault.query(
      AqUserRole.kCollection,
      VaultQuery().where('userId', VaultOperator.equals, userId),
    );

    final roles = results.map((data) => AqUserRole.fromJson(data)).toList();

    // Фильтровать истёкшие роли
    return roles.where((role) => !role.isExpired).toList();
  }

  @override
  Future<void> assignRole(AqUserRole userRole) async {
    await vault.save(
        AqUserRole.kCollection, userRole.roleId, userRole.toJson());
  }

  @override
  Future<void> revokeRole(String userId, String roleId) async {
    // Найти назначение
    final results = await vault.query(
      AqUserRole.kCollection,
      VaultQuery()
          .where('userId', VaultOperator.equals, userId)
          .where('roleId', VaultOperator.equals, roleId),
    );

    // Удалить все найденные назначения
    for (final data in results) {
      final userRole = AqUserRole.fromJson(data);
      await vault.delete(AqUserRole.kCollection, userRole.roleId);
    }
  }

  /// Получить все назначения роли.
  Future<List<AqUserRole>> getRoleAssignments(String roleId) async {
    final results = await vault.query(
      AqUserRole.kCollection,
      VaultQuery().where('roleId', VaultOperator.equals, roleId),
    );
    return results.map((data) => AqUserRole.fromJson(data)).toList();
  }

  /// Получить временные роли, которые скоро истекут.
  Future<List<AqUserRole>> getExpiringRoles(Duration threshold) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final thresholdTime = DateTime.now().add(threshold).millisecondsSinceEpoch;

    final results = await vault.query(
      AqUserRole.kCollection,
      VaultQuery()
          .where('expiresAt', VaultOperator.greaterThan, now)
          .where('expiresAt', VaultOperator.lessThan, thresholdTime),
    );
    return results.map((data) => AqUserRole.fromJson(data)).toList();
  }
}

/// Репозиторий политик через Vault.
class VaultPolicyRepository implements PolicyRepository {
  VaultPolicyRepository(this.vault);

  final dynamic vault;

  @override
  Future<List<AqAccessPolicy>> getEnabledPolicies() async {
    final results = await vault.query(
      AqAccessPolicy.kCollection,
      VaultQuery().where('enabled', VaultOperator.equals, true),
    );
    return results.map((data) => AqAccessPolicy.fromJson(data)).toList();
  }

  @override
  Future<AqAccessPolicy?> getPolicy(String policyId) async {
    try {
      final data = await vault.findById(AqAccessPolicy.kCollection, policyId);
      if (data == null) return null;
      return AqAccessPolicy.fromJson(data);
    } catch (e) {
      return null;
    }
  }

  @override
  Future<void> savePolicy(AqAccessPolicy policy) async {
    await vault.save(AqAccessPolicy.kCollection, policy.id, policy.toJson());
  }

  @override
  Future<void> deletePolicy(String policyId) async {
    await vault.delete(AqAccessPolicy.kCollection, policyId);
  }

  /// Получить все политики.
  Future<List<AqAccessPolicy>> getAllPolicies() async {
    final results = await vault.query(
      AqAccessPolicy.kCollection,
      const VaultQuery(),
    );
    return results.map((data) => AqAccessPolicy.fromJson(data)).toList();
  }

  /// Получить политики по tenant.
  Future<List<AqAccessPolicy>> getPoliciesByTenant(String tenantId) async {
    final results = await vault.query(
      AqAccessPolicy.kCollection,
      VaultQuery().where('tenantId', VaultOperator.equals, tenantId),
    );
    return results.map((data) => AqAccessPolicy.fromJson(data)).toList();
  }
}

/// Репозиторий логов доступа (интерфейс).
abstract class AccessLogRepository {
  Future<void> saveLog(AqAccessLog log);
  Future<List<AqAccessLog>> getLogs({
    String? userId,
    String? resource,
    int? limit,
    int? offset,
  });
}

/// Репозиторий логов доступа через Vault.
class VaultAccessLogRepository implements AccessLogRepository {
  VaultAccessLogRepository(this.vault);

  final dynamic vault;

  @override
  Future<void> saveLog(AqAccessLog log) async {
    await vault.save(AqAccessLog.kCollection, log.id, log.toJson());
  }

  @override
  Future<List<AqAccessLog>> getLogs({
    String? userId,
    String? resource,
    int? limit,
    int? offset,
  }) async {
    var query = const VaultQuery();

    if (userId != null) {
      query = query.where('userId', VaultOperator.equals, userId);
    }

    if (resource != null) {
      query = query.where('resource', VaultOperator.equals, resource);
    }

    query = query.orderBy('timestamp', descending: true);

    if (limit != null) {
      query = query.withLimit(limit);
    }

    if (offset != null) {
      query = query.withOffset(offset);
    }

    final results = await vault.query(AqAccessLog.kCollection, query);
    return results.map((data) => AqAccessLog.fromJson(data)).toList();
  }

  /// Получить логи за период.
  Future<List<AqAccessLog>> getLogsByPeriod({
    required int startTime,
    required int endTime,
    int? limit,
  }) async {
    var query = VaultQuery()
        .where('timestamp', VaultOperator.greaterOrEqual, startTime)
        .where('timestamp', VaultOperator.lessOrEqual, endTime)
        .orderBy('timestamp', descending: true);

    if (limit != null) {
      query = query.withLimit(limit);
    }

    final results = await vault.query(AqAccessLog.kCollection, query);
    return results.map((data) => AqAccessLog.fromJson(data)).toList();
  }

  /// Получить отказы в доступе.
  Future<List<AqAccessLog>> getDenials({
    String? userId,
    int? limit,
  }) async {
    var query = VaultQuery().where('allowed', VaultOperator.equals, false);

    if (userId != null) {
      query = query.where('userId', VaultOperator.equals, userId);
    }

    query = query.orderBy('timestamp', descending: true);

    if (limit != null) {
      query = query.withLimit(limit);
    }

    final results = await vault.query(AqAccessLog.kCollection, query);
    return results.map((data) => AqAccessLog.fromJson(data)).toList();
  }
}

/// Репозиторий оповещений через Vault.
class VaultAlertRepository {
  VaultAlertRepository(this.vault);

  final dynamic vault;

  Future<void> saveAlert(AccessAlert alert) async {
    await vault.save(AccessAlert.kCollection, alert.id, alert.toJson());
  }

  Future<List<AccessAlert>> getAlerts({
    String? userId,
    AlertSeverity? severity,
    bool? acknowledged,
    int? limit,
  }) async {
    var query = const VaultQuery();

    if (userId != null) {
      query = query.where('userId', VaultOperator.equals, userId);
    }

    if (severity != null) {
      query = query.where('severity', VaultOperator.equals, severity.name);
    }

    if (acknowledged != null) {
      query = query.where('acknowledged', VaultOperator.equals, acknowledged);
    }

    query = query.orderBy('timestamp', descending: true);

    if (limit != null) {
      query = query.withLimit(limit);
    }

    final results = await vault.query(AccessAlert.kCollection, query);
    return results.map((data) => AccessAlert.fromJson(data)).toList();
  }

  Future<void> acknowledgeAlert(String alertId, String acknowledgedBy) async {
    final data = await vault.findById(AccessAlert.kCollection, alertId);
    if (data == null) return;

    final alert = AccessAlert.fromJson(data);
    final updated = alert.copyWith(
      resolved: true,
      resolvedBy: acknowledgedBy,
      resolvedAt: DateTime.now().millisecondsSinceEpoch,
    );

    await vault.save(AccessAlert.kCollection, alertId, updated.toJson());
  }

  Future<int> getUnacknowledgedCount() async {
    final results = await vault.query(
      AccessAlert.kCollection,
      VaultQuery().where('resolved', VaultOperator.equals, false),
    );
    return results.length;
  }
}

/// Репозиторий метрик через Vault (реализация MetricsRepository).
class VaultMetricsRepository implements MetricsRepository {
  VaultMetricsRepository(this.vault);

  final dynamic vault;

  static const String kCollection = 'rbac_metrics';

  @override
  Future<void> save(RBACMetrics metrics) async {
    final id = 'metrics_${metrics.timestamp}';
    await vault.save(kCollection, id, metrics.toJson());
  }

  @override
  Future<List<RBACMetrics>> getMetricsInRange(
      int startTime, int endTime) async {
    final results = await vault.query(
      kCollection,
      VaultQuery()
          .where('timestamp', VaultOperator.greaterOrEqual, startTime)
          .where('timestamp', VaultOperator.lessOrEqual, endTime)
          .orderBy('timestamp', descending: false),
    );

    return results.map((data) => RBACMetrics.fromJson(data)).toList();
  }

  @override
  Future<void> deleteOlderThan(int timestamp) async {
    final results = await vault.query(
      kCollection,
      VaultQuery().where('periodEnd', VaultOperator.lessThan, timestamp),
    );

    for (final data in results) {
      final id = 'metrics_${data['periodStart']}';
      await vault.delete(kCollection, id);
    }
  }

  /// Получить последние метрики.
  Future<RBACMetrics?> getLatest() async {
    final results = await vault.query(
      kCollection,
      VaultQuery().orderBy('periodEnd', descending: true).withLimit(1),
    );

    if (results.isEmpty) return null;
    return RBACMetrics.fromJson(results.first);
  }
}

/// Репозиторий оповещений через Vault (реализация AlertRepository).
class VaultAlertRepositoryImpl implements AlertRepository {
  VaultAlertRepositoryImpl(this.vault);

  final dynamic vault;

  @override
  Future<void> save(AccessAlert alert) async {
    await vault.save(AccessAlert.kCollection, alert.id, alert.toJson());
  }

  @override
  Future<void> update(AccessAlert alert) async {
    await vault.save(AccessAlert.kCollection, alert.id, alert.toJson());
  }

  @override
  Future<AccessAlert?> getById(String id) async {
    try {
      final data = await vault.findById(AccessAlert.kCollection, id);
      if (data == null) return null;
      return AccessAlert.fromJson(data);
    } catch (e) {
      return null;
    }
  }

  @override
  Future<List<AccessAlert>> getUnacknowledged() async {
    final results = await vault.query(
      AccessAlert.kCollection,
      VaultQuery()
          .where('acknowledged', VaultOperator.equals, false)
          .orderBy('timestamp', descending: true),
    );

    return results.map((data) => AccessAlert.fromJson(data)).toList();
  }

  @override
  Future<List<AccessAlert>> getInRange({
    required int startTime,
    required int endTime,
    AlertType? type,
    AlertSeverity? severity,
  }) async {
    var query = VaultQuery()
        .where('timestamp', VaultOperator.greaterOrEqual, startTime)
        .where('timestamp', VaultOperator.lessOrEqual, endTime);

    if (type != null) {
      query = query.where('type', VaultOperator.equals, type.name);
    }

    if (severity != null) {
      query = query.where('severity', VaultOperator.equals, severity.name);
    }

    query = query.orderBy('timestamp', descending: true);

    final results = await vault.query(AccessAlert.kCollection, query);
    return results.map((data) => AccessAlert.fromJson(data)).toList();
  }

  @override
  Future<void> deleteOlderThan(int timestamp) async {
    final results = await vault.query(
      AccessAlert.kCollection,
      VaultQuery().where('timestamp', VaultOperator.lessThan, timestamp),
    );

    for (final data in results) {
      final alert = AccessAlert.fromJson(data);
      await vault.delete(AccessAlert.kCollection, alert.id);
    }
  }
}
