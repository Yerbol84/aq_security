// test/unit/permission_inheritance_test.dart
//
// Тесты для PermissionInheritanceService

import 'package:test/test.dart';
import 'package:aq_security/aq_security_server.dart';
import 'package:aq_schema/security/security.dart';

// Mock repository
class MockPermissionRepository implements IResourcePermissionRepository {
  final Map<String, AqResourcePermission> _storage = {};

  @override
  Future<AqResourcePermission> grant(AqResourcePermission permission) async {
    _storage[permission.id] = permission;
    return permission;
  }

  @override
  Future<void> revoke(String permissionId) async {
    _storage.remove(permissionId);
  }

  @override
  Future<AqResourcePermission?> findById(String id) async {
    return _storage[id];
  }

  @override
  Future<List<AqResourcePermission>> findByUserAndResource({
    required String userId,
    required ResourceType resourceType,
    required String resourceId,
  }) async {
    return _storage.values
        .where((p) =>
            p.userId == userId &&
            p.resourceType == resourceType &&
            p.resourceId == resourceId)
        .toList();
  }

  @override
  Future<List<AqResourcePermission>> findByResource({
    required ResourceType resourceType,
    required String resourceId,
  }) async {
    return _storage.values
        .where((p) => p.resourceType == resourceType && p.resourceId == resourceId)
        .toList();
  }

  @override
  Future<List<AqResourcePermission>> findByUser(String userId) async {
    return _storage.values.where((p) => p.userId == userId).toList();
  }

  @override
  Future<AccessLevel?> checkAccess({
    required String userId,
    required ResourceType resourceType,
    required String resourceId,
  }) async {
    final permissions = await findByUserAndResource(
      userId: userId,
      resourceType: resourceType,
      resourceId: resourceId,
    );

    if (permissions.isEmpty) return null;

    // Вернуть максимальный уровень
    return permissions
        .where((p) => !p.isExpired)
        .map((p) => p.accessLevel)
        .fold<AccessLevel?>(null, (max, level) {
      if (max == null) return level;
      return max.includes(level) ? max : level;
    });
  }

  @override
  Future<int> deleteByResource({
    required ResourceType resourceType,
    required String resourceId,
  }) async {
    final toDelete = _storage.values
        .where((p) => p.resourceType == resourceType && p.resourceId == resourceId)
        .toList();

    for (final p in toDelete) {
      _storage.remove(p.id);
    }

    return toDelete.length;
  }

  @override
  Future<int> cleanupExpired() async {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final toDelete = _storage.values.where((p) => p.expiresAt != null && p.expiresAt! <= now).toList();

    for (final p in toDelete) {
      _storage.remove(p.id);
    }

    return toDelete.length;
  }
}

