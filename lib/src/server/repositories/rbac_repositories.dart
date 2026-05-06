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
import 'package:aq_schema/security/security.dart';
import '../metrics/metrics_aggregator.dart';
import '../alerts/alert_generator.dart';

/// Репозиторий назначений ролей через Vault.
class VaultUserRoleRepository implements IUserRoleRepository {
  VaultUserRoleRepository(this._repo);

  final DirectRepository<StorableAqUserRole> _repo;

  @override
  Future<List<AqUserRole>> getUserRoles(String userId) async {
    final r = await _repo.findAll(
      query: VaultQuery().where('userId', VaultOperator.equals, userId),
    );
    return r.map((s) => s.domain).where((ur) => !ur.isExpired).toList();
  }

  @override
  Future<void> assignRole(AqUserRole userRole) async =>
      await _repo.save(StorableAqUserRole(userRole));

  @override
  Future<void> revokeRole(String userId, String roleId) async {
    final r = await _repo.findAll(
      query: VaultQuery()
          .where('userId', VaultOperator.equals, userId)
          .where('roleId', VaultOperator.equals, roleId),
    );
    for (final s in r) {
      await _repo.delete(s.id);
    }
  }

  Future<List<AqUserRole>> getRoleAssignments(String roleId) async {
    final r = await _repo.findAll(
      query: VaultQuery().where('roleId', VaultOperator.equals, roleId),
    );
    return r.map((s) => s.domain).toList();
  }

  Future<List<AqUserRole>> getExpiringRoles(Duration threshold) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final thresholdTime = DateTime.now().add(threshold).millisecondsSinceEpoch;
    final r = await _repo.findAll(
      query: VaultQuery()
          .where('expiresAt', VaultOperator.greaterThan, now)
          .where('expiresAt', VaultOperator.lessThan, thresholdTime),
    );
    return r.map((s) => s.domain).toList();
  }
}

/// Репозиторий политик через Vault.
class VaultPolicyRepository implements IPolicyRepository {
  VaultPolicyRepository(this._repo);

  final DirectRepository<StorableAqPolicy> _repo;

  @override
  Future<List<AqAccessPolicy>> getEnabledPolicies() async {
    final r = await _repo.findAll(
      query: VaultQuery().where('enabled', VaultOperator.equals, true),
    );
    return r.map((s) => s.domain).toList();
  }

  Future<AqAccessPolicy?> getPolicy(String policyId) async =>
      (await _repo.findById(policyId))?.domain;

  @override
  Future<AqAccessPolicy?> findById(String id) async =>
      (await _repo.findById(id))?.domain;

  @override
  Future<AqAccessPolicy> create(AqAccessPolicy policy) async {
    await _repo.save(StorableAqPolicy(policy));
    return policy;
  }

  @override
  Future<AqAccessPolicy> update(AqAccessPolicy policy) async {
    await _repo.save(StorableAqPolicy(policy));
    return policy;
  }

  @override
  Future<void> delete(String policyId) async => await _repo.delete(policyId);

  @override
  Future<List<AqAccessPolicy>> findByTenant(String tenantId) async {
    final r = await _repo.findAll(
      query: VaultQuery().where('tenantId', VaultOperator.equals, tenantId),
    );
    return r.map((s) => s.domain).toList();
  }

  @override
  Future<List<AqAccessPolicy>> findActive(String tenantId) async {
    final r = await _repo.findAll(
      query: VaultQuery()
          .where('tenantId', VaultOperator.equals, tenantId)
          .where('enabled', VaultOperator.equals, true),
    );
    return r.map((s) => s.domain).toList();
  }

  @override
  Future<void> savePolicy(AqAccessPolicy policy) async =>
      await _repo.save(StorableAqPolicy(policy));

  @override
  Future<void> deletePolicy(String policyId) async =>
      await _repo.delete(policyId);

  @override
  Future<List<AqAccessPolicy>> getAllPolicies() async {
    final r = await _repo.findAll();
    return r.map((s) => s.domain).toList();
  }

  Future<List<AqAccessPolicy>> getPoliciesByTenant(String tenantId) =>
      findByTenant(tenantId);
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
  VaultAccessLogRepository(this._repo);

  final LoggedRepository<StorableAqAccessLog> _repo;

  @override
  Future<void> saveLog(AqAccessLog log) async =>
      await _repo.save(StorableAqAccessLog(log), actorId: log.userId);

  @override
  Future<List<AqAccessLog>> getLogs({
    String? userId,
    String? resource,
    int? limit,
    int? offset,
  }) async {
    var q = const VaultQuery();
    if (userId != null) q = q.where('userId', VaultOperator.equals, userId);
    if (resource != null) q = q.where('resource', VaultOperator.equals, resource);
    q = q.orderBy('timestamp', descending: true);
    if (limit != null) q = q.withLimit(limit);
    if (offset != null) q = q.withOffset(offset);
    final r = await _repo.findAll(query: q);
    return r.map((s) => s.domain).toList();
  }

  Future<List<AqAccessLog>> getLogsByPeriod({
    required int startTime,
    required int endTime,
    int? limit,
  }) async {
    var q = VaultQuery()
        .where('timestamp', VaultOperator.greaterOrEqual, startTime)
        .where('timestamp', VaultOperator.lessOrEqual, endTime)
        .orderBy('timestamp', descending: true);
    if (limit != null) q = q.withLimit(limit);
    final r = await _repo.findAll(query: q);
    return r.map((s) => s.domain).toList();
  }

