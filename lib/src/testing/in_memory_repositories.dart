// pkgs/aq_security/lib/src/testing/in_memory_repositories.dart
//
// In-memory реализации всех репозиторных интерфейсов.
// Используются в примерах, тестах и разработке без data layer.
//
// Все реализации работают строго через порты из aq_schema.
// Никаких Map<String, dynamic>, никакого хардкода.

import 'package:aq_schema/security/security.dart';

// ═══════════════════════════════════════════════════════════════════════════
// IUserRepository
// ═══════════════════════════════════════════════════════════════════════════

final class InMemoryUserRepository implements IUserRepository {
  final _users = <String, AqUser>{};

  @override
  Future<AqUser?> findById(String id) async => _users[id];

  @override
  Future<AqUser?> findByEmail(String email) async =>
      _users.values.where((u) => u.email == email).firstOrNull;

  @override
  Future<AqUser?> findByProvider(String provider, String providerUserId) async =>
      _users.values
          .where((u) =>
              u.authProvider.value == provider &&
              u.providerUserId == providerUserId)
          .firstOrNull;

  @override
  Future<AqUser> create(AqUser user) async {
    _users[user.id] = user;
    return user;
  }

  @override
  Future<AqUser> update(AqUser user) async {
    _users[user.id] = user;
    return user;
  }

  @override
  Future<void> updateLastLogin(String userId, int timestamp) async {
    final user = _users[userId];
    if (user != null) _users[userId] = user.copyWith(lastLoginAt: timestamp);
  }

  @override
  Future<List<AqUser>> listByTenant(String tenantId) async =>
      _users.values.where((u) => u.tenantId == tenantId).toList();
}

// ═══════════════════════════════════════════════════════════════════════════
// IProfileRepository
// ═══════════════════════════════════════════════════════════════════════════

final class InMemoryProfileRepository implements IProfileRepository {
  final _profiles = <String, AqProfile>{};

  @override
  Future<AqProfile?> findByUserId(String userId) async => _profiles[userId];