void main() {
  group('PermissionInheritanceService', () {
    late PermissionInheritanceService service;
    late MockPermissionRepository repo;
    late ResourcePermissionService permService;

    // Mock parent resource mapping
    final parentMapping = <String, String>{
      'graph1': 'project1',
      'graph2': 'project1',
      'instruction1': 'project1',
    };

    setUp(() {
      repo = MockPermissionRepository();
      permService = ResourcePermissionService(repo: repo);
      service = PermissionInheritanceService(
        repo: repo,
        getParentResourceId: (childType, childId) async => parentMapping[childId],
      );
    });

    group('propagateToChild', () {
      test('создаёт inherited permissions для child ресурса', () async {
        final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;

        // Создать parent permission
        await permService.grant(
          resourceType: ResourceType.project,
          resourceId: 'project1',
          userId: 'user1',
          tenantId: 'tenant1',
          accessLevel: AccessLevel.admin,
          grantedBy: 'owner',
        );

        // Propagate к child
        final inherited = await service.propagateToChild(
          parentType: ResourceType.project,
          parentResourceId: 'project1',
          childType: ResourceType.graph,
          childResourceId: 'graph1',
          tenantId: 'tenant1',
        );

        expect(inherited.length, equals(1));
        expect(inherited[0].userId, equals('user1'));
        expect(inherited[0].resourceType, equals(ResourceType.graph));
        expect(inherited[0].resourceId, equals('graph1'));
        expect(inherited[0].accessLevel, equals(AccessLevel.admin));
        expect(inherited[0].inheritedFrom, equals('project1'));
      });

      test('не создаёт inherited если есть explicit permission', () async {
        // Создать parent permission
        await permService.grant(
          resourceType: ResourceType.project,
          resourceId: 'project1',
          userId: 'user1',
          tenantId: 'tenant1',
          accessLevel: AccessLevel.admin,
          grantedBy: 'owner',
        );

        // Создать explicit permission на child
        await permService.grant(
          resourceType: ResourceType.graph,
          resourceId: 'graph1',
          userId: 'user1',
          tenantId: 'tenant1',
          accessLevel: AccessLevel.read,
          grantedBy: 'admin',
        );

        // Propagate к child
        final inherited = await service.propagateToChild(
          parentType: ResourceType.project,
          parentResourceId: 'project1',
          childType: ResourceType.graph,
          childResourceId: 'graph1',
          tenantId: 'tenant1',
        );

        // Не должно создать inherited permission
        expect(inherited.length, equals(0));
      });

      test('пропускает expired permissions', () async {
        final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;

        // Создать expired parent permission
        await permService.grant(
          resourceType: ResourceType.project,
          resourceId: 'project1',
          userId: 'user1',
          tenantId: 'tenant1',
          accessLevel: AccessLevel.admin,
          grantedBy: 'owner',
          expiresAt: now - 3600, // Истёк час назад
        );

        // Propagate к child
        final inherited = await service.propagateToChild(
          parentType: ResourceType.project,
          parentResourceId: 'project1',
          childType: ResourceType.graph,
          childResourceId: 'graph1',
          tenantId: 'tenant1',
        );

        expect(inherited.length, equals(0));
      });
    });

    group('getEffectiveAccessLevel', () {
      test('возвращает explicit permission если есть', () async {
        // Создать parent permission
        await permService.grant(
          resourceType: ResourceType.project,
          resourceId: 'project1',
          userId: 'user1',
          tenantId: 'tenant1',
          accessLevel: AccessLevel.admin,
          grantedBy: 'owner',
        );

        // Создать inherited permission
        await service.propagateToChild(
          parentType: ResourceType.project,
          parentResourceId: 'project1',
          childType: ResourceType.graph,
          childResourceId: 'graph1',
          tenantId: 'tenant1',
        );

        // Создать explicit permission с меньшим уровнем
        await permService.grant(
          resourceType: ResourceType.graph,
          resourceId: 'graph1',
          userId: 'user1',
          tenantId: 'tenant1',
          accessLevel: AccessLevel.read,
          grantedBy: 'admin',
        );

        // Effective level должен быть explicit (read), не inherited (admin)
        final level = await service.getEffectiveAccessLevel(
          userId: 'user1',
          resourceType: ResourceType.graph,
          resourceId: 'graph1',
        );

        expect(level, equals(AccessLevel.read));
      });

      test('возвращает inherited permission если нет explicit', () async {
        // Создать parent permission
        await permService.grant(
          resourceType: ResourceType.project,
          resourceId: 'project1',
          userId: 'user1',
          tenantId: 'tenant1',
          accessLevel: AccessLevel.admin,
          grantedBy: 'owner',
        );

        // Propagate к child
        await service.propagateToChild(
          parentType: ResourceType.project,
          parentResourceId: 'project1',
          childType: ResourceType.graph,
          childResourceId: 'graph1',
          tenantId: 'tenant1',
        );

        // Effective level должен быть inherited
        final level = await service.getEffectiveAccessLevel(
          userId: 'user1',
          resourceType: ResourceType.graph,
          resourceId: 'graph1',
        );

        expect(level, equals(AccessLevel.admin));
      });

      test('проверяет parent если нет permissions на child', () async {
        // Создать parent permission
        await permService.grant(
          resourceType: ResourceType.project,
          resourceId: 'project1',
          userId: 'user1',
          tenantId: 'tenant1',
          accessLevel: AccessLevel.write,
          grantedBy: 'owner',
        );

        // НЕ propagate к child

        // Effective level должен быть от parent
        final level = await service.getEffectiveAccessLevel(
          userId: 'user1',
          resourceType: ResourceType.graph,
          resourceId: 'graph1',
        );

        expect(level, equals(AccessLevel.write));
      });
    });

    group('updateInheritedPermissions', () {
      test('обновляет inherited permissions при изменении parent', () async {
        // Создать parent permission
        await permService.grant(
          resourceType: ResourceType.project,
          resourceId: 'project1',
          userId: 'user1',
          tenantId: 'tenant1',
          accessLevel: AccessLevel.admin,
          grantedBy: 'owner',
        );

        // Propagate к child
        await service.propagateToChild(
          parentType: ResourceType.project,
          parentResourceId: 'project1',
          childType: ResourceType.graph,
          childResourceId: 'graph1',
          tenantId: 'tenant1',
        );

        // Обновить parent permission
        await service.updateInheritedPermissions(
          parentType: ResourceType.project,
          parentResourceId: 'project1',
          userId: 'user1',
          newLevel: AccessLevel.read,
        );

        // Проверить, что inherited permission обновился
        final level = await service.getEffectiveAccessLevel(
          userId: 'user1',
          resourceType: ResourceType.graph,
          resourceId: 'graph1',
        );

        expect(level, equals(AccessLevel.read));
      });

      test('не трогает explicit permissions', () async {
        // Создать parent permission
        await permService.grant(
          resourceType: ResourceType.project,
          resourceId: 'project1',
          userId: 'user1',
          tenantId: 'tenant1',
          accessLevel: AccessLevel.admin,
          grantedBy: 'owner',
        );

        // Создать explicit permission на child
        await permService.grant(
          resourceType: ResourceType.graph,
          resourceId: 'graph1',
          userId: 'user1',
          tenantId: 'tenant1',
          accessLevel: AccessLevel.write,
          grantedBy: 'admin',
        );

        // Обновить parent permission
        await service.updateInheritedPermissions(
          parentType: ResourceType.project,
          parentResourceId: 'project1',
          userId: 'user1',
          newLevel: AccessLevel.read,
        );

        // Explicit permission не должен измениться
        final level = await service.getEffectiveAccessLevel(
          userId: 'user1',
          resourceType: ResourceType.graph,
          resourceId: 'graph1',
        );

        expect(level, equals(AccessLevel.write));
      });
    });

    group('removeInheritedPermissions', () {
      test('удаляет inherited permissions при удалении parent', () async {
        // Создать parent permission
        final parentPerm = await permService.grant(
          resourceType: ResourceType.project,
          resourceId: 'project1',
          userId: 'user1',
          tenantId: 'tenant1',
          accessLevel: AccessLevel.admin,
          grantedBy: 'owner',
        );

        // Propagate к child
        await service.propagateToChild(
          parentType: ResourceType.project,
          parentResourceId: 'project1',
          childType: ResourceType.graph,
          childResourceId: 'graph1',
          tenantId: 'tenant1',
        );

        // Удалить parent permission
        await repo.revoke(parentPerm.id);

        // Удалить inherited permissions
        final removed = await service.removeInheritedPermissions(
          parentType: ResourceType.project,
          parentResourceId: 'project1',
          userId: 'user1',
        );

        expect(removed, equals(1));

        // Проверить, что inherited permission удалён
        final permissions = await repo.findByUserAndResource(
          userId: 'user1',
          resourceType: ResourceType.graph,
          resourceId: 'graph1',
        );

        expect(permissions.length, equals(0));
      });
    });

    group('overrideInherited', () {
      test('создаёт explicit permission поверх inherited', () async {
        // Создать parent permission
        await permService.grant(
          resourceType: ResourceType.project,
          resourceId: 'project1',
          userId: 'user1',
          tenantId: 'tenant1',
          accessLevel: AccessLevel.admin,
          grantedBy: 'owner',
        );

        // Создать admin permission для user2
        await permService.grant(
          resourceType: ResourceType.graph,
          resourceId: 'graph1',
          userId: 'user2',
          tenantId: 'tenant1',
          accessLevel: AccessLevel.admin,
          grantedBy: 'owner',
        );

        // Propagate к child
        await service.propagateToChild(
          parentType: ResourceType.project,
          parentResourceId: 'project1',
          childType: ResourceType.graph,
          childResourceId: 'graph1',
          tenantId: 'tenant1',
        );

        // Override inherited permission
        await service.overrideInherited(
          userId: 'user1',
          resourceType: ResourceType.graph,
          resourceId: 'graph1',
          tenantId: 'tenant1',
          newLevel: AccessLevel.read,
          grantedBy: 'user2',
        );

        // Effective level должен быть explicit (read)
        final level = await service.getEffectiveAccessLevel(
          userId: 'user1',
          resourceType: ResourceType.graph,
          resourceId: 'graph1',
        );

        expect(level, equals(AccessLevel.read));
      });

      test('требует admin права для override', () async {
        // Создать parent permission
        await permService.grant(
          resourceType: ResourceType.project,
          resourceId: 'project1',
          userId: 'user1',
          tenantId: 'tenant1',
          accessLevel: AccessLevel.admin,
          grantedBy: 'owner',
        );

        // Создать read permission для user2
        await permService.grant(
          resourceType: ResourceType.graph,
          resourceId: 'graph1',
          userId: 'user2',
          tenantId: 'tenant1',
          accessLevel: AccessLevel.read,
          grantedBy: 'owner',
        );

        // Propagate к child
        await service.propagateToChild(
          parentType: ResourceType.project,
          parentResourceId: 'project1',
          childType: ResourceType.graph,
          childResourceId: 'graph1',
          tenantId: 'tenant1',
        );

        // Попытка override без прав
        expect(
          () => service.overrideInherited(
            userId: 'user1',
            resourceType: ResourceType.graph,
            resourceId: 'graph1',
            tenantId: 'tenant1',
            newLevel: AccessLevel.read,
            grantedBy: 'user2',
          ),
          throwsException,
        );
      });
    });

    group('ResourceHierarchy', () {
      test('определяет стандартные иерархии', () {
        expect(
          ResourceHierarchy.hasHierarchy(ResourceType.project, ResourceType.graph),
          isTrue,
        );
        expect(
          ResourceHierarchy.hasHierarchy(ResourceType.project, ResourceType.instruction),
          isTrue,
        );
        expect(
          ResourceHierarchy.hasHierarchy(ResourceType.graph, ResourceType.project),
          isFalse,
        );
      });

      test('возвращает parent type для child', () {
        expect(
          ResourceHierarchy.getParentType(ResourceType.graph),
          equals(ResourceType.project),
        );
        expect(
          ResourceHierarchy.getParentType(ResourceType.instruction),
          equals(ResourceType.project),
        );
        expect(
          ResourceHierarchy.getParentType(ResourceType.project),
          isNull,
        );
      });
    });
  });
}
