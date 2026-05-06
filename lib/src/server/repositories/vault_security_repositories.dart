// pkgs/aq_security/lib/src/server/repositories/vault_security_repositories.dart
//
// ⚠️ THIN WRAPPERS - НЕ ДОБАВЛЯТЬ БИЗНЕС-ЛОГИКУ!
//
// Эти классы - тонкие обёртки над DirectRepositoryImpl/LoggedRepositoryImpl
// для удобства API (методы findByEmail, findByProvider и т.д.).
//
// ЗАПРЕЩЕНО добавлять сюда:
// - Бизнес-логику
// - Валидацию
// - Вычисления
// - Трансформации данных
//
// Только простые запросы к Vault через VaultQuery.
//
// DirectStorable  → DirectRepositoryImpl   (User, Tenant, Profile, Role, UserRole)
// LoggedStorable  → LoggedRepositoryImpl   (Session, ApiKey)

import 'package:aq_schema/aq_schema.dart' hide AqRole, AqUserRole;
import 'package:aq_schema/security/security.dart';

// ── User ──────────────────────────────────────────────────────────────────────

final class VaultUserRepository implements IUserRepository {
  VaultUserRepository(this._repo);

  final DirectRepository<StorableUser> _repo;

  @override
  Future<AqUser?> findById(String id) async =>
      (await _repo.findById(id))?.domain;

  @override
  Future<AqUser?> findByEmail(String email) async {
    final r = await _repo.findAll(
      query: VaultQuery()
          .where('email', VaultOperator.equals, email)
          .page(limit: 1, offset: 0),
    );
    return r.isEmpty ? null : r.first.domain;
  }

  @override
  Future<AqUser?> findByProvider(String provider, String providerUserId) async {
    final r = await _repo.findAll(
      query: VaultQuery()
          .where('authProvider', VaultOperator.equals, provider)
          .where('providerUserId', VaultOperator.equals, providerUserId)
          .page(limit: 1, offset: 0),
    );
    return r.isEmpty ? null : r.first.domain;
  }

  @override
  Future<AqUser> create(AqUser u) async {
    await _repo.save(StorableUser(u));
    return u;
  }

  @override
  Future<AqUser> update(AqUser u) async {
    await _repo.save(StorableUser(u));
    return u;
  }

  @override
  Future<void> updateLastLogin(String userId, int ts) async {
    final u = await findById(userId);
    if (u == null) return;
    await _repo.save(StorableUser(u.copyWith(lastLoginAt: ts, updatedAt: ts)));
  }

  @override
  Future<List<AqUser>> listByTenant(String tenantId) async {
    final r = await _repo.findAll(
      query: VaultQuery().where('tenantId', VaultOperator.equals, tenantId),
    );
    return r.map((s) => s.domain).toList();
  }
}

// ── Profile ───────────────────────────────────────────────────────────────────

final class VaultProfileRepository implements IProfileRepository {
  VaultProfileRepository(this._repo);

  final DirectRepository<StorableProfile> _repo;

  @override
  Future<AqProfile?> findByUserId(String userId) async =>
      (await _repo.findById(userId))?.domain;

  @override
  Future<AqProfile> upsert(AqProfile p) async {
    await _repo.save(StorableProfile(p));
    return p;
  }
}

// ── Role ──────────────────────────────────────────────────────────────────────

final class VaultRoleRepository implements IRoleRepository {
  VaultRoleRepository({
    required DirectRepository<StorableRole> roles,
    required DirectRepository<StorableUserRole> userRoles,
  })  : _roleRepo = roles,
        _urRepo = userRoles;

  final DirectRepository<StorableRole> _roleRepo;
  final DirectRepository<StorableUserRole> _urRepo;

  @override
  Future<List<AqRole>> findByUser(String userId, String tenantId) async {
    final assignments = await _urRepo.findAll(
      query: VaultQuery()
          .where('userId', VaultOperator.equals, userId)
          .where('tenantId', VaultOperator.equals, tenantId),
    );
    final roles = <AqRole>[];
    for (final a in assignments) {
      final r = await _roleRepo.findById(a.domain.roleId);
      if (r != null) roles.add(r.domain);
    }
    return roles;
  }

