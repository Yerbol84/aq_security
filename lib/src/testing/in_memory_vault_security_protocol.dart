// pkgs/aq_security/lib/src/testing/in_memory_vault_security_protocol.dart
//
// In-memory реализация IVaultSecurityProtocol.
// Используется в примерах и тестах — без HTTP, без dart_vault.
//
// Логика: claims извлекаются локально из JWT (без верификации подписи),
// права проверяются через in-memory RBAC.

import 'package:aq_schema/security/security.dart';
import 'package:aq_schema/http/responses/validation_field_error.dart';
import 'in_memory_repositories.dart';
import '../rbac/access_control_engine.dart';

/// In-memory реализация IVaultSecurityProtocol.
///
/// Режим: embedded (SecurityMode.embedded).
/// Права проверяются через AccessControlEngine с in-memory репозиториями.
///
/// Использование:
/// ```dart
/// final protocol = InMemoryVaultSecurityProtocol.withDefaults();
/// IVaultSecurityProtocol.initialize(protocol);
/// ```
final class InMemoryVaultSecurityProtocol implements IVaultSecurityProtocol {
  InMemoryVaultSecurityProtocol({
    required AccessControlEngine engine,
    required InMemoryResourcePermissionService resourcePermissionService,
  })  : _engine = engine,
        _resourcePermissions = resourcePermissionService,
        _auditLog = [];

  final AccessControlEngine _engine;
  final InMemoryResourcePermissionService _resourcePermissions;
  final List<AuditEntry> _auditLog;

  /// Создать с дефолтными in-memory репозиториями и тестовыми данными.
  ///
  /// Создаёт роли: admin (все права), editor (read/write), viewer (read).
  factory InMemoryVaultSecurityProtocol.withDefaults() {
    final roleRepo = InMemoryRoleRepository();
    final userRoleRepo = InMemoryUserRoleRepository();
    final policyRepo = InMemoryPolicyRepository();
    final resourcePerms = InMemoryResourcePermissionService();

    // Seed roles
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;

    final adminRole = AqRole(
      id: 'role-admin',
      name: 'admin',
      permissions: ['*'],
      isSystem: true,
      createdAt: now,
    );
    final editorRole = AqRole(
      id: 'role-editor',
      name: 'editor',
      permissions: ['projects:read', 'projects:write', 'graphs:read', 'graphs:write'],
      isSystem: true,
      createdAt: now,
    );
    final viewerRole = AqRole(
      id: 'role-viewer',
      name: 'viewer',
      permissions: ['projects:read', 'graphs:read'],
      isSystem: true,
      createdAt: now,
    );

    roleRepo.seed(adminRole);
    roleRepo.seed(editorRole);
    roleRepo.seed(viewerRole);

    final engine = AccessControlEngine(
      roleRepository: roleRepo,
      userRoleRepository: userRoleRepo,
      policyRepository: policyRepo,
      cache: null,
    );

    return InMemoryVaultSecurityProtocol(
      engine: engine,
      resourcePermissionService: resourcePerms,
    );
  }

  /// Назначить роль пользователю (для настройки тестов).
  void assignRole(String userId, String roleId) {
    final engine = _engine;
    (engine.userRoleRepository as InMemoryUserRoleRepository).seed(
      AqUserRole(
        userId: userId,
        roleId: roleId,
        tenantId: 'default',
        grantedAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      ),
    );
  }

  /// Лог аудита (для проверки в тестах).
  List<AuditEntry> get auditLog => List.unmodifiable(_auditLog);

  // ── IVaultSecurityProtocol ────────────────────────────────────────────────

  @override
  IResourcePermissionService get resourcePermissions => _resourcePermissions;

  @override
  Future<AqTokenClaims?> extractClaims(Map<String, String> headers) async {
    // 1. Попробовать из Authorization header
    final auth = headers['authorization'] ?? headers['Authorization'];
    if (auth != null && auth.startsWith('Bearer ')) {
      final token = auth.substring(7);
      try {
        return TokenCodec.decodeUnverified(token);
      } catch (_) {}
    }

    // 2. Fallback: IAuthContext (embedded режим — нет HTTP headers)
    final authContext = IAuthContext.instance;
    if (authContext != null) {
      final token = await authContext.currentToken;
      if (token != null) {
        try {
          return TokenCodec.decodeUnverified(token);
        } catch (_) {}
      }
    }

    return null;
  }