  @override
  Future<AqProfile> upsert(AqProfile profile) async {
    _profiles[profile.userId] = profile;
    return profile;
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// IRoleRepository
// ═══════════════════════════════════════════════════════════════════════════

final class InMemoryRoleRepository implements IRoleRepository {
  final _roles = <String, AqRole>{};
  final _userRoles = <String, List<String>>{}; // userId → [roleId]

  @override
  Future<List<AqRole>> findByUser(String userId, String tenantId) async {
    final roleIds = _userRoles[userId] ?? [];
    return roleIds
        .map((id) => _roles[id])
        .whereType<AqRole>()
        .where((r) => r.tenantId == null || r.tenantId == tenantId)
        .toList();
  }

  @override
  Future<List<AqRole>> listSystemRoles() async =>
      _roles.values.where((r) => r.isSystem).toList();

  @override
  Future<AqRole?> findByName(String name, {String? tenantId}) async =>
      _roles.values
          .where((r) => r.name == name && (tenantId == null || r.tenantId == tenantId))
          .firstOrNull;

  @override
  Future<AqRole> create(AqRole role) async {
    _roles[role.id] = role;
    return role;
  }

  @override
  Future<AqRole?> findById(String id) async => _roles[id];

  @override
  Future<List<AqRole>> getAllRoles() async => _roles.values.toList();

  @override
  Future<void> saveRole(AqRole role) async => _roles[role.id] = role;

  @override
  Future<void> deleteRole(String roleId) async => _roles.remove(roleId);

  /// Seed для тестов.
  void seed(AqRole role) => _roles[role.id] = role;

  @override
  Future<void> assignRole(String userId, String roleId, String tenantId,
      {String? grantedBy}) async {
    _userRoles.putIfAbsent(userId, () => []);
    if (!_userRoles[userId]!.contains(roleId)) {
      _userRoles[userId]!.add(roleId);
    }
  }

  @override
  Future<void> revokeRole(String userId, String roleId, String tenantId) async {
    _userRoles[userId]?.remove(roleId);
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// ISessionRepository
// ═══════════════════════════════════════════════════════════════════════════

final class InMemorySessionRepository implements ISessionRepository {
  final _sessions = <String, AqSession>{};

  @override
  Future<AqSession?> findById(String id) async => _sessions[id];

  @override
  Future<AqSession> create(AqSession session) async {
    _sessions[session.id] = session;
    return session;
  }

  @override
  Future<AqSession> update(AqSession session) async {
    _sessions[session.id] = session;
    return session;
  }

  @override
  Future<void> touch(String sessionId, int lastSeenAt) async {
    final s = _sessions[sessionId];
    if (s != null) _sessions[sessionId] = s.copyWith(lastSeenAt: lastSeenAt);
  }

  @override
  Future<void> revoke(String sessionId, String reason) async {
    final s = _sessions[sessionId];
    if (s != null) {
      _sessions[sessionId] = s.copyWith(
        status: SessionStatus.revoked,
        revokedAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
        revokedReason: reason,
      );
    }
  }

  @override
  Future<void> revokeAllForUser(String userId) async {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    for (final entry in _sessions.entries) {
      if (entry.value.userId == userId &&
          entry.value.status == SessionStatus.active) {
        _sessions[entry.key] = entry.value.copyWith(
          status: SessionStatus.revoked,
          revokedAt: now,
          revokedReason: 'logout_all',
        );
      }
    }
  }

  @override
  Future<List<AqSession>> listActiveByUser(String userId) async =>
      _sessions.values
          .where((s) => s.userId == userId && s.isActive)
          .toList();

  @override
  Future<int> purgeExpired() async {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final expired = _sessions.entries
        .where((e) => e.value.expiresAt < now)
        .map((e) => e.key)
        .toList();
    for (final id in expired) {
      _sessions.remove(id);
    }
    return expired.length;
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// IApiKeyRepository
// ═══════════════════════════════════════════════════════════════════════════

final class InMemoryApiKeyRepository implements IApiKeyRepository {
  final _keys = <String, AqApiKey>{};

  @override
  Future<AqApiKey?> findByHash(String keyHash) async =>
      _keys.values.where((k) => k.keyHash == keyHash).firstOrNull;

  @override
  Future<AqApiKey?> findById(String id) async => _keys[id];

  @override
  Future<AqApiKey> create(AqApiKey apiKey) async {
    _keys[apiKey.id] = apiKey;
    return apiKey;
  }

  @override
  Future<AqApiKey> update(AqApiKey apiKey) async {
    _keys[apiKey.id] = apiKey;
    return apiKey;
  }

  @override
  Future<void> revoke(String id) async {
    final k = _keys[id];
    if (k == null) return;
    _keys[id] = AqApiKey(
      id: k.id, userId: k.userId, tenantId: k.tenantId,
      name: k.name, keyPrefix: k.keyPrefix, keyHash: k.keyHash,
      permissions: k.permissions, isActive: false,
      createdAt: k.createdAt, lastUsedAt: k.lastUsedAt,
    );
  }

  @override
  Future<void> updateLastUsed(String id, int timestamp) async {
    final k = _keys[id];
    if (k == null) return;
    _keys[id] = AqApiKey(
      id: k.id, userId: k.userId, tenantId: k.tenantId,
      name: k.name, keyPrefix: k.keyPrefix, keyHash: k.keyHash,
      permissions: k.permissions, isActive: k.isActive,
      createdAt: k.createdAt, lastUsedAt: timestamp,
    );
  }

  @override
  Future<List<AqApiKey>> listByUser(String userId) async =>
      _keys.values.where((k) => k.userId == userId).toList();

  @override
  Future<List<AqApiKey>> listAll() async => _keys.values.toList();
}

// ═══════════════════════════════════════════════════════════════════════════
// ITenantRepository
// ═══════════════════════════════════════════════════════════════════════════

final class InMemoryTenantRepository implements ITenantRepository {
  final _tenants = <String, AqTenant>{};

  @override
  Future<AqTenant?> findById(String id) async => _tenants[id];

  @override
  Future<AqTenant?> findBySlug(String slug) async =>
      _tenants.values.where((t) => t.slug == slug).firstOrNull;

  @override
  Future<AqTenant> create(AqTenant tenant) async {
    _tenants[tenant.id] = tenant;
    return tenant;
  }

  @override
  Future<AqTenant> update(AqTenant tenant) async {
    _tenants[tenant.id] = tenant;
    return tenant;
  }

  @override
  Future<List<AqTenant>> list() async => _tenants.values.toList();
}

// ═══════════════════════════════════════════════════════════════════════════
// IUserRoleRepository + IPolicyRepository (для AccessControlEngine)
// ═══════════════════════════════════════════════════════════════════════════

final class InMemoryUserRoleRepository implements IUserRoleRepository {
  final _assignments = <String, List<AqUserRole>>{}; // userId → assignments

  void seed(AqUserRole assignment) {
    _assignments.putIfAbsent(assignment.userId, () => []);
    _assignments[assignment.userId]!.add(assignment);
  }

  @override
  Future<List<AqUserRole>> getUserRoles(String userId) async =>
      _assignments[userId] ?? [];

  @override
  Future<void> assignRole(AqUserRole userRole) async {
    _assignments.putIfAbsent(userRole.userId, () => []);
    _assignments[userRole.userId]!.add(userRole);
  }

  @override
  Future<void> revokeRole(String userId, String roleId) async {
    _assignments[userId]?.removeWhere((r) => r.roleId == roleId);
  }
}

final class InMemoryPolicyRepository implements IPolicyRepository {
  final _policies = <String, AqAccessPolicy>{};

  void seed(AqAccessPolicy policy) => _policies[policy.id] = policy;

  @override
  Future<List<AqAccessPolicy>> getEnabledPolicies() async =>
      _policies.values.where((p) => p.isActive).toList();

  Future<AqAccessPolicy?> getPolicy(String policyId) async => _policies[policyId];

  @override
  Future<AqAccessPolicy?> findById(String id) async => _policies[id];

  @override
  Future<AqAccessPolicy> create(AqAccessPolicy policy) async {
    _policies[policy.id] = policy;
    return policy;
  }

  @override
  Future<AqAccessPolicy> update(AqAccessPolicy policy) async {
    _policies[policy.id] = policy;
    return policy;
  }

  @override
  Future<void> delete(String policyId) async => _policies.remove(policyId);

  @override
  Future<List<AqAccessPolicy>> findByTenant(String tenantId) async =>
      _policies.values.where((p) => p.tenantId == tenantId).toList();

  @override
  Future<List<AqAccessPolicy>> findActive(String tenantId) async =>
      _policies.values.where((p) => p.isActive && p.tenantId == tenantId).toList();

  @override
  Future<void> savePolicy(AqAccessPolicy policy) async =>
      _policies[policy.id] = policy;

  @override
  Future<void> deletePolicy(String policyId) async => _policies.remove(policyId);

  @override
  Future<List<AqAccessPolicy>> getAllPolicies() async => _policies.values.toList();
}

// ═══════════════════════════════════════════════════════════════════════════
// IResourcePermissionService (in-memory)
// ═══════════════════════════════════════════════════════════════════════════

final class InMemoryResourcePermissionService
    implements IResourcePermissionService {
  final _permissions = <String, List<AqResourcePermission>>{}; // resourceId → list

  @override
  Future<void> grant({
    required String resourceId,
    required String userId,
    required AccessLevel level,
    required String grantedBy,
    DateTime? expiresAt,
  }) async {
    _permissions.putIfAbsent(resourceId, () => []);
    _permissions[resourceId]!.removeWhere((p) => p.userId == userId);
    _permissions[resourceId]!.add(AqResourcePermission(
      id: '$resourceId:$userId',
      resourceType: ResourceType.project,
      resourceId: resourceId,
      userId: userId,
      tenantId: 'default',
      accessLevel: level,
      grantedAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      grantedBy: grantedBy,
      expiresAt: expiresAt != null
          ? expiresAt.millisecondsSinceEpoch ~/ 1000
          : null,
    ));
  }

  @override
  Future<void> revoke({
    required String resourceId,
    required String userId,
    required String revokedBy,
  }) async {
    _permissions[resourceId]?.removeWhere((p) => p.userId == userId);
  }

  @override
  Future<List<AqResourcePermission>> list(String resourceId) async =>
      _permissions[resourceId] ?? [];

  @override
  Future<bool> hasAccess({
    required String resourceId,
    required String userId,
    required AccessLevel minimumLevel,
  }) async {
    final perms = _permissions[resourceId] ?? [];
    return perms.any((p) =>
        p.userId == userId &&
        !p.isExpired &&
        p.accessLevel.includes(minimumLevel));
  }

  @override
  Future<List<String>> listUserResources({
    required String userId,
    AccessLevel? minimumLevel,
  }) async {
    final result = <String>[];
    for (final entry in _permissions.entries) {
      final hasMatch = entry.value.any((p) =>
          p.userId == userId &&
          !p.isExpired &&
          (minimumLevel == null || p.accessLevel.includes(minimumLevel)));
      if (hasMatch) result.add(entry.key);
    }
    return result;
  }

  @override
  Future<void> copyPermissions({
    required String sourceResourceId,
    required String targetResourceId,
    required String copiedBy,
  }) async {
    final source = _permissions[sourceResourceId] ?? [];
    _permissions[targetResourceId] = source
        .map((p) => AqResourcePermission(
              id: '$targetResourceId:${p.userId}',
              resourceType: p.resourceType,
              resourceId: targetResourceId,
              userId: p.userId,
              tenantId: p.tenantId,
              accessLevel: p.accessLevel,
              grantedAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
              grantedBy: copiedBy,
            ))
        .toList();
  }

  @override
  Future<void> deleteAllPermissions({
    required String resourceId,
    required String deletedBy,
  }) async {
    _permissions.remove(resourceId);
  }
}

final class InMemoryRevokedTokenRepository implements IRevokedTokenRepository {
  final _store = <String, AqRevokedToken>{}; // jti → token

  @override
  Future<void> revoke(AqRevokedToken token) async =>
      _store[token.jti] = token;

  @override
  Future<bool> isRevoked(String jti) async => _store.containsKey(jti);

  @override
  Future<AqRevokedToken?> findByJti(String jti) async => _store[jti];

  @override
  Future<int> revokeAllForUser(String userId, {String? reason}) async {
    final toRevoke = _store.values.where((t) => t.userId == userId).toList();
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    for (final t in toRevoke) {
      _store[t.jti] = AqRevokedToken(
        jti: t.jti, userId: t.userId, tenantId: t.tenantId,
        revokedAt: now, expiresAt: t.expiresAt,
        reason: reason ?? 'revoked_all',
      );
    }
    return toRevoke.length;
  }

  @override
  Future<int> revokeAllForSession(String sessionId, {String? reason}) async =>
      // In-memory: нет индекса по sessionId — возвращаем 0
      // Vault реализация использует query по sessionId
      0;

  @override
  Future<int> cleanupExpired() async {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final expired = _store.keys.where((k) => _store[k]!.expiresAt < now).toList();
    for (final k in expired) _store.remove(k);
    return expired.length;
  }

  @override
  Future<List<AqRevokedToken>> listByUser(String userId) async =>
      _store.values.where((t) => t.userId == userId).toList();
}
