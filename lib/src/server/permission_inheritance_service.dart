// pkgs/aq_security/lib/src/server/permission_inheritance_service.dart
//
// Server-only. Permission inheritance management.
// Автоматически propagate permissions от родительских ресурсов к дочерним.

import 'package:aq_schema/security/security.dart';
import 'package:uuid/uuid.dart';

/// Определяет иерархию ресурсов для inheritance
final class ResourceHierarchy {
  const ResourceHierarchy({
    required this.parentType,
    required this.childType,
  });

  final ResourceType parentType;
  final ResourceType childType;

  /// Стандартные иерархии в системе
  static const hierarchies = [
    // Project → Graph
    ResourceHierarchy(
      parentType: ResourceType.project,
      childType: ResourceType.graph,
    ),
    // Project → Instruction
    ResourceHierarchy(
      parentType: ResourceType.project,
      childType: ResourceType.instruction,
    ),
    // Project → Prompt
    ResourceHierarchy(
      parentType: ResourceType.project,
      childType: ResourceType.prompt,
    ),
    // Project → Dataset
    ResourceHierarchy(
      parentType: ResourceType.project,
      childType: ResourceType.dataset,
    ),
  ];

  /// Проверить, есть ли иерархия между типами
  static bool hasHierarchy(ResourceType parent, ResourceType child) {
    return hierarchies.any(
      (h) => h.parentType == parent && h.childType == child,
    );
  }

  /// Получить parent type для child type
  static ResourceType? getParentType(ResourceType childType) {
    final hierarchy = hierarchies.where((h) => h.childType == childType).firstOrNull;
    return hierarchy?.parentType;
  }
}

/// Callback для получения parent resource ID
typedef GetParentResourceId = Future<String?> Function(
  ResourceType childType,
  String childResourceId,
);

final class PermissionInheritanceService {
  PermissionInheritanceService({
    required this.repo,
    required this.getParentResourceId,
  });

  final IResourcePermissionRepository repo;
  final GetParentResourceId getParentResourceId;
  static final _uuid = Uuid();

  /// Propagate permissions от parent к child ресурсу
  Future<List<AqResourcePermission>> propagateToChild({
    required ResourceType parentType,
    required String parentResourceId,
    required ResourceType childType,
    required String childResourceId,
    required String tenantId,
  }) async {
    // Проверить, что есть иерархия
    if (!ResourceHierarchy.hasHierarchy(parentType, childType)) {
      throw ArgumentError(
        'No hierarchy defined between $parentType and $childType',
      );
    }

    // Получить все permissions родителя
    final parentPermissions = await repo.findByResource(
      resourceType: parentType,
      resourceId: parentResourceId,
    );

    final inherited = <AqResourcePermission>[];

    // Создать inherited permissions для каждого пользователя
    for (final parentPerm in parentPermissions) {
      if (parentPerm.isExpired) continue;

      // Проверить, нет ли уже explicit permission для этого пользователя
      final existingLevel = await repo.checkAccess(
        userId: parentPerm.userId,
        resourceType: childType,
        resourceId: childResourceId,
      );

      // Если есть explicit permission, не создаём inherited
      if (existingLevel != null) {
        final existing = await repo.findByUserAndResource(
          userId: parentPerm.userId,
          resourceType: childType,
          resourceId: childResourceId,
        );

        // Пропускаем только если это не inherited permission
        if (existing.any((p) => !p.isInherited)) {
          continue;
        }
      }

      // Создать inherited permission
      final inheritedPerm = AqResourcePermission(
        id: _uuid.v4(),
        resourceType: childType,
        resourceId: childResourceId,
        userId: parentPerm.userId,
        tenantId: tenantId,
        accessLevel: parentPerm.accessLevel,
        grantedAt: _now(),
        grantedBy: parentPerm.grantedBy,
        expiresAt: parentPerm.expiresAt,
        inheritedFrom: parentResourceId,
      );

      await repo.grant(inheritedPerm);
      inherited.add(inheritedPerm);
    }

    return inherited;
  }

  /// Propagate permissions от parent ко всем child ресурсам
  Future<int> propagateToAllChildren({
    required ResourceType parentType,
    required String parentResourceId,
    required String tenantId,
    required Future<List<String>> Function(ResourceType childType) getChildResourceIds,
  }) async {
    int totalPropagated = 0;

    // Найти все child types для этого parent type
    final childTypes = ResourceHierarchy.hierarchies
        .where((h) => h.parentType == parentType)
        .map((h) => h.childType)
        .toSet();

    for (final childType in childTypes) {
      // Получить все child resource IDs
      final childIds = await getChildResourceIds(childType);

      for (final childId in childIds) {
        final inherited = await propagateToChild(
          parentType: parentType,
          parentResourceId: parentResourceId,
          childType: childType,
          childResourceId: childId,
          tenantId: tenantId,
        );

        totalPropagated += inherited.length;
      }
    }

    return totalPropagated;
  }

