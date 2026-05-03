// pkgs/aq_security/lib/src/server/resource_permission_service.dart
//
// Server-only. Resource-based permission management.
// Управляет доступом к конкретным ресурсам (projects, graphs, etc).

import 'package:uuid/uuid.dart';
import 'package:aq_schema/security/security.dart';

final class ResourcePermissionService {
  ResourcePermissionService({required this.repo});

  final IResourcePermissionRepository repo;
  static final _uuid = Uuid();

  /// Выдать permission пользователю на ресурс
  Future<AqResourcePermission> grant({
    required ResourceType resourceType,
    required String resourceId,
    required String userId,
    required String tenantId,
    required AccessLevel accessLevel,
    required String grantedBy,
    int? expiresAt,
    String? inheritedFrom,
  }) async {
    final permission = AqResourcePermission(
      id: _uuid.v4(),
      resourceType: resourceType,
      resourceId: resourceId,
      userId: userId,
      tenantId: tenantId,
      accessLevel: accessLevel,
      grantedAt: _now(),
      grantedBy: grantedBy,
      expiresAt: expiresAt,
      inheritedFrom: inheritedFrom,
    );

    return repo.grant(permission);
  }

  /// Отозвать permission
  Future<void> revoke(String permissionId) async {
    await repo.revoke(permissionId);
  }

  /// Проверить, есть ли у пользователя доступ к ресурсу
  Future<bool> hasAccess({
    required String userId,
    required ResourceType resourceType,
    required String resourceId,
    required AccessLevel requiredLevel,
  }) async {
    final userLevel = await repo.checkAccess(
      userId: userId,
      resourceType: resourceType,
      resourceId: resourceId,
    );

    if (userLevel == null) return false;
    return userLevel.includes(requiredLevel);
  }

  /// Получить уровень доступа пользователя к ресурсу
  Future<AccessLevel?> getAccessLevel({
    required String userId,
    required ResourceType resourceType,
    required String resourceId,
  }) async {
    return repo.checkAccess(
      userId: userId,
      resourceType: resourceType,
      resourceId: resourceId,
    );
  }

  /// Проверить, является ли пользователь владельцем ресурса
  Future<bool> isOwner({
    required String userId,
    required ResourceType resourceType,
    required String resourceId,
  }) async {
    final level = await getAccessLevel(
      userId: userId,
      resourceType: resourceType,
      resourceId: resourceId,
    );

    return level == AccessLevel.owner;
  }

  /// Передать ownership другому пользователю
  Future<void> transferOwnership({
    required ResourceType resourceType,
    required String resourceId,
    required String fromUserId,
    required String toUserId,
    required String tenantId,
  }) async {
    // Проверить, что fromUser является owner
    final isCurrentOwner = await isOwner(
      userId: fromUserId,
      resourceType: resourceType,
      resourceId: resourceId,
    );

    if (!isCurrentOwner) {
      throw Exception('User $fromUserId is not the owner of $resourceType:$resourceId');
    }

    // Найти текущий owner permission
    final permissions = await repo.findByUserAndResource(
      userId: fromUserId,
      resourceType: resourceType,
      resourceId: resourceId,
    );

    final ownerPermission = permissions.firstWhere(
      (p) => p.accessLevel == AccessLevel.owner,
    );

    // Отозвать старый owner permission
    await repo.revoke(ownerPermission.id);

    // Выдать новый owner permission
    await grant(
      resourceType: resourceType,
      resourceId: resourceId,
      userId: toUserId,
      tenantId: tenantId,
      accessLevel: AccessLevel.owner,
      grantedBy: fromUserId,
    );
  }

  /// Поделиться ресурсом с пользователем
  Future<AqResourcePermission> share({
    required ResourceType resourceType,
    required String resourceId,
    required String withUserId,
    required String tenantId,
    required AccessLevel accessLevel,
    required String sharedBy,
    int? expiresAt,
  }) async {
    // Проверить, что sharedBy имеет право делиться (admin или owner)
    final sharerLevel = await getAccessLevel(
      userId: sharedBy,
      resourceType: resourceType,
      resourceId: resourceId,
    );

    if (sharerLevel == null || !sharerLevel.includes(AccessLevel.admin)) {
      throw Exception('User $sharedBy does not have permission to share $resourceType:$resourceId');
    }

    // Owner не может выдать owner другому пользователю через share
    if (accessLevel == AccessLevel.owner) {
      throw Exception('Cannot grant owner access via share. Use transferOwnership instead.');
    }

    return grant(
      resourceType: resourceType,
      resourceId: resourceId,
      userId: withUserId,
      tenantId: tenantId,
      accessLevel: accessLevel,
      grantedBy: sharedBy,
      expiresAt: expiresAt,
    );
  }

  /// Обновить уровень доступа
  Future<AqResourcePermission> updateAccessLevel({
    required String permissionId,
    required AccessLevel newLevel,
  }) async {
    final permission = await repo.findById(permissionId);
    if (permission == null) {
      throw Exception('Permission not found: $permissionId');
    }

    // Owner не может быть изменён через updateAccessLevel
    if (permission.accessLevel == AccessLevel.owner || newLevel == AccessLevel.owner) {
      throw Exception('Cannot change owner access level. Use transferOwnership instead.');
    }

    final updated = permission.copyWith(accessLevel: newLevel);
    return repo.grant(updated);
  }

  /// Получить список пользователей с доступом к ресурсу
  Future<List<({String userId, AccessLevel level, AqResourcePermission permission})>> listUsers({
    required ResourceType resourceType,
    required String resourceId,
  }) async {
    final permissions = await repo.findByResource(
      resourceType: resourceType,
      resourceId: resourceId,
    );

    return permissions
        .where((p) => !p.isExpired)
        .map((p) => (userId: p.userId, level: p.accessLevel, permission: p))
        .toList();
  }

  /// Получить список ресурсов, к которым у пользователя есть доступ
  Future<List<({ResourceType type, String resourceId, AccessLevel level})>> listUserResources(
    String userId,
  ) async {
    final permissions = await repo.findByUser(userId);

    return permissions
        .where((p) => !p.isExpired)
        .map((p) => (type: p.resourceType, resourceId: p.resourceId, level: p.accessLevel))
        .toList();
  }

  /// Удалить все permissions для ресурса (при удалении ресурса)
  Future<int> deleteResourcePermissions({
    required ResourceType resourceType,
    required String resourceId,
  }) async {
    return repo.deleteByResource(
      resourceType: resourceType,
      resourceId: resourceId,
    );
  }

  /// Cleanup истёкших permissions
  Future<int> cleanupExpired() async {
    return repo.cleanupExpired();
  }

  static int _now() => DateTime.now().millisecondsSinceEpoch ~/ 1000;
}