  @override
  Future<List<AqRole>> listSystemRoles() async {
    final r = await _roleRepo.findAll(
      query: VaultQuery().where('isSystem', VaultOperator.equals, true),
    );
    return r.map((s) => s.domain).toList();
  }

  @override
  Future<AqRole?> findByName(String name, {String? tenantId}) async {
    var q = VaultQuery()
        .where('name', VaultOperator.equals, name)
        .page(limit: 1, offset: 0);
    if (tenantId != null) {
      q = q.where('tenantId', VaultOperator.equals, tenantId);
    }
    final r = await _roleRepo.findAll(query: q);
    return r.isEmpty ? null : r.first.domain;
  }

  @override
  Future<AqRole?> findById(String id) async =>
      (await _roleRepo.findById(id))?.domain;

  @override
  Future<List<AqRole>> getAllRoles() async {
    final r = await _roleRepo.findAll();
    return r.map((s) => s.domain).toList();
  }

  @override
  Future<void> saveRole(AqRole role) async =>
      await _roleRepo.save(StorableRole(role));

  @override
  Future<void> deleteRole(String roleId) async =>
      await _roleRepo.delete(roleId);

  @override
  Future<AqRole> create(AqRole role) async {
    await _roleRepo.save(StorableRole(role));
    return role;
  }

  @override
  Future<void> assignRole(
    String userId,
    String roleId,
    String tenantId, {
    String? grantedBy,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    await _urRepo.save(StorableUserRole(AqUserRole(
      userId: userId,
      roleId: roleId,
      tenantId: tenantId,
      grantedBy: grantedBy,
      grantedAt: now,
    )));
  }

  @override
  Future<void> revokeRole(String userId, String roleId, String tenantId) async {
    await _urRepo.delete('${userId}_${roleId}_$tenantId');
  }
}

// ── Tenant ────────────────────────────────────────────────────────────────────

final class VaultTenantRepository implements ITenantRepository {
  VaultTenantRepository(this._repo);

  final DirectRepository<StorableTenant> _repo;

  @override
  Future<AqTenant?> findById(String id) async =>
      (await _repo.findById(id))?.domain;

  @override
  Future<AqTenant?> findBySlug(String slug) async {
    final r = await _repo.findAll(
      query: VaultQuery()
          .where('slug', VaultOperator.equals, slug)
          .page(limit: 1, offset: 0),
    );
    return r.isEmpty ? null : r.first.domain;
  }

  @override
  Future<AqTenant> create(AqTenant t) async {
    await _repo.save(StorableTenant(t));
    return t;
  }

  @override
  Future<AqTenant> update(AqTenant t) async {
    await _repo.save(StorableTenant(t));
    return t;
  }

  @override
  Future<List<AqTenant>> list() async {
    final r = await _repo.findAll();
    return r.map((s) => s.domain).toList();
  }
}

// ── Session — LoggedRepositoryImpl ────────────────────────────────────────────

final class VaultSessionRepository implements ISessionRepository {
  VaultSessionRepository(this._repo);

  final LoggedRepository<StorableSession> _repo;
  static const _sys = 'system';

  @override
  Future<AqSession?> findById(String id) async =>
      (await _repo.findById(id))?.domain;

  @override
  Future<AqSession> create(AqSession s) async {
    await _repo.save(StorableSession(s), actorId: _sys);
    return s;
  }

  @override
  Future<AqSession> update(AqSession s) async {
    await _repo.save(StorableSession(s), actorId: _sys);
    return s;
  }

  @override
  Future<void> touch(String sessionId, int ts) async {
    final s = await findById(sessionId);
    if (s == null) return;
    await _repo.save(
      StorableSession(s.copyWith(lastSeenAt: ts)),
      actorId: _sys,
    );
  }

