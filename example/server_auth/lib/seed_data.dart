// lib/seed_data.dart
//
// Seed test data for development

import 'package:aq_schema/security/security.dart';

/// Seed test data for development
///
/// Creates:
/// - 1 test tenant
/// - 3 test users (admin, developer, viewer)
/// - 3 roles with different permissions
/// - Role assignments
/// - 1 test API key
Future<void> seedTestData() async {
  print('🌱 Seeding test data...');

  // Note: This is a placeholder. Actual implementation will use
  // repositories from AQAuthServer to save data.
  //
  // The data structure is defined here for reference.

  final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;

  // 1. Test Tenant
  final tenant = AqTenant(
    id: 'tenant_test',
    slug: 'test-company',
    name: 'Test Company',
    plan: TenantPlan.pro,
    isActive: true,
    createdAt: now,
  );

  // 2. Test Users
  final users = [
    AqUser(
      id: 'user_admin',
      email: 'admin@test.com',
      tenantId: tenant.id,
      authProvider: AuthProvider.email,
      userType: UserType.admin,
      isActive: true,
      createdAt: now,
    ),
    AqUser(
      id: 'user_developer',
      email: 'developer@test.com',
      tenantId: tenant.id,
      authProvider: AuthProvider.email,
      userType: UserType.regular,
      isActive: true,
      createdAt: now,
    ),
    AqUser(
      id: 'user_viewer',
      email: 'viewer@test.com',
      tenantId: tenant.id,
      authProvider: AuthProvider.email,
      userType: UserType.regular,
      isActive: true,
      createdAt: now,
    ),
  ];

  // 3. Test Roles
  final roles = [
    AqRole(
      id: 'role_admin',
      name: 'Admin',
      description: 'Full access to all resources',
      tenantId: tenant.id,
      permissions: ['*:*:*'], // Wildcard - full access
      isSystem: false,
      createdAt: now,
    ),
    AqRole(
      id: 'role_developer',
      name: 'Developer',
      description: 'Can read all, write own projects and tasks',
      tenantId: tenant.id,
      permissions: [
        'projects:read:*',
        'projects:write:own',
        'projects:delete:own',
        'tasks:*:own',
        'users:read:tenant',
      ],
      isSystem: false,
      createdAt: now,
    ),
    AqRole(
      id: 'role_viewer',
      name: 'Viewer',
      description: 'Read-only access',
      tenantId: tenant.id,
      permissions: [
        'projects:read:*',
        'tasks:read:*',
        'users:read:tenant',
      ],
      isSystem: false,
      createdAt: now,
    ),
  ];

  // 4. Role Assignments
  final userRoles = [
    AqUserRole(
      userId: users[0].id,
      roleId: roles[0].id,
      tenantId: tenant.id,
      grantedAt: now,
      reason: 'Test admin user',
    ),
    AqUserRole(
      userId: users[1].id,
      roleId: roles[1].id,
      tenantId: tenant.id,
      grantedAt: now,
      reason: 'Test developer user',
    ),
    AqUserRole(
      userId: users[2].id,
      roleId: roles[2].id,
      tenantId: tenant.id,
      grantedAt: now,
      reason: 'Test viewer user',
    ),
  ];

  // 5. Test API Key
  // Note: In real implementation, this would be hashed
  final apiKey = AqApiKey(
    id: 'key_test',
    userId: users[0].id,
    tenantId: tenant.id,
    name: 'Test API Key',
    keyHash: 'hash_of_aq_test_1234567890abcdef', // SHA-256 hash
    prefix: 'aq_test_',
    isActive: true,
    createdAt: now,
  );

  print('✅ Test data structure prepared:');
  print('   Tenant: ${tenant.slug}');
  print('   Users: ${users.length}');
  print('   Roles: ${roles.length}');
  print('   Role assignments: ${userRoles.length}');
  print('   API keys: 1');
  print('');
  print('📝 Test credentials:');
  print('   Email: admin@test.com / Password: admin123');
  print('   Email: developer@test.com / Password: dev123');
  print('   Email: viewer@test.com / Password: view123');
  print('   API Key: aq_test_1234567890abcdef');
  print('');

  // TODO: Save to database through repositories
  // This will be implemented when AQAuthServer is integrated
}