  /// Обновить inherited permissions при изменении parent permission
  Future<void> updateInheritedPermissions({
    required ResourceType parentType,
    required String parentResourceId,
    required String userId,
    required AccessLevel newLevel,
  }) async {
    // Найти все child types
    final childTypes = ResourceHierarchy.hierarchies
        .where((h) => h.parentType == parentType)
        .map((h) => h.childType)
        .toSet();

    for (final childType in childTypes) {
      // Найти все inherited permissions для этого пользователя
      final userPermissions = await repo.findByUser(userId);

      final inheritedPerms = userPermissions.where(
        (p) =>
            p.resourceType == childType &&
            p.inheritedFrom == parentResourceId &&
            !p.isExpired,
      );

      // Обновить каждый inherited permission
      for (final perm in inheritedPerms) {
        // Проверить, нет ли explicit permission
        final allPerms = await repo.findByUserAndResource(
          userId: userId,
          resourceType: childType,
          resourceId: perm.resourceId,
        );

        final hasExplicit = allPerms.any((p) => !p.isInherited);

        // Если есть explicit, не трогаем inherited
        if (hasExplicit) continue;

        // Обновить inherited permission
        final updated = perm.copyWith(accessLevel: newLevel);
        await repo.grant(updated);
      }
    }
  }

  /// Удалить inherited permissions при удалении parent permission
  Future<int> removeInheritedPermissions({
    required ResourceType parentType,
    required String parentResourceId,
    required String userId,
  }) async {
    int removed = 0;

    // Найти все child types
    final childTypes = ResourceHierarchy.hierarchies
        .where((h) => h.parentType == parentType)
        .map((h) => h.childType)
        .toSet();

    for (final childType in childTypes) {
      // Найти все inherited permissions
      final userPermissions = await repo.findByUser(userId);

      final inheritedPerms = userPermissions.where(
        (p) =>
            p.resourceType == childType &&
            p.inheritedFrom == parentResourceId,
      );

      // Удалить каждый inherited permission
      for (final perm in inheritedPerms) {
        await repo.revoke(perm.id);
        removed++;
      }
    }

    return removed;
  }

  /// Получить effective access level с учётом inheritance
  Future<AccessLevel?> getEffectiveAccessLevel({
    required String userId,
    required ResourceType resourceType,
    required String resourceId,
  }) async {
    // Сначала проверить explicit permissions
    final permissions = await repo.findByUserAndResource(
      userId: userId,
      resourceType: resourceType,
      resourceId: resourceId,
    );

    // Фильтровать expired
    final validPermissions = permissions.where((p) => !p.isExpired).toList();

    if (validPermissions.isEmpty) {
      // Проверить inherited permissions от parent
      final parentType = ResourceHierarchy.getParentType(resourceType);
      if (parentType != null) {
        final parentId = await getParentResourceId(resourceType, resourceId);
        if (parentId != null) {
          return getEffectiveAccessLevel(
            userId: userId,
            resourceType: parentType,
            resourceId: parentId,
          );
        }
      }

      return null;
    }

    // Explicit permissions побеждают inherited
    final explicitPerms = validPermissions.where((p) => !p.isInherited).toList();
    if (explicitPerms.isNotEmpty) {
      // Вернуть максимальный уровень
      return explicitPerms
          .map((p) => p.accessLevel)
          .reduce((a, b) => a.includes(b) ? a : b);
    }

    // Только inherited permissions
    return validPermissions
        .map((p) => p.accessLevel)
        .reduce((a, b) => a.includes(b) ? a : b);
  }

  /// Проверить, может ли пользователь override inherited permission
  Future<bool> canOverrideInherited({
    required String userId,
    required ResourceType resourceType,
    required String resourceId,
    required String requestedBy,
  }) async {
    // Проверить, что у requestedBy есть admin или owner на ресурсе
    final requesterLevel = await getEffectiveAccessLevel(
      userId: requestedBy,
      resourceType: resourceType,
      resourceId: resourceId,
    );

    if (requesterLevel == null || !requesterLevel.includes(AccessLevel.admin)) {
      return false;
    }

    return true;
  }

  /// Override inherited permission с explicit permission
  Future<AqResourcePermission> overrideInherited({
    required String userId,
    required ResourceType resourceType,
    required String resourceId,
    required String tenantId,
    required AccessLevel newLevel,
    required String grantedBy,
  }) async {
    // Проверить права
    final canOverride = await canOverrideInherited(
      userId: userId,
      resourceType: resourceType,
      resourceId: resourceId,
      requestedBy: grantedBy,
    );

    if (!canOverride) {
      throw Exception(
        'User $grantedBy does not have permission to override inherited permissions',
      );
    }

    // Создать explicit permission (inherited permissions остаются, но explicit побеждает)
    final permission = AqResourcePermission(
      id: _uuid.v4(),
      resourceType: resourceType,
      resourceId: resourceId,
      userId: userId,
      tenantId: tenantId,
      accessLevel: newLevel,
      grantedAt: _now(),
      grantedBy: grantedBy,
      expiresAt: null,
      inheritedFrom: null, // Explicit permission
    );

    return repo.grant(permission);
  }

  static int _now() => DateTime.now().millisecondsSinceEpoch ~/ 1000;
}
