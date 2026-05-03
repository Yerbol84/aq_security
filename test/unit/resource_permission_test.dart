// test/unit/resource_permission_test.dart
//
// Тесты для ResourcePermissionService

import 'package:test/test.dart';
import 'package:aq_security/aq_security_server.dart';
import 'package:aq_schema/security/security.dart';

// Mock repository для тестирования
class MockResourcePermissionRepository implements IResourcePermissionRepository {
  final Map<String, AqResourcePermission> _storage = {};
  final Map<String, List<String>> _userIndex = {};
  final Map<String, List<String>> _resourceIndex = {};

  @override
  Future<AqResourcePermission> grant(AqResourcePermission permission) async {
    _storage[permission.id] = permission;
    _userIndex.putIfAbsent(permission.userId, () => []).add(permission.id);
    final resourceKey = '${permission.resourceType.value}:${permission.resourceId}';
    _resourceIndex.putIfAbsent(resourceKey, () => []).add(permission.id);
    return permission;
  }

  @override
  Future<void> revoke(String permissionId) async {
    final permission = _storage[permissionId];
    if (permission != null) {
      _storage.remove(permissionId);
      _userIndex[permission.userId]?.remove(permissionId);
      final resourceKey = '${permission.resourceType.value}:${permission.resourceId}';
      _resourceIndex[resourceKey]?.remove(permissionId);
    }
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
    final ids = _userIndex[userId] ?? [];
    return ids.map((id) => _storage[id]!).toList();
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

    // Вернуть наивысший уровень доступа
    var maxLevel = AccessLevel.none;
    for (final p in permissions) {
      if (!p.isExpired && p.accessLevel.includes(maxLevel)) {
        maxLevel = p.accessLevel;
      }
    }

    return maxLevel == AccessLevel.none ? null : maxLevel;
  }

  @override
  Future<int> deleteByResource({
    required ResourceType resourceType,
    required String resourceId,
  }) async {
    final permissions = await findByResource(
      resourceType: resourceType,
      resourceId: resourceId,
    );

    for (final p in permissions) {
      await revoke(p.id);
    }

    return permissions.length;
  }

  @override
  Future<int> cleanupExpired() async {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final expired = _storage.values.where((p) => p.expiresAt != null && p.expiresAt! <= now).toList();

    for (final p in expired) {
      await revoke(p.id);
    }

    return expired.length;
  }
}

