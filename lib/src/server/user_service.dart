// pkgs/aq_security/lib/src/server/user_service.dart
//
// Server-only. User and tenant lifecycle: find-or-create, role assignment.
// Called by AuthService during login to ensure user exists in DB.

import 'package:uuid/uuid.dart';
import 'package:aq_schema/security/security.dart';

import 'google_oauth_service.dart';
import 'github_oauth_service.dart';
import 'password_service.dart';

final class UserService {
  UserService({
    required this.users,
    required this.profiles,
    required this.roles,
    required this.tenants,
    required this.passwordService,
  });

  final IUserRepository users;
  final IProfileRepository profiles;
  final IRoleRepository roles;
  final ITenantRepository tenants;
  final PasswordService passwordService;

  static final _uuid = Uuid();

  // ── Google login: find or create user ─────────────────────────────────────

  Future<AqUser> findOrCreateFromGoogle(GoogleUserInfo google) async {
    // Look up by provider ID first (fastest + most reliable)
    var user = await users.findByProvider('google', google.sub);

    if (user == null) {
      // Try by email (user might have registered differently before)
      user = await users.findByEmail(google.email);
    }

    if (user != null) {
      // Update profile from Google if stale
      final updated = user.copyWith(
        displayName: user.displayName ?? google.name,
        photoUrl: user.photoUrl ?? google.picture,
        isVerified: user.isVerified || google.emailVerified,
        lastLoginAt: _now(),
        updatedAt: _now(),
      );
      return users.update(updated);
    }

    // New user — auto-provision with default tenant
    return _provisionNewGoogleUser(google);
  }

  Future<AqUser> _provisionNewGoogleUser(GoogleUserInfo google) async {
    // Create a personal tenant for this user
    final tenantSlug = _slugify(google.email.split('@').first);
    final uniqueSlug = '${tenantSlug}_${_uuid.v4().substring(0, 6)}';

    final tenant = await tenants.create(AqTenant(
      id: _uuid.v4(),
      name: google.name ?? google.email,
      slug: uniqueSlug,
      plan: TenantPlan.free,
      isActive: true,
      createdAt: _now(),
    ));

    final userId = _uuid.v4();
    final user = await users.create(AqUser(
      id: userId,
      email: google.email,
      displayName: google.name,
      photoUrl: google.picture,
      userType: UserType.developer, // default for Google login
      tenantId: tenant.id,
      authProvider: IdentityProvider.google,
      providerUserId: google.sub,
      isActive: true,
      isVerified: google.emailVerified,
      lastLoginAt: _now(),
      createdAt: _now(),
    ));

    // Update tenant owner
    await tenants.update(tenant.copyWith(ownerId: userId, updatedAt: _now()));

    // Assign default role
    final developerRole = await roles.findByName('developer');
    if (developerRole != null) {
      await roles.assignRole(user.id, developerRole.id, tenant.id);
    }

    // Create profile
    await profiles.upsert(AqProfile(
      userId: user.id,
      updatedAt: _now(),
    ));

    return user;
  }

  // ── GitHub login: find or create user ──────────────────────────────────────

  Future<AqUser> findOrCreateFromGitHub(GitHubUser github) async {
    // Look up by provider ID first
    var user = await users.findByProvider('github', github.id.toString());

    if (user == null && github.email != null) {
      // Try by email if available
      user = await users.findByEmail(github.email!);
    }

    if (user != null) {
      // Update profile from GitHub if stale
      final updated = user.copyWith(
        displayName: user.displayName ?? github.name ?? github.login,
        photoUrl: user.photoUrl ?? github.avatarUrl,
        lastLoginAt: _now(),
        updatedAt: _now(),
      );
      return users.update(updated);
    }

    // New user — auto-provision with default tenant
    return _provisionNewGitHubUser(github);
  }

  Future<AqUser> _provisionNewGitHubUser(GitHubUser github) async {
    // Create a personal tenant for this user
    final tenantSlug = _slugify(github.login);
    final uniqueSlug = '${tenantSlug}_${_uuid.v4().substring(0, 6)}';

    final tenant = await tenants.create(AqTenant(
      id: _uuid.v4(),
      name: github.name ?? github.login,
      slug: uniqueSlug,
      plan: TenantPlan.free,
      isActive: true,
      createdAt: _now(),
    ));

    final userId = _uuid.v4();
    final user = await users.create(AqUser(
      id: userId,
      email: github.email ?? '${github.login}@github.local', // fallback if email not public
      displayName: github.name ?? github.login,
      photoUrl: github.avatarUrl,
      userType: UserType.developer, // default for GitHub login
      tenantId: tenant.id,
      authProvider: IdentityProvider.github,
      providerUserId: github.id.toString(),
      isActive: true,
      isVerified: github.email != null, // verified if email available
      lastLoginAt: _now(),
      createdAt: _now(),
    ));

    // Update tenant owner
    await tenants.update(tenant.copyWith(ownerId: userId, updatedAt: _now()));

    // Assign default role
    final developerRole = await roles.findByName('developer');
    if (developerRole != null) {
      await roles.assignRole(user.id, developerRole.id, tenant.id);
    }

    // Create profile
    await profiles.upsert(AqProfile(
      userId: user.id,
      updatedAt: _now(),
    ));

    return user;
  }

