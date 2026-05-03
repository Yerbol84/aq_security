// lib/vault_registry.dart
//
// Registration of all security domains for the data layer

import 'package:dart_vault/dart_vault.dart';
import 'package:aq_schema/security/storable/security_storables.dart';
import 'package:aq_schema/security/storable/storable_rbac.dart';

/// Register all security domains in the vault
///
/// This function registers all storable types that the auth service needs:
/// - Users, Tenants, Profiles (DirectStorable)
/// - Roles, UserRoles (DirectStorable)
/// - Sessions, API Keys (LoggedStorable - with audit trail)
/// - Policies, Access Logs, Audit Trail (RBAC)
void registerSecurityDomains(VaultRegistry registry) {
  print('📦 Registering security domains...');

  // ═══════════════════════════════════════════
  //  DirectStorable — Simple CRUD entities
  // ═══════════════════════════════════════════

  // Users
  registry.registerDirect<StorableUser>(
    collection: SecurityCollections.users,
    fromMap: StorableUser.fromMap,
  );
  print('   ✅ Registered: ${SecurityCollections.users} (DirectStorable)');

  // Tenants
  registry.registerDirect<StorableTenant>(
    collection: SecurityCollections.tenants,
    fromMap: StorableTenant.fromMap,
  );
  print('   ✅ Registered: ${SecurityCollections.tenants} (DirectStorable)');

  // Profiles
  registry.registerDirect<StorableProfile>(
    collection: SecurityCollections.profiles,
    fromMap: StorableProfile.fromMap,
  );
  print('   ✅ Registered: ${SecurityCollections.profiles} (DirectStorable)');

  // Roles
  registry.registerDirect<StorableRole>(
    collection: SecurityCollections.roles,
    fromMap: StorableRole.fromMap,
  );
  print('   ✅ Registered: ${SecurityCollections.roles} (DirectStorable)');

  // User Roles (role assignments)
  registry.registerDirect<StorableUserRole>(
    collection: SecurityCollections.userRoles,
    fromMap: StorableUserRole.fromMap,
  );
  print('   ✅ Registered: ${SecurityCollections.userRoles} (DirectStorable)');

  // ═══════════════════════════════════════════
  //  LoggedStorable — Entities with audit trail
  // ═══════════════════════════════════════════

  // Sessions (with audit trail for status changes)
  registry.registerLogged<StorableSession>(
    collection: SecurityCollections.sessions,
    fromMap: StorableSession.fromMap,
  );
  print('   ✅ Registered: ${SecurityCollections.sessions} (LoggedStorable)');

  // API Keys (with audit trail for activation/deactivation)
  registry.registerLogged<StorableApiKey>(
    collection: SecurityCollections.apiKeys,
    fromMap: StorableApiKey.fromMap,
  );
  print('   ✅ Registered: ${SecurityCollections.apiKeys} (LoggedStorable)');

  // ═══════════════════════════════════════════
  //  RBAC — Policies and audit logs
  // ═══════════════════════════════════════════

  // Policies
  registry.registerDirect<StorableAqPolicy>(
    collection: AqPolicy.kCollection,
    fromMap: StorableAqPolicy.fromMap,
  );
  print('   ✅ Registered: ${AqPolicy.kCollection} (DirectStorable)');

  // Access Logs (with audit trail)
  registry.registerLogged<StorableAqAccessLog>(
    collection: AqAccessLog.kCollection,
    fromMap: StorableAqAccessLog.fromMap,
  );
  print('   ✅ Registered: ${AqAccessLog.kCollection} (LoggedStorable)');

  // Audit Trail (with audit trail - meta!)
  registry.registerLogged<StorableAqAuditTrail>(
    collection: AqAuditTrail.kCollection,
    fromMap: StorableAqAuditTrail.fromMap,
  );
  print('   ✅ Registered: ${AqAuditTrail.kCollection} (LoggedStorable)');

  print('✅ Registered ${registry.domainCount} security domains');
}
