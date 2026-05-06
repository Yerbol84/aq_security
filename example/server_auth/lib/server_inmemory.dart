// SCN-001 + SCN-002 + SCN-004: Auth flow и RBAC в embedded режиме.
import 'package:aq_schema/security/security.dart';
import 'package:aq_schema/security/token/token_codec.dart';
import 'package:uuid/uuid.dart';
import 'package:aq_security/aq_security_server.dart';

void main() async {
  print('=== SCN-001 + SCN-002 + SCN-004 ===\n');

  const secret = 'test-jwt-secret-32-chars-long-ok!';
  final config = SecurityConfig(authEndpoint: 'http://localhost:8080', jwtSecret: secret);
  final users = InMemoryUserRepository();
  final sessions = InMemorySessionRepository();
  final apiKeys = InMemoryApiKeyRepository();
  final tenants = InMemoryTenantRepository();
  final roleRepo = InMemoryRoleRepository();
  final userRoleRepo = InMemoryUserRoleRepository();
  final policyRepo = InMemoryPolicyRepository();
  final passwordService = PasswordService();
  final codec = TokenCodec(secret: secret);
  final uuid = const Uuid();
  final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;

  // Seed
  final tenant = AqTenant(id: 'tenant-1', slug: 'acme', name: 'Acme', plan: TenantPlan.pro, isActive: true, createdAt: now);
  await tenants.create(tenant);

  roleRepo.seed(AqRole(id: 'role-editor', name: 'editor', permissions: ['projects:read', 'projects:write'], isSystem: true, createdAt: now));

  final engine = AccessControlEngine(
    roleRepository: roleRepo,
    userRoleRepository: userRoleRepo,
    policyRepository: policyRepo,
    cache: null,
  );

  // SCN-001: Registration
  print('--- SCN-001: Registration ---');
  final userId = uuid.v4();
  final pwdHash = passwordService.hash('password123');
  final pwdStore = {userId: pwdHash}; // AqUser не хранит passwordHash

  final user = AqUser(id: userId, email: 'alice@acme.com', tenantId: tenant.id, authProvider: IdentityProvider.emailPassword, userType: UserType.developer, isActive: true, createdAt: now);
  await users.create(user);
  userRoleRepo.seed(AqUserRole(userId: userId, roleId: 'role-editor', tenantId: tenant.id, grantedAt: now));
  print('✓ Registered: ${user.email}');

  // SCN-001: Login
  print('\n--- SCN-001: Login ---');
  final found = await users.findByEmail('alice@acme.com');
  if (found == null || !passwordService.verify('password123', pwdStore[found.id]!)) {
    print('✗ Login failed'); return;
  }
  final session = AqSession(id: uuid.v4(), userId: found.id, tenantId: tenant.id, status: SessionStatus.active, authProvider: IdentityProvider.emailPassword, kind: SessionKind.human, createdAt: now, expiresAt: now + config.sessionTtlSeconds, lastSeenAt: now);
  await sessions.create(session);
  await users.updateLastLogin(found.id, now);

  final token = codec.encode(AqTokenClaims(sub: found.id, tid: tenant.id, email: found.email, type: TokenType.access, roles: ['editor'], scopes: ['projects:read', 'projects:write'], iat: now, exp: now + config.accessTokenTtlSeconds, jti: uuid.v4(), sid: session.id));
  print('✓ Login: ${found.email}, kind=${session.kind.name}');
  print('  Token: ${token.substring(0, 30)}...');

  // SCN-002: RBAC
  print('\n--- SCN-002: RBAC ---');
  for (final action in ['read', 'write', 'delete']) {
    final d = await engine.canAsync(found.id, 'projects', action);
    print('projects:$action → ${d.allowed ? '✓ ALLOW' : '✗ DENY'}');
  }

  // SCN-004: API Key
  print('\n--- SCN-004: API Key ---');
  final rawKey = 'aq_${uuid.v4().replaceAll('-', '')}';
  final key = AqApiKey(id: uuid.v4(), userId: found.id, tenantId: tenant.id, name: 'CI/CD', keyPrefix: rawKey.substring(0, 8), keyHash: passwordService.hash(rawKey), permissions: ['projects:read'], isActive: true, createdAt: now);
  await apiKeys.create(key);

  final foundKey = (await apiKeys.listAll()).where((k) => k.isActive && passwordService.verify(rawKey, k.keyHash)).firstOrNull;
  if (foundKey != null) {
    final svc = AqSession(id: uuid.v4(), userId: foundKey.userId, tenantId: tenant.id, status: SessionStatus.active, authProvider: IdentityProvider.apiKey, kind: SessionKind.service, createdAt: now, expiresAt: now + 3600, lastSeenAt: now);
    await sessions.create(svc);
    print('✓ API Key auth: kind=${svc.kind.name}');
  }

  // Logout
  print('\n--- SCN-001: Logout ---');
  await sessions.revoke(session.id, 'logout');
  print('✓ Revoked: ${(await sessions.findById(session.id))?.status.value}');
  print('\n✓ Done');
}