  // ── Roles ─────────────────────────────────────────────────────────────────

  Future<List<AqRole>> getRolesForUser(String userId, String tenantId) =>
      roles.findByUser(userId, tenantId);

  // ── Email/Password registration ────────────────────────────────────────────

  /// Регистрирует нового пользователя с email/password.
  Future<AqUser> registerWithEmailPassword({
    required String email,
    required String password,
    String? displayName,
  }) async {
    // Проверяем, что email не занят
    final existing = await users.findByEmail(email);
    if (existing != null) {
      throw EmailPasswordException('Email already registered');
    }

    // Валидируем силу пароля
    final validation = passwordService.validateStrength(password);
    if (!validation.valid) {
      throw EmailPasswordException(validation.message);
    }

    // Хешируем пароль
    final passwordHash = passwordService.hash(password);

    // Создаём tenant
    final tenantSlug = _slugify(email.split('@').first);
    final uniqueSlug = '${tenantSlug}_${_uuid.v4().substring(0, 6)}';

    final tenant = await tenants.create(AqTenant(
      id: _uuid.v4(),
      name: displayName ?? email,
      slug: uniqueSlug,
      plan: TenantPlan.free,
      isActive: true,
      createdAt: _now(),
    ));

    // Создаём пользователя
    final userId = _uuid.v4();
    final user = await users.create(AqUser(
      id: userId,
      email: email,
      displayName: displayName,
      photoUrl: null,
      userType: UserType.developer,
      tenantId: tenant.id,
      authProvider: IdentityProvider.emailPassword,
      providerUserId: null,
      isActive: true,
      isVerified: false, // требуется email verification
      lastLoginAt: null,
      createdAt: _now(),
    ));

    // Сохраняем password hash в preferences
    await profiles.upsert(AqProfile(
      userId: user.id,
      preferences: {'password_hash': passwordHash},
      updatedAt: _now(),
    ));

    // Update tenant owner
    await tenants.update(tenant.copyWith(ownerId: userId, updatedAt: _now()));

    // Assign default role
    final developerRole = await roles.findByName('developer');
    if (developerRole != null) {
      await roles.assignRole(user.id, developerRole.id, tenant.id);
    }

    return user;
  }

  /// Аутентифицирует пользователя по email/password.
  Future<AqUser> authenticateWithEmailPassword({
    required String email,
    required String password,
  }) async {
    // Найти пользователя
    final user = await users.findByEmail(email);
    if (user == null) {
      throw EmailPasswordException('Invalid email or password');
    }

    // Проверить, что это email/password пользователь
    if (user.authProvider != IdentityProvider.emailPassword) {
      throw EmailPasswordException(
        'This email is registered with ${user.authProvider.value}',
      );
    }

    // Проверить, что аккаунт активен
    if (!user.isActive) {
      throw EmailPasswordException('Account is disabled');
    }

    // Получить password hash из profile preferences
    final profile = await profiles.findByUserId(user.id);
    final passwordHash = profile?.preferences['password_hash'] as String?;

    if (passwordHash == null) {
      throw EmailPasswordException('Password not set');
    }

    // Проверить пароль
    if (!passwordService.verify(password, passwordHash)) {
      throw EmailPasswordException('Invalid email or password');
    }

    // Обновить lastLoginAt
    final updated = user.copyWith(
      lastLoginAt: _now(),
      updatedAt: _now(),
    );

    return users.update(updated);
  }

  /// Обновляет пароль пользователя.
  Future<void> updatePassword({
    required String userId,
    required String newPassword,
  }) async {
    // Валидируем силу пароля
    final validation = passwordService.validateStrength(newPassword);
    if (!validation.valid) {
      throw EmailPasswordException(validation.message);
    }

    // Хешируем новый пароль
    final passwordHash = passwordService.hash(newPassword);

    // Обновляем в profile
    final profile = await profiles.findByUserId(userId);
    if (profile == null) {
      throw EmailPasswordException('User profile not found');
    }

    await profiles.upsert(AqProfile(
      userId: userId,
      preferences: {
        ...profile.preferences,
        'password_hash': passwordHash,
      },
      updatedAt: _now(),
    ));
  }

