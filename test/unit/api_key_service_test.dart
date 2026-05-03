// test/unit/api_key_service_test.dart
//
// Unit тесты для ApiKeyService

import 'package:test/test.dart';
import 'package:aq_security/src/server/api_key_service.dart';
import 'package:aq_schema/security/security.dart';

// Mock repository для тестирования
class MockApiKeyRepository implements IApiKeyRepository {
  final Map<String, AqApiKey> _storage = {};
  final Map<String, AqApiKey> _hashIndex = {};

  @override
  Future<AqApiKey> create(AqApiKey key) async {
    _storage[key.id] = key;
    _hashIndex[key.keyHash] = key;
    return key;
  }

  @override
  Future<AqApiKey?> findById(String id) async => _storage[id];

  @override
  Future<AqApiKey?> findByHash(String hash) async => _hashIndex[hash];

  @override
  Future<void> revoke(String id) async {
    final key = _storage[id];
    if (key != null) {
      final updated = AqApiKey(
        id: key.id,
        userId: key.userId,
        tenantId: key.tenantId,
        name: key.name,
        keyPrefix: key.keyPrefix,
        keyHash: key.keyHash,
        permissions: key.permissions,
        isActive: false,
        createdAt: key.createdAt,
        lastUsedAt: key.lastUsedAt,
        expiresAt: key.expiresAt,
      );
      _storage[id] = updated;
      _hashIndex[key.keyHash] = updated;
    }
  }

  @override
  Future<void> updateLastUsed(String id, int timestamp) async {
    final key = _storage[id];
    if (key != null) {
      final updated = AqApiKey(
        id: key.id,
        userId: key.userId,
        tenantId: key.tenantId,
        name: key.name,
        keyPrefix: key.keyPrefix,
        keyHash: key.keyHash,
        permissions: key.permissions,
        isActive: key.isActive,
        createdAt: key.createdAt,
        lastUsedAt: timestamp,
        expiresAt: key.expiresAt,
      );
      _storage[id] = updated;
      _hashIndex[key.keyHash] = updated;
    }
  }

  @override
  Future<List<AqApiKey>> listByUser(String userId) async {
    return _storage.values.where((k) => k.userId == userId).toList();
  }

  @override
  Future<AqApiKey> update(AqApiKey key) async {
    _storage[key.id] = key;
    _hashIndex[key.keyHash] = key;
    return key;
  }

  @override
  Future<List<AqApiKey>> listAll() async {
    return _storage.values.toList();
  }
}

