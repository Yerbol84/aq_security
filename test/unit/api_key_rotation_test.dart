// test/unit/api_key_rotation_test.dart
//
// Тесты для API Key Rotation с grace period

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
        lastRotatedAt: key.lastRotatedAt,
        expiresAt: key.expiresAt,
        updatedAt: key.updatedAt,
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
        lastRotatedAt: key.lastRotatedAt,
        expiresAt: key.expiresAt,
        updatedAt: key.updatedAt,
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
  group('API Key Rotation', () {
    late ApiKeyService service;
    late MockApiKeyRepository repo;

    setUp(() {
      repo = MockApiKeyRepository();
      service = ApiKeyService(repo: repo);
    });

    test('rotate создаёт новый ключ и revoke старый (без grace period)', () async {
      // Создать исходный ключ
      final original = await service.create(
        userId: 'user1',
        tenantId: 'tenant1',
        name: 'Original Key',
        permissions: ['read', 'write'],
      );

      // Ротация без grace period
      final result = await service.rotate(original.record.id);

      // Проверить новый ключ
      expect(result.rawKey, isNotEmpty);
      expect(result.rawKey, isNot(equals(original.rawKey)));
      expect(result.record.name, equals('Original Key (rotated)'));
      expect(result.record.permissions, equals(['read', 'write']));
      expect(result.record.lastRotatedAt, isNotNull);

      // Старый ключ должен быть revoked
      expect(result.oldRecord, isNull);
      final oldKey = await repo.findById(original.record.id);
      expect(oldKey!.isActive, isFalse);
    });

    test('rotate с grace period оставляет старый ключ активным', () async {
      // Создать исходный ключ
      final original = await service.create(
        userId: 'user1',
        tenantId: 'tenant1',
        name: 'Original Key',
        permissions: ['read'],
      );

      // Ротация с grace period 7 дней
      final result = await service.rotate(
        original.record.id,
        gracePeriod: const Duration(days: 7),
      );

      // Новый ключ создан
      expect(result.rawKey, isNotEmpty);
      expect(result.record.isActive, isTrue);

      // Старый ключ всё ещё активен
      expect(result.oldRecord, isNotNull);
      expect(result.oldRecord!.isActive, isTrue);
      expect(result.oldRecord!.expiresAt, isNotNull);

      // Оба ключа должны работать
      final newKeyValidation = await service.validate(result.rawKey);
      final oldKeyValidation = await service.validate(original.rawKey);

      expect(newKeyValidation, isNotNull);
      expect(oldKeyValidation, isNotNull);
    });

    test('rotate с нулевым grace period revoke старый ключ', () async {
      final original = await service.create(
        userId: 'user1',
        tenantId: 'tenant1',
        name: 'Test Key',
        permissions: ['read'],
      );

      final result = await service.rotate(
        original.record.id,
        gracePeriod: Duration.zero,
      );

      expect(result.oldRecord, isNull);
      final oldKey = await repo.findById(original.record.id);
      expect(oldKey!.isActive, isFalse);
    });

    test('rotate сохраняет isTest флаг', () async {
      final original = await service.create(
        userId: 'user1',
        tenantId: 'tenant1',
        name: 'Test Key',
        permissions: ['read'],
        isTest: true,
      );

      final result = await service.rotate(original.record.id);

      expect(result.rawKey.startsWith('aq_test_'), isTrue);
      expect(result.record.keyPrefix.startsWith('aq_test_'), isTrue);
    });

    test('findKeysNeedingRotation находит ключи по rotation period', () async {
      // Создать ключ с lastRotatedAt 100 дней назад
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final oldRotation = now - const Duration(days: 100).inSeconds;

      final oldKey = await repo.create(AqApiKey(
        id: 'key1',
        userId: 'user1',
        tenantId: 'tenant1',
        name: 'Old Key',
        keyPrefix: 'aq_live_',
        keyHash: 'hash1',
        permissions: ['read'],
        isActive: true,
        createdAt: now - const Duration(days: 200).inSeconds,
        lastRotatedAt: oldRotation,
      ));

      // Создать свежий ключ
      final freshKey = await repo.create(AqApiKey(
        id: 'key2',
        userId: 'user2',
        tenantId: 'tenant1',
        name: 'Fresh Key',
        keyPrefix: 'aq_live_',
        keyHash: 'hash2',
        permissions: ['read'],
        isActive: true,
        createdAt: now - const Duration(days: 10).inSeconds,
        lastRotatedAt: now - const Duration(days: 10).inSeconds,
      ));

      // Найти ключи, требующие ротации (90 дней)
      final needsRotation = await service.findKeysNeedingRotation(
        rotationPeriod: const Duration(days: 90),
      );

      expect(needsRotation.length, equals(1));
      expect(needsRotation.first.id, equals(oldKey.id));
    });

    test('findKeysNeedingRotation находит ключи по expiration warning', () async {
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;

      // Ключ истекает через 10 дней
      final expiringKey = await repo.create(AqApiKey(
        id: 'key1',
        userId: 'user1',
        tenantId: 'tenant1',
        name: 'Expiring Key',
        keyPrefix: 'aq_live_',
        keyHash: 'hash1',
        permissions: ['read'],
        isActive: true,
        createdAt: now - const Duration(days: 100).inSeconds,
        expiresAt: now + const Duration(days: 10).inSeconds,
      ));

      // Ключ истекает через 30 дней
      final safeKey = await repo.create(AqApiKey(
        id: 'key2',
        userId: 'user2',
        tenantId: 'tenant1',
        name: 'Safe Key',
        keyPrefix: 'aq_live_',
        keyHash: 'hash2',
        permissions: ['read'],
        isActive: true,
        createdAt: now - const Duration(days: 50).inSeconds,
        expiresAt: now + const Duration(days: 30).inSeconds,
      ));

      // Найти ключи с warning 14 дней
      final needsRotation = await service.findKeysNeedingRotation(
        expirationWarning: const Duration(days: 14),
      );

      expect(needsRotation.length, equals(1));
      expect(needsRotation.first.id, equals(expiringKey.id));
    });

    test('findKeysNeedingRotation игнорирует неактивные ключи', () async {
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;

      await repo.create(AqApiKey(
        id: 'key1',
        userId: 'user1',
        tenantId: 'tenant1',
        name: 'Inactive Key',
        keyPrefix: 'aq_live_',
        keyHash: 'hash1',
        permissions: ['read'],
        isActive: false,
        createdAt: now - const Duration(days: 200).inSeconds,
        lastRotatedAt: now - const Duration(days: 100).inSeconds,
      ));

      final needsRotation = await service.findKeysNeedingRotation(
        rotationPeriod: const Duration(days: 90),
      );

      expect(needsRotation, isEmpty);
    });

    test('autoRotateKeys ротирует все ключи, требующие ротации', () async {
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;

      // Создать 3 старых ключа
      for (var i = 1; i <= 3; i++) {
        await repo.create(AqApiKey(
          id: 'key$i',
          userId: 'user$i',
          tenantId: 'tenant1',
          name: 'Old Key $i',
          keyPrefix: 'aq_live_',
          keyHash: 'hash$i',
          permissions: ['read'],
          isActive: true,
          createdAt: now - const Duration(days: 200).inSeconds,
          lastRotatedAt: now - const Duration(days: 100).inSeconds,
        ));
      }

      // Автоматическая ротация
      final rotatedCount = await service.autoRotateKeys(
        rotationPeriod: const Duration(days: 90),
        gracePeriod: const Duration(days: 7),
      );

      expect(rotatedCount, equals(3));

      // Проверить, что созданы новые ключи
      final allKeys = await repo.listAll();
      expect(allKeys.length, equals(6)); // 3 старых + 3 новых
    });

    test('autoRotateKeys продолжает при ошибке одного ключа', () async {
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;

      // Создать 2 ключа
      await repo.create(AqApiKey(
        id: 'key1',
        userId: 'user1',
        tenantId: 'tenant1',
        name: 'Key 1',
        keyPrefix: 'aq_live_',
        keyHash: 'hash1',
        permissions: ['read'],
        isActive: true,
        createdAt: now - const Duration(days: 200).inSeconds,
        lastRotatedAt: now - const Duration(days: 100).inSeconds,
      ));

      await repo.create(AqApiKey(
        id: 'key2',
        userId: 'user2',
        tenantId: 'tenant1',
        name: 'Key 2',
        keyPrefix: 'aq_live_',
        keyHash: 'hash2',
        permissions: ['read'],
        isActive: true,
        createdAt: now - const Duration(days: 200).inSeconds,
        lastRotatedAt: now - const Duration(days: 100).inSeconds,
      ));

      // Авторотация должна обработать оба ключа
      final rotatedCount = await service.autoRotateKeys(
        rotationPeriod: const Duration(days: 90),
      );

      expect(rotatedCount, equals(2));
    });

    test('findKeysNeedingRotation проверяет createdAt если lastRotatedAt == null', () async {
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;

      // Ключ создан 100 дней назад, никогда не ротировался
      final oldKey = await repo.create(AqApiKey(
        id: 'key1',
        userId: 'user1',
        tenantId: 'tenant1',
        name: 'Never Rotated',
        keyPrefix: 'aq_live_',
        keyHash: 'hash1',
        permissions: ['read'],
        isActive: true,
        createdAt: now - const Duration(days: 100).inSeconds,
        lastRotatedAt: null,
      ));

      final needsRotation = await service.findKeysNeedingRotation(
        rotationPeriod: const Duration(days: 90),
      );

      expect(needsRotation.length, equals(1));
      expect(needsRotation.first.id, equals(oldKey.id));
    });
  });
}