  Future<List<AqAccessLog>> getDenials({String? userId, int? limit}) async {
    var q = VaultQuery().where('allowed', VaultOperator.equals, false);
    if (userId != null) q = q.where('userId', VaultOperator.equals, userId);
    q = q.orderBy('timestamp', descending: true);
    if (limit != null) q = q.withLimit(limit);
    final r = await _repo.findAll(query: q);
    return r.map((s) => s.domain).toList();
  }
}

// TODO(tech-debt): VaultAlertRepository, VaultAlertRepositoryImpl, VaultMetricsRepository
// используют dynamic vault — нет StorableAccessAlert и StorableRBACMetrics в aq_schema.
// Нужно создать Storable обёртки в aq_schema и перевести на DirectRepository<T>.

/// Репозиторий оповещений через Vault.
class VaultAlertRepository {
  VaultAlertRepository(this._repo);

  final DirectRepository<StorableAccessAlert> _repo;

  Future<void> saveAlert(AccessAlert alert) async =>
      await _repo.save(StorableAccessAlert(alert));

  Future<List<AccessAlert>> getAlerts({
    String? userId,
    AlertSeverity? severity,
    bool? acknowledged,
    int? limit,
  }) async {
    var q = const VaultQuery();
    if (userId != null) q = q.where('userId', VaultOperator.equals, userId);
    if (severity != null) q = q.where('severity', VaultOperator.equals, severity.value);
    if (acknowledged != null) q = q.where('resolved', VaultOperator.equals, acknowledged);
    q = q.orderBy('timestamp', descending: true);
    if (limit != null) q = q.withLimit(limit);
    final r = await _repo.findAll(query: q);
    return r.map((s) => s.domain).toList();
  }

  Future<void> acknowledgeAlert(String alertId, String acknowledgedBy) async {
    final s = await _repo.findById(alertId);
    if (s == null) return;
    final updated = s.domain.copyWith(
      resolved: true,
      resolvedBy: acknowledgedBy,
      resolvedAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
    );
    await _repo.save(StorableAccessAlert(updated));
  }

  Future<int> getUnacknowledgedCount() async {
    final r = await _repo.findAll(
      query: VaultQuery().where('resolved', VaultOperator.equals, false),
    );
    return r.length;
  }
}

/// Репозиторий метрик через Vault (реализация MetricsRepository).
class VaultMetricsRepository implements MetricsRepository {
  VaultMetricsRepository(this._repo);

  final DirectRepository<StorableRBACMetrics> _repo;

  @override
  Future<void> save(RBACMetrics metrics) async {
    final id = 'metrics_${metrics.timestamp}';
    await _repo.save(StorableRBACMetrics(metrics, id: id));
  }

  @override
  Future<List<RBACMetrics>> getMetricsInRange(int startTime, int endTime) async {
    final r = await _repo.findAll(
      query: VaultQuery()
          .where('timestamp', VaultOperator.greaterOrEqual, startTime)
          .where('timestamp', VaultOperator.lessOrEqual, endTime)
          .orderBy('timestamp', descending: false),
    );
    return r.map((s) => s.domain).toList();
  }

  @override
  Future<void> deleteOlderThan(int timestamp) async {
    final r = await _repo.findAll(
      query: VaultQuery().where('timestamp', VaultOperator.lessThan, timestamp),
    );
    for (final s in r) {
      await _repo.delete(s.id);
    }
  }

  Future<RBACMetrics?> getLatest() async {
    final r = await _repo.findAll(
      query: VaultQuery().orderBy('timestamp', descending: true).withLimit(1),
    );
    return r.isEmpty ? null : r.first.domain;
  }
}

/// Репозиторий оповещений через Vault (реализация AlertRepository).
class VaultAlertRepositoryImpl implements AlertRepository {
  VaultAlertRepositoryImpl(this._repo);

  final DirectRepository<StorableAccessAlert> _repo;

  @override
  Future<void> save(AccessAlert alert) async =>
      await _repo.save(StorableAccessAlert(alert));

  @override
  Future<void> update(AccessAlert alert) async =>
      await _repo.save(StorableAccessAlert(alert));

  @override
  Future<AccessAlert?> getById(String id) async =>
      (await _repo.findById(id))?.domain;

  @override
  Future<List<AccessAlert>> getUnacknowledged() async {
    final r = await _repo.findAll(
      query: VaultQuery()
          .where('resolved', VaultOperator.equals, false)
          .orderBy('timestamp', descending: true),
    );
    return r.map((s) => s.domain).toList();
  }

  @override
  Future<List<AccessAlert>> getInRange({
    required int startTime,
    required int endTime,
    AlertType? type,
    AlertSeverity? severity,
  }) async {
    var q = VaultQuery()
        .where('timestamp', VaultOperator.greaterOrEqual, startTime)
        .where('timestamp', VaultOperator.lessOrEqual, endTime);
    if (type != null) q = q.where('type', VaultOperator.equals, type.value);
    if (severity != null) q = q.where('severity', VaultOperator.equals, severity.value);
    q = q.orderBy('timestamp', descending: true);
    final r = await _repo.findAll(query: q);
    return r.map((s) => s.domain).toList();
  }

  @override
  Future<void> deleteOlderThan(int timestamp) async {
    final r = await _repo.findAll(
      query: VaultQuery().where('timestamp', VaultOperator.lessThan, timestamp),
    );
    for (final s in r) {
      await _repo.delete(s.id);
    }
  }
}