void main() {
  group('ApiKeyService', () {
    late ApiKeyService service;
    late MockApiKeyRepository repo;

    setUp(() {
      repo = MockApiKeyRepository();
      service = ApiKeyService(repo: repo);
    });

    group('create', () {
      test('создает ключ с префиксом aq_live_', () async {
        final result = await service.create(
          userId: 'user1',
          tenantId: 'tenant1',
          name: 'Test Key',
          permissions: ['projects:read'],
        );

        expect(result.rawKey, startsWith('aq_live_'));
        expect(result.rawKey.length, 72); // 'aq_live_' (8) + 64 hex chars
        expect(result.record.name, 'Test Key');
        expect(result.record.userId, 'user1');
        expect(result.record.tenantId, 'tenant1');
        expect(result.record.permissions, ['projects:read']);
        expect(result.record.isActive, isTrue);
      });

      test('создает ключ с префиксом aq_test_ когда isTest=true', () async {
        final result = await service.create(
          userId: 'user1',
          tenantId: 'tenant1',
          name: 'Test Key',
          permissions: ['projects:read'],
          isTest: true,
        );

        expect(result.rawKey, startsWith('aq_test_'));
        expect(result.rawKey.length, 72); // 'aq_test_' (8) + 64 hex chars
      });

      test('сохраняет только hash, не raw key', () async {
        final result = await service.create(
          userId: 'user1',
          tenantId: 'tenant1',
          name: 'Test Key',
          permissions: ['projects:read'],
        );

        // Проверяем что в record нет raw key
        expect(result.record.toJson().containsKey('key'), isFalse);
        expect(result.record.keyHash, isNotEmpty);
        expect(result.record.keyHash, isNot(equals(result.rawKey)));
      });

      test('keyPrefix содержит первые 14 символов', () async {
        final result = await service.create(
          userId: 'user1',
          tenantId: 'tenant1',
          name: 'Test Key',
          permissions: ['projects:read'],
        );

        expect(result.record.keyPrefix, result.rawKey.substring(0, 14));
        expect(result.record.keyPrefix, startsWith('aq_live_'));
      });
    });

    group('validate', () {
      test('валидирует корректный ключ', () async {
        final created = await service.create(
          userId: 'user1',
          tenantId: 'tenant1',
          name: 'Test Key',
          permissions: ['projects:read'],
        );

        final validated = await service.validate(created.rawKey);

        expect(validated, isNotNull);
        expect(validated!.id, created.record.id);
        expect(validated.userId, 'user1');
      });

      test('отклоняет ключ с неправильным префиксом', () async {
        final validated = await service.validate('wrong_prefix_123456');

        expect(validated, isNull);
      });

      test('отклоняет несуществующий ключ', () async {
        final validated = await service.validate('aq_live_' + '0' * 64);

        expect(validated, isNull);
      });

      test('отклоняет отозванный ключ', () async {
        final created = await service.create(
          userId: 'user1',
          tenantId: 'tenant1',
          name: 'Test Key',
          permissions: ['projects:read'],
        );

        await service.revoke(created.record.id);

        final validated = await service.validate(created.rawKey);

        expect(validated, isNull);
      });

      test('обновляет lastUsedAt при валидации', () async {
        final created = await service.create(
          userId: 'user1',
          tenantId: 'tenant1',
          name: 'Test Key',
          permissions: ['projects:read'],
        );

        expect(created.record.lastUsedAt, isNull);

        await service.validate(created.rawKey);

        final updated = await repo.findById(created.record.id);
        expect(updated!.lastUsedAt, isNotNull);
        expect(updated.lastUsedAt! > 0, isTrue);
      });
    });

    group('rotate', () {
      test('создает новый ключ и отзывает старый', () async {
        final original = await service.create(
          userId: 'user1',
          tenantId: 'tenant1',
          name: 'Original Key',
          permissions: ['projects:read'],
        );

        final rotated = await service.rotate(original.record.id);

        // Новый ключ создан
        expect(rotated.rawKey, isNot(equals(original.rawKey)));
        expect(rotated.rawKey, startsWith('aq_live_'));
        expect(rotated.record.name, contains('rotated'));
        expect(rotated.record.userId, original.record.userId);
        expect(rotated.record.tenantId, original.record.tenantId);
        expect(rotated.record.permissions, original.record.permissions);

        // Старый ключ отозван
        final oldKey = await repo.findById(original.record.id);
        expect(oldKey!.isActive, isFalse);

        // Старый ключ больше не валидируется
        final validated = await service.validate(original.rawKey);
        expect(validated, isNull);
      });

      test('сохраняет тип ключа (test/live) при ротации', () async {
        final original = await service.create(
          userId: 'user1',
          tenantId: 'tenant1',
          name: 'Test Key',
          permissions: ['projects:read'],
          isTest: true,
        );

        final rotated = await service.rotate(original.record.id);

        expect(rotated.rawKey, startsWith('aq_test_'));
      });

      test('выбрасывает ошибку для несуществующего ключа', () async {
        expect(
          () => service.rotate('nonexistent'),
          throwsA(isA<Exception>()),
        );
      });
    });

    group('listForUser', () {
      test('возвращает только ключи пользователя', () async {
        await service.create(
          userId: 'user1',
          tenantId: 'tenant1',
          name: 'Key 1',
          permissions: ['projects:read'],
        );

        await service.create(
          userId: 'user1',
          tenantId: 'tenant1',
          name: 'Key 2',
          permissions: ['projects:write'],
        );

        await service.create(
          userId: 'user2',
          tenantId: 'tenant1',
          name: 'Key 3',
          permissions: ['projects:read'],
        );

        final user1Keys = await service.listForUser('user1');
        final user2Keys = await service.listForUser('user2');

        expect(user1Keys.length, 2);
        expect(user2Keys.length, 1);
        expect(user1Keys.every((k) => k.userId == 'user1'), isTrue);
        expect(user2Keys.every((k) => k.userId == 'user2'), isTrue);
      });
    });
  });
}