  @override
  Future<AccessDecision> canRead({
    required AqTokenClaims? claims,
    required String collection,
    String? entityId,
  }) => _check(claims, collection, 'read');

  @override
  Future<AccessDecision> canWrite({
    required AqTokenClaims? claims,
    required String collection,
    String? entityId,
    required Map<String, dynamic> data,
  }) => _check(claims, collection, 'write');

  @override
  Future<AccessDecision> canDelete({
    required AqTokenClaims? claims,
    required String collection,
    required String entityId,
  }) => _check(claims, collection, 'delete');

  @override
  Future<AccessDecision> canPublish({
    required AqTokenClaims? claims,
    required String collection,
    required String entityId,
  }) => _check(claims, collection, 'publish');

  @override
  Future<AccessDecision> canGrant({
    required AqTokenClaims? claims,
    required String collection,
    required String entityId,
    required String targetUserId,
    required AccessLevel level,
  }) => _check(claims, collection, 'grant');

  @override
  Future<bool> checkRateLimit({
    required AqTokenClaims? claims,
    required String operation,
    String? ip,
  }) async => true; // in-memory: лимит не применяется

  @override
  Future<List<ValidationFieldError>> validateData({
    required String collection,
    required Map<String, dynamic> data,
  }) async {
    if (data.toString().length > 10 * 1024 * 1024) {
      return [const ValidationFieldError(
        field: '_size',
        message: 'Data size exceeds 10 MB',
        code: 'data_too_large',
      )];
    }
    return [];
  }

  @override
  Future<Map<String, dynamic>> encryptSensitiveFields({
    required AqTokenClaims? claims,
    required String collection,
    required Map<String, dynamic> data,
  }) async => data; // in-memory: шифрование не применяется

  @override
  Future<Map<String, dynamic>> decryptSensitiveFields({
    required AqTokenClaims? claims,
    required String collection,
    required Map<String, dynamic> data,
  }) async => data;

  @override
  Future<void> logOperation({
    required AqTokenClaims? claims,
    required String operation,
    required String collection,
    String? entityId,
    required bool success,
    String? errorMessage,
  }) async {
    _auditLog.add(AuditEntry(
      userId: claims?.sub,
      operation: operation,
      collection: collection,
      entityId: entityId,
      success: success,
      errorMessage: errorMessage,
      timestamp: DateTime.now(),
    ));
  }

  // ── Internal ──────────────────────────────────────────────────────────────

  Future<AccessDecision> _check(
    AqTokenClaims? claims,
    String collection,
    String action,
  ) async {
    if (claims == null) {
      return AccessDecision.deny(reason: 'Anonymous access not allowed');
    }

    // Маппинг коллекции на resource type (resource:action формат)
    final resource = _collectionToResource(collection);
    if (resource == null) {
      return AccessDecision.deny(reason: 'Unknown collection: $collection');
    }

    final decision = await _engine.canAsync(
      claims.sub,
      resource,
      action,
    );

    return decision;
  }

  String? _collectionToResource(String collection) {
    switch (collection) {
      case 'projects':
      case 'aq_studio_projects':
        return 'projects';
      case 'graphs':
      case 'workflow_graphs':
        return 'graphs';
      case 'instructions':
      case 'instruction_graphs':
        return 'instructions';
      case 'prompts':
      case 'prompt_graphs':
        return 'prompts';
      case 'datasets':
        return 'datasets';
      case 'models':
        return 'models';
      case 'api_keys':
        return 'api_keys';
      case 'sessions':
        return 'sessions';
      default:
        return null;
    }
  }
}

final class AuditEntry {
  const AuditEntry({
    required this.userId,
    required this.operation,
    required this.collection,
    required this.entityId,
    required this.success,
    required this.errorMessage,
    required this.timestamp,
  });

  final String? userId;
  final String operation;
  final String collection;
  final String? entityId;
  final bool success;
  final String? errorMessage;
  final DateTime timestamp;

  @override
  String toString() =>
      '[$timestamp] $userId $operation $collection${entityId != null ? ':$entityId' : ''} → ${success ? 'OK' : 'FAIL: $errorMessage'}';
}
