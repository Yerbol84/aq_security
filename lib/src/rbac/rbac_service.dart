// pkgs/aq_security/lib/src/rbac/rbac_service.dart
//
// Сервис управления RBAC системой.

import 'package:aq_schema/aq_schema.dart';
import 'package:uuid/uuid.dart';
import 'access_control_engine.dart';
import '../server/repositories/rbac_repositories.dart';

/// Сервис управления RBAC (Role-Based Access Control).
/// Предоставляет API для управления ролями, правами и проверки доступа.
class RBACService {
  RBACService({
    required this.engine,
    required this.roleRepository,
    required this.userRoleRepository,
    required this.policyRepository,
    this.accessLogRepository,
  });

  final AccessControlEngine engine;
  final IRoleRepository roleRepository;
  final IUserRoleRepository userRoleRepository;
  final IPolicyRepository policyRepository;
  final AccessLogRepository? accessLogRepository;

  static final _uuid = Uuid();

  String _generateId() => _uuid.v4();
  // ═══════════════════════════════════════════════════════════════════════════

  /// Создать роль.
  Future<AqRole> createRole({
    required String name,
    String? description,
    required List<String> permissions,
    List<String> inheritsFrom = const [],
    required String tenantId,
    Map<String, dynamic> metadata = const {},
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final role = AqRole(
      id: _generateId(),
      name: name,
      description: description,
      permissions: permissions,
      tenantId: tenantId,
      inheritsFrom: inheritsFrom,
      metadata: metadata,
      createdAt: now,
      updatedAt: now,
    );

    await roleRepository.saveRole(role);
    engine.invalidateAllCache(); // Инвалидировать кэш

    return role;
  }

  /// Получить роль.
  Future<AqRole?> getRole(String roleId) async {
    return await roleRepository.findById(roleId);
  }

  /// Получить все роли.
  Future<List<AqRole>> getAllRoles() async {
    return await roleRepository.getAllRoles();
  }

  /// Обновить роль.
  Future<AqRole> updateRole(
    String roleId, {
    String? name,
    String? description,
    List<String>? permissions,
    List<String>? inheritsFrom,
    Map<String, dynamic>? metadata,
  }) async {
    final existing = await roleRepository.findById(roleId);
    if (existing == null) {
      throw Exception('Role not found: $roleId');
    }

    final updated = existing.copyWith(
      name: name,
      description: description,
      permissions: permissions,
      inheritsFrom: inheritsFrom,
      metadata: metadata,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    );

    await roleRepository.saveRole(updated);
    engine.invalidateAllCache();

    return updated;
  }

  /// Удалить роль.
  Future<void> deleteRole(String roleId) async {
    await roleRepository.deleteRole(roleId);
    engine.invalidateAllCache();
  }

  /// Добавить наследование роли.
  Future<void> addRoleInheritance(String roleId, String parentRoleId) async {
    final role = await roleRepository.findById(roleId);
    if (role == null) {
      throw Exception('Role not found: $roleId');
    }

    if (role.inheritsFrom.contains(parentRoleId)) {
      return; // Уже наследует
    }

    // Проверить на циклы
    if (await _wouldCreateCycle(roleId, parentRoleId)) {
      throw Exception('Adding inheritance would create a cycle');
    }

    final updated = role.copyWith(
      inheritsFrom: [...role.inheritsFrom, parentRoleId],
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    );

    await roleRepository.saveRole(updated);
    engine.invalidateAllCache();
  }

  /// Убрать наследование роли.
  Future<void> removeRoleInheritance(String roleId, String parentRoleId) async {
    final role = await roleRepository.findById(roleId);
    if (role == null) {
      throw Exception('Role not found: $roleId');
    }

    final updated = role.copyWith(
      inheritsFrom:
          role.inheritsFrom.where((id) => id != parentRoleId).toList(),
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    );

    await roleRepository.saveRole(updated);
    engine.invalidateAllCache();
  }

  /// Получить эффективные права роли (с учётом наследования).
  Future<List<String>> getRoleEffectivePermissions(String roleId) async {
    final permissions = <String>{};
    final processed = <String>{};

    await _collectRolePermissions(roleId, permissions, processed);
    return permissions.toList();
  }

  Future<void> _collectRolePermissions(
    String roleId,
    Set<String> permissions,
    Set<String> processed, {
    int depth = 0,
  }) async {
    if (processed.contains(roleId) || depth > 5) return;
    processed.add(roleId);

    final role = await roleRepository.findById(roleId);
    if (role == null) return;

    permissions.addAll(role.permissions);

    for (final parentId in role.inheritsFrom) {
      await _collectRolePermissions(parentId, permissions, processed,
          depth: depth + 1);
    }
  }

  Future<bool> _wouldCreateCycle(String roleId, String parentRoleId) async {
    final visited = <String>{};
    return await _hasCycle(parentRoleId, roleId, visited);
  }

  Future<bool> _hasCycle(
      String currentId, String targetId, Set<String> visited) async {
    if (currentId == targetId) return true;
    if (visited.contains(currentId)) return false;
    visited.add(currentId);

    final role = await roleRepository.findById(currentId);
    if (role == null) return false;

    for (final parentId in role.inheritsFrom) {
      if (await _hasCycle(parentId, targetId, visited)) {
        return true;
      }
    }

    return false;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // User Role Assignment
  // ═══════════════════════════════════════════════════════════════════════════

  /// Назначить роль пользователю.
  Future<AqUserRole> assignRole({
    required String userId,
    required String roleId,
    required String tenantId,
    String? grantedBy,
    String? reason,
  }) async {
    final userRole = AqUserRole(
      userId: userId,
      roleId: roleId,
      tenantId: tenantId,
      grantedBy: grantedBy,
      grantedAt: DateTime.now().millisecondsSinceEpoch,
      reason: reason,
    );

    await userRoleRepository.assignRole(userRole);
    engine.invalidateUser(userId);

    return userRole;
  }

  /// Назначить временную роль.
  Future<AqUserRole> assignTemporaryRole({
    required String userId,
    required String roleId,
    required String tenantId,
    required Duration duration,
    String? grantedBy,
    String? reason,
  }) async {
    final now = DateTime.now();
    final expiresAt = now.add(duration).millisecondsSinceEpoch;

    final userRole = AqUserRole(
      userId: userId,
      roleId: roleId,
      tenantId: tenantId,
      grantedBy: grantedBy,
      grantedAt: now.millisecondsSinceEpoch,
      expiresAt: expiresAt,
      reason: reason,
    );

    await userRoleRepository.assignRole(userRole);
    engine.invalidateUser(userId);

    return userRole;
  }

  /// Отозвать роль у пользователя.
  Future<void> revokeRole(String userId, String roleId) async {
    await userRoleRepository.revokeRole(userId, roleId);
    engine.invalidateUser(userId);
  }

  /// Получить роли пользователя.
  Future<List<AqUserRole>> getUserRoles(String userId) async {
    return await userRoleRepository.getUserRoles(userId);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Access Control
  // ═══════════════════════════════════════════════════════════════════════════

  /// Проверить доступ (синхронно, из кэша).
  bool canSync(String userId, String permission) {
    return engine.canSync(userId, permission);
  }

  /// Проверить доступ (асинхронно, с политиками).
  Future<AccessDecision> can(
    String userId,
    String resource,
    String action,
    String scope, {
    AccessContext? context,
  }) async {
    final startTime = DateTime.now();

    final decision = await engine.canAsync(
      userId,
      resource,
      action,
      scope: scope,
      context: context,
    );

    // Логировать проверку
    if (accessLogRepository != null) {
      final duration = DateTime.now().difference(startTime);
      await _logAccess(
        userId: userId,
        userEmail: context?.userAttributes['email'] as String? ?? 'unknown@example.com',
        tenantId: context?.tenantId ?? 'unknown',
        resource: resource,
        action: action,
        decision: decision,
        context: context,
        duration: duration,
      );
    }

    return decision;
  }

  /// Batch проверка прав.
  Future<Map<String, bool>> canBatch(
      String userId, List<String> permissions) async {
    return await engine.canBatch(userId, permissions);
  }

  /// Получить все эффективные права пользователя.
  Future<List<String>> getUserEffectivePermissions(String userId) async {
    return await engine.getEffectivePermissions(userId);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Policy Management
  // ═══════════════════════════════════════════════════════════════════════════

  /// Создать политику.
  Future<AqAccessPolicy> createPolicy({
    required String name,
    String? description,
    required List<PolicyCondition> conditions,
    required PolicyEffect effect,
    required int priority,
    required String tenantId,
    required String createdBy,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final policy = AqAccessPolicy(
      id: _generateId(),
      name: name,
      description: description,
      tenantId: tenantId,
      statements: [
        PolicyStatement(
          effect: effect,
          conditions: conditions,
          logic: PolicyLogic.and,
        ),
      ],
      isActive: true,
      priority: priority,
      createdAt: now,
      createdBy: createdBy,
    );

    await policyRepository.savePolicy(policy);
    engine.invalidateAllCache();

    return policy;
  }

  /// Получить политику.
  Future<AqAccessPolicy?> getPolicy(String policyId) async {
    return await policyRepository.findById(policyId);
  }

  /// Обновить политику.
  Future<AqAccessPolicy> updatePolicy(
    String policyId, {
    String? name,
    String? description,
    List<PolicyCondition>? conditions,
    PolicyEffect? effect,
    int? priority,
    bool? isActive,
  }) async {
    final existing = await policyRepository.findById(policyId);
    if (existing == null) {
      throw Exception('Policy not found: $policyId');
    }

    // Если нужно обновить conditions или effect, создаём новый statement
    List<PolicyStatement>? newStatements;
    if (conditions != null || effect != null) {
      newStatements = [
        PolicyStatement(
          effect: effect ?? existing.statements.first.effect,
          conditions: conditions ?? existing.statements.first.conditions,
          logic: existing.statements.first.logic,
        ),
      ];
    }

    final updated = existing.copyWith(
      name: name,
      description: description,
      statements: newStatements,
      priority: priority,
      isActive: isActive,
    );

    await policyRepository.savePolicy(updated);
    engine.invalidateAllCache();

    return updated;
  }

  /// Удалить политику.
  Future<void> deletePolicy(String policyId) async {
    await policyRepository.deletePolicy(policyId);
    engine.invalidateAllCache();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Helpers
  // ═══════════════════════════════════════════════════════════════════════════

  Future<void> _logAccess({
    required String userId,
    required String userEmail,
    required String tenantId,
    required String resource,
    required String action,
    required AccessDecision decision,
    AccessContext? context,
    required Duration duration,
  }) async {
    final log = AqAccessLog(
      id: _generateId(),
      userId: userId,
      userEmail: userEmail,
      tenantId: tenantId,
      resource: resource,
      action: action,
      allowed: decision.allowed,
      reason: decision.reason,
      timestamp: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      ipAddress: context?.ipAddress,
      userAgent: context?.userAgent,
      metadata: {
        'durationMs': duration.inMilliseconds,
        'mfaVerified': context?.mfaVerified ?? false,
        if (context?.resourceAttributes['status'] != null)
          'resourceState': context!.resourceAttributes['status'],
        if (decision.appliedPolicies.isNotEmpty)
          'appliedPolicies': decision.appliedPolicies,
        if (decision.matchedPermissions.isNotEmpty)
          'matchedPermissions': decision.matchedPermissions,
      },
    );

    await accessLogRepository?.saveLog(log);
  }
}