  /// Помечает email как verified.
  Future<AqUser> markEmailVerified(String userId) async {
    final user = await users.findById(userId);
    if (user == null) {
      throw EmailPasswordException('User not found');
    }

    final updated = user.copyWith(
      isVerified: true,
      updatedAt: _now(),
    );

    return users.update(updated);
  }

  // ── Magic Link authentication ──────────────────────────────────────────────

  /// Находит или создаёт пользователя для magic link.
  Future<AqUser> findOrCreateForMagicLink({
    required String email,
    String? displayName,
  }) async {
    // Попытка найти существующего пользователя
    var user = await users.findByEmail(email);

    if (user != null) {
      // Обновить lastLoginAt
      final updated = user.copyWith(
        lastLoginAt: _now(),
        updatedAt: _now(),
      );
      return users.update(updated);
    }

    // Создать нового пользователя через magic link
    return _provisionNewUserForMagicLink(
      email: email,
      displayName: displayName,
    );
  }

  Future<AqUser> _provisionNewUserForMagicLink({
    required String email,
    String? displayName,
  }) async {
    // Создаём tenant
    final tenantSlug = _slugify(email.split('@').first);
    final uniqueSlug = '${tenantSlug}_${_uuid.v4().substring(0, 6)}';

    final tenant = await tenants.create(AqTenant(
      id: _uuid.v4(),
      name: displayName ?? email,
      slug: uniqueSlug,
      plan: TenantPlan.free,
      isActive: true,
      createdAt: _now(),
    ));

    // Создаём пользователя
    final userId = _uuid.v4();
    final user = await users.create(AqUser(
      id: userId,
      email: email,
      displayName: displayName,
      photoUrl: null,
      userType: UserType.developer,
      tenantId: tenant.id,
      authProvider: IdentityProvider.emailPassword, // magic link использует emailPassword
      providerUserId: null,
      isActive: true,
      isVerified: true, // email уже verified через magic link
      lastLoginAt: _now(),
      createdAt: _now(),
    ));

    // Создаём profile без password hash
    await profiles.upsert(AqProfile(
      userId: user.id,
      updatedAt: _now(),
    ));

    // Update tenant owner
    await tenants.update(tenant.copyWith(ownerId: userId, updatedAt: _now()));

    // Assign default role
    final developerRole = await roles.findByName('developer');
    if (developerRole != null) {
      await roles.assignRole(user.id, developerRole.id, tenant.id);
    }

    return user;
  }

  // ── Seed ──────────────────────────────────────────────────────────────────

  /// Seed system roles on server startup if they don't exist.
  Future<void> seedSystemRoles() async {
    final systemRoles = [
      _makeRole('platform_admin', ['*']),
      _makeRole('developer', [
        'projects:*', 'agents:*', 'blueprints:*', 'runs:*', 'knowledge:*',
      ]),
      _makeRole('end_user', ['agents:run', 'runs:read']),
      _makeRole('service', ['runs:*', 'graphs:read', 'knowledge:read']),
    ];

    for (final role in systemRoles) {
      final existing = await roles.findByName(role.name);
      if (existing == null) {
        await roles.create(role);
      }
    }
  }

  AqRole _makeRole(String name, List<String> perms) => AqRole(
        id: _uuid.v4(),
        name: name,
        permissions: perms,
        isSystem: true,
        createdAt: _now(),
      );

  // ── API Key user provisioning ──────────────────────────────────────────────

  /// Find user associated with an API key (by userId in the key record).
  Future<AqUser?> findById(String id) => users.findById(id);

  /// Find user by email.
  Future<AqUser?> findByEmail(String email) => users.findByEmail(email);

  Future<AqTenant?> findTenantById(String id) => tenants.findById(id);

  // ── Helpers ────────────────────────────────────────────────────────────────

  static String _slugify(String s) => s
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]'), '-')
      .replaceAll(RegExp(r'-+'), '-')
      .replaceAll(RegExp(r'^-|-$'), '');

  static int _now() => DateTime.now().millisecondsSinceEpoch ~/ 1000;
}

/// Email/Password authentication exception.
final class EmailPasswordException implements Exception {
  const EmailPasswordException(this.message);

  final String message;

  @override
  String toString() => 'EmailPasswordException: $message';
}