void main() {
  group('ResourcePermissionService', () {
    late ResourcePermissionService service;
    late MockResourcePermissionRepository repo;

    setUp(() {
      repo = MockResourcePermissionRepository();
      service = ResourcePermissionService(repo: repo);
    });

    group('grant', () {
      test('выдаёт permission пользователю', () async {
        final permission = await service.grant(
          resourceType: ResourceType.project,
          resourceId: 'project123',
          userId: 'user456',
          tenantId: 'tenant789',
          accessLevel: AccessLevel.read,
          grantedBy: 'owner123',
        );

        expect(permission.resourceType, equals(ResourceType.project));
        expect(permission.resourceId, equals('project123'));
        expect(permission.userId, equals('user456'));
        expect(permission.accessLevel, equals(AccessLevel.read));
      });
    });

    group('hasAccess', () {
      test('возвращает true если есть требуемый уровень доступа', () async {
        await service.grant(
          resourceType: ResourceType.project,
          resourceId: 'project123',
          userId: 'user456',
          tenantId: 'tenant789',
          accessLevel: AccessLevel.write,
          grantedBy: 'owner123',
        );

        final hasRead = await service.hasAccess(
          userId: 'user456',
          resourceType: ResourceType.project,
          resourceId: 'project123',
          requiredLevel: AccessLevel.read,
        );

        final hasWrite = await service.hasAccess(
          userId: 'user456',
          resourceType: ResourceType.project,
          resourceId: 'project123',
          requiredLevel: AccessLevel.write,
        );

        expect(hasRead, isTrue);
        expect(hasWrite, isTrue);
      });

      test('возвращает false если нет требуемого уровня', () async {
        await service.grant(
          resourceType: ResourceType.project,
          resourceId: 'project123',
          userId: 'user456',
          tenantId: 'tenant789',
          accessLevel: AccessLevel.read,
          grantedBy: 'owner123',
        );

        final hasWrite = await service.hasAccess(
          userId: 'user456',
          resourceType: ResourceType.project,
          resourceId: 'project123',
          requiredLevel: AccessLevel.write,
        );

        expect(hasWrite, isFalse);
      });

      test('возвращает false если нет доступа', () async {
        final hasAccess = await service.hasAccess(
          userId: 'user456',
          resourceType: ResourceType.project,
          resourceId: 'project123',
          requiredLevel: AccessLevel.read,
        );

        expect(hasAccess, isFalse);
      });
    });

    group('isOwner', () {
      test('возвращает true для owner', () async {
        await service.grant(
          resourceType: ResourceType.project,
          resourceId: 'project123',
          userId: 'user456',
          tenantId: 'tenant789',
          accessLevel: AccessLevel.owner,
          grantedBy: 'system',
        );

        final isOwner = await service.isOwner(
          userId: 'user456',
          resourceType: ResourceType.project,
          resourceId: 'project123',
        );

        expect(isOwner, isTrue);
      });

      test('возвращает false для не-owner', () async {
        await service.grant(
          resourceType: ResourceType.project,
          resourceId: 'project123',
          userId: 'user456',
          tenantId: 'tenant789',
          accessLevel: AccessLevel.admin,
          grantedBy: 'owner123',
        );

        final isOwner = await service.isOwner(
          userId: 'user456',
          resourceType: ResourceType.project,
          resourceId: 'project123',
        );

        expect(isOwner, isFalse);
      });
    });

    group('transferOwnership', () {
      test('передаёт ownership другому пользователю', () async {
        await service.grant(
          resourceType: ResourceType.project,
          resourceId: 'project123',
          userId: 'user1',
          tenantId: 'tenant789',
          accessLevel: AccessLevel.owner,
          grantedBy: 'system',
        );

        await service.transferOwnership(
          resourceType: ResourceType.project,
          resourceId: 'project123',
          fromUserId: 'user1',
          toUserId: 'user2',
          tenantId: 'tenant789',
        );

        final user1IsOwner = await service.isOwner(
          userId: 'user1',
          resourceType: ResourceType.project,
          resourceId: 'project123',
        );

        final user2IsOwner = await service.isOwner(
          userId: 'user2',
          resourceType: ResourceType.project,
          resourceId: 'project123',
        );

        expect(user1IsOwner, isFalse);
        expect(user2IsOwner, isTrue);
      });

      test('выбрасывает exception если fromUser не owner', () async {
        await service.grant(
          resourceType: ResourceType.project,
          resourceId: 'project123',
          userId: 'user1',
          tenantId: 'tenant789',
          accessLevel: AccessLevel.admin,
          grantedBy: 'owner123',
        );

        expect(
          () => service.transferOwnership(
            resourceType: ResourceType.project,
            resourceId: 'project123',
            fromUserId: 'user1',
            toUserId: 'user2',
            tenantId: 'tenant789',
          ),
          throwsException,
        );
      });
    });

    group('share', () {
      test('делится ресурсом с пользователем', () async {
        // Owner
        await service.grant(
          resourceType: ResourceType.project,
          resourceId: 'project123',
          userId: 'owner',
          tenantId: 'tenant789',
          accessLevel: AccessLevel.owner,
          grantedBy: 'system',
        );

        // Share
        await service.share(
          resourceType: ResourceType.project,
          resourceId: 'project123',
          withUserId: 'user2',
          tenantId: 'tenant789',
          accessLevel: AccessLevel.read,
          sharedBy: 'owner',
        );

        final hasAccess = await service.hasAccess(
          userId: 'user2',
          resourceType: ResourceType.project,
          resourceId: 'project123',
          requiredLevel: AccessLevel.read,
        );

        expect(hasAccess, isTrue);
      });

      test('выбрасывает exception если sharedBy не имеет права', () async {
        await service.grant(
          resourceType: ResourceType.project,
          resourceId: 'project123',
          userId: 'user1',
          tenantId: 'tenant789',
          accessLevel: AccessLevel.read,
          grantedBy: 'owner',
        );

        expect(
          () => service.share(
            resourceType: ResourceType.project,
            resourceId: 'project123',
            withUserId: 'user2',
            tenantId: 'tenant789',
            accessLevel: AccessLevel.read,
            sharedBy: 'user1',
          ),
          throwsException,
        );
      });

      test('выбрасывает exception при попытке share owner', () async {
        await service.grant(
          resourceType: ResourceType.project,
          resourceId: 'project123',
          userId: 'owner',
          tenantId: 'tenant789',
          accessLevel: AccessLevel.owner,
          grantedBy: 'system',
        );

        expect(
          () => service.share(
            resourceType: ResourceType.project,
            resourceId: 'project123',
            withUserId: 'user2',
            tenantId: 'tenant789',
            accessLevel: AccessLevel.owner,
            sharedBy: 'owner',
          ),
          throwsException,
        );
      });
    });

    group('listUsers', () {
      test('возвращает список пользователей с доступом', () async {
        await service.grant(
          resourceType: ResourceType.project,
          resourceId: 'project123',
          userId: 'user1',
          tenantId: 'tenant789',
          accessLevel: AccessLevel.owner,
          grantedBy: 'system',
        );

        await service.grant(
          resourceType: ResourceType.project,
          resourceId: 'project123',
          userId: 'user2',
          tenantId: 'tenant789',
          accessLevel: AccessLevel.read,
          grantedBy: 'user1',
        );

        final users = await service.listUsers(
          resourceType: ResourceType.project,
          resourceId: 'project123',
        );

        expect(users, hasLength(2));
        expect(users.map((u) => u.userId), containsAll(['user1', 'user2']));
      });
    });

    group('listUserResources', () {
      test('возвращает список ресурсов пользователя', () async {
        await service.grant(
          resourceType: ResourceType.project,
          resourceId: 'project1',
          userId: 'user1',
          tenantId: 'tenant789',
          accessLevel: AccessLevel.owner,
          grantedBy: 'system',
        );

        await service.grant(
          resourceType: ResourceType.graph,
          resourceId: 'graph1',
          userId: 'user1',
          tenantId: 'tenant789',
          accessLevel: AccessLevel.read,
          grantedBy: 'owner',
        );

        final resources = await service.listUserResources('user1');

        expect(resources, hasLength(2));
        expect(resources.map((r) => r.type), containsAll([ResourceType.project, ResourceType.graph]));
      });
    });

    group('AccessLevel', () {
      test('includes проверяет иерархию', () {
        expect(AccessLevel.owner.includes(AccessLevel.admin), isTrue);
        expect(AccessLevel.owner.includes(AccessLevel.write), isTrue);
        expect(AccessLevel.owner.includes(AccessLevel.read), isTrue);
        expect(AccessLevel.admin.includes(AccessLevel.write), isTrue);
        expect(AccessLevel.admin.includes(AccessLevel.read), isTrue);
        expect(AccessLevel.write.includes(AccessLevel.read), isTrue);

        expect(AccessLevel.read.includes(AccessLevel.write), isFalse);
        expect(AccessLevel.write.includes(AccessLevel.admin), isFalse);
      });
    });
  });
}