  @override
  Future<void> revoke(String sessionId, String reason) async {
    final s = await findById(sessionId);
    if (s == null) return;
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    await _repo.save(
      StorableSession(s.copyWith(
        status: SessionStatus.revoked,
        revokedAt: now,
        revokedReason: reason,
      )),
      actorId: _sys,
    );
  }

  @override
  Future<void> revokeAllForUser(String userId) async {
    for (final s in await listActiveByUser(userId)) {
      await revoke(s.id, 'revoke_all');
    }
  }

  @override
  Future<List<AqSession>> listActiveByUser(String userId) async {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final r = await _repo.findAll(
      query: VaultQuery()
          .where('userId', VaultOperator.equals, userId)
          .where('status', VaultOperator.equals, 'active'),
    );
    return r.map((s) => s.domain).where((s) => s.expiresAt > now).toList();
  }

  @override
  Future<int> purgeExpired() async {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final all = await _repo.findAll(
      query: VaultQuery().where('status', VaultOperator.equals, 'active'),
    );
    var count = 0;
    for (final storable in all) {
      final s = storable.domain;
      if (s.expiresAt < now) {
        await _repo.save(
          StorableSession(s.copyWith(status: SessionStatus.expired)),
          actorId: _sys,
        );
        count++;
      }
    }
    return count;
  }
}

// ── ApiKey — LoggedRepositoryImpl ─────────────────────────────────────────────

final class VaultApiKeyRepository implements IApiKeyRepository {
  VaultApiKeyRepository(this._repo);

  final LoggedRepository<StorableApiKey> _repo;
  static const _sys = 'system';

  @override
  Future<AqApiKey?> findByHash(String hash) async {
    final r = await _repo.findAll(
      query: VaultQuery()
          .where('keyHash', VaultOperator.equals, hash)
          .page(limit: 1, offset: 0),
    );
    return r.isEmpty ? null : r.first.domain;
  }

  @override
  Future<AqApiKey?> findById(String id) async =>
      (await _repo.findById(id))?.domain;

  @override
  Future<AqApiKey> create(AqApiKey k) async {
    await _repo.save(StorableApiKey(k), actorId: k.userId);
    return k;
  }

  @override
  Future<void> revoke(String id) async {
    final k = await findById(id);
    if (k == null) return;
    await _repo.save(
      StorableApiKey(AqApiKey(
        id: k.id,
        userId: k.userId,
        tenantId: k.tenantId,
        name: k.name,
        keyPrefix: k.keyPrefix,
        keyHash: k.keyHash,
        permissions: k.permissions,
        isActive: false,
        lastUsedAt: k.lastUsedAt,
        expiresAt: k.expiresAt,
        createdAt: k.createdAt,
      )),
      actorId: _sys,
    );
  }

  @override
  Future<void> updateLastUsed(String id, int ts) async {
    final k = await findById(id);
    if (k == null) return;
    await _repo.save(
      StorableApiKey(AqApiKey(
        id: k.id,
        userId: k.userId,
        tenantId: k.tenantId,
        name: k.name,
        keyPrefix: k.keyPrefix,
        keyHash: k.keyHash,
        permissions: k.permissions,
        isActive: k.isActive,
        lastUsedAt: ts,
        expiresAt: k.expiresAt,
        createdAt: k.createdAt,
      )),
      actorId: _sys,
    );
  }

  @override
  Future<List<AqApiKey>> listByUser(String userId) async {
    final r = await _repo.findAll(
      query: VaultQuery().where('userId', VaultOperator.equals, userId),
    );
    return r.map((s) => s.domain).toList();
  }

  @override
  Future<AqApiKey> update(AqApiKey k) async {
    await _repo.save(StorableApiKey(k), actorId: _sys);
    return k;
  }

  @override
  Future<List<AqApiKey>> listAll() async {
    final r = await _repo.findAll();
    return r.map((s) => s.domain).toList();
  }
}

// Фабрика vaultSecurityRepos намеренно удалена.
// Создание DirectRepositoryImpl/LoggedRepositoryImpl — ответственность
// приложения-сервера (aq_auth_server.dart или main.dart),
// где dart_vault является явной зависимостью.
