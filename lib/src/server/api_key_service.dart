// pkgs/aq_security/lib/src/server/api_key_service.dart
//
// Server-only. API key issuance, validation, revocation.
// Raw key shown ONCE. Only SHA-256 hash stored.
// Used by: workers, data service, external integrations.

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:uuid/uuid.dart';
import 'package:aq_schema/security/security.dart';

final class ApiKeyService {
  ApiKeyService({required this.repo});

  final IApiKeyRepository repo;

  static final _uuid = Uuid();

  // ── Key format ────────────────────────────────────────────────────────────
  // aq_live_<32 random bytes as hex>  - production keys
  // aq_test_<32 random bytes as hex>  - development/testing keys
  // Prefix → easy to identify in logs/code.

  static const _prefixLive = 'aq_live_';
  static const _prefixTest = 'aq_test_';

  // ── Issue ─────────────────────────────────────────────────────────────────

  /// Create a new API key. Returns the raw key (shown once) + the stored record.
  Future<({String rawKey, AqApiKey record})> create({
    required String userId,
    required String tenantId,
    required String name,
    required List<String> permissions,
    int? expiresAt,
    bool isTest = false,
    String? replacesKeyId,
  }) async {
    final rawKey = _generate(isTest: isTest);
    final keyHash = _hash(rawKey);
    final keyPrefix = rawKey.substring(0, 14); // 'aq_live_' or 'aq_test_' + 6 chars

    final record = await repo.create(AqApiKey(
      id: _uuid.v4(),
      userId: userId,
      tenantId: tenantId,
      name: name,
      keyPrefix: keyPrefix,
      keyHash: keyHash,
      permissions: permissions,
      isActive: true,
      expiresAt: expiresAt,
      createdAt: _now(),
      lastRotatedAt: replacesKeyId != null ? _now() : null,
    ));

    return (rawKey: rawKey, record: record);
  }

  // ── Validate ──────────────────────────────────────────────────────────────

  /// Validate raw API key. Returns the record if valid, null otherwise.
  Future<AqApiKey?> validate(String rawKey) async {
    if (!rawKey.startsWith(_prefixLive) && !rawKey.startsWith(_prefixTest)) {
      return null;
    }

    final keyHash = _hash(rawKey);
    final record = await repo.findByHash(keyHash);
    if (record == null) return null;
    if (!record.isActive) return null;
    if (record.isExpired) return null;

    // Update last used
    await repo.updateLastUsed(record.id, _now());

    return record;
  }

  // ── Rotate ────────────────────────────────────────────────────────────────

  /// Rotate an API key: create new key, keep old one active for grace period.
  /// Returns new raw key (shown once) + new record.
  Future<({String rawKey, AqApiKey record, AqApiKey? oldRecord})> rotate(
    String oldKeyId, {
    Duration? gracePeriod,
  }) async {
    final oldKey = await repo.findById(oldKeyId);
    if (oldKey == null) {
      throw Exception('API key not found: $oldKeyId');
    }

    // Create new key with same settings
    final isTest = oldKey.keyPrefix.startsWith(_prefixTest);
    final result = await create(
      userId: oldKey.userId,
      tenantId: oldKey.tenantId,
      name: '${oldKey.name} (rotated)',
      permissions: oldKey.permissions,
      expiresAt: oldKey.expiresAt,
      isTest: isTest,
      replacesKeyId: oldKeyId,
    );

    // Handle old key based on grace period
    if (gracePeriod != null && gracePeriod > Duration.zero) {
      // Keep old key active for grace period
      final graceExpiresAt = _now() + gracePeriod.inSeconds;
      final updatedOldKey = await repo.update(oldKey.copyWith(
        expiresAt: graceExpiresAt,
        updatedAt: _now(),
      ));
      return (rawKey: result.rawKey, record: result.record, oldRecord: updatedOldKey);
    } else {
      // Revoke old key immediately
      await repo.revoke(oldKeyId);
      return (rawKey: result.rawKey, record: result.record, oldRecord: null);
    }
  }

  /// Проверяет API keys на необходимость ротации.
  /// Возвращает список ключей, которые нужно ротировать.
  Future<List<AqApiKey>> findKeysNeedingRotation({
    Duration? rotationPeriod,
    Duration? expirationWarning,
  }) async {
    final allKeys = await repo.listAll();
    final now = _now();
    final needsRotation = <AqApiKey>[];

    for (final key in allKeys) {
      if (!key.isActive) continue;

      // Проверка на истечение срока
      if (expirationWarning != null && key.expiresAt != null) {
        final warningTime = key.expiresAt! - expirationWarning.inSeconds;
        if (now >= warningTime && now < key.expiresAt!) {
          needsRotation.add(key);
          continue;
        }
      }

      // Проверка на период ротации
      if (rotationPeriod != null && key.lastRotatedAt != null) {
        final nextRotation = key.lastRotatedAt! + rotationPeriod.inSeconds;
        if (now >= nextRotation) {
          needsRotation.add(key);
          continue;
        }
      }

      // Проверка на период с момента создания (если lastRotatedAt == null)
      if (rotationPeriod != null && key.lastRotatedAt == null) {
        final nextRotation = key.createdAt + rotationPeriod.inSeconds;
        if (now >= nextRotation) {
          needsRotation.add(key);
        }
      }
    }

    return needsRotation;
  }

  /// Автоматическая ротация ключей по расписанию.
  /// Возвращает количество ротированных ключей.
  Future<int> autoRotateKeys({
    Duration rotationPeriod = const Duration(days: 90),
    Duration gracePeriod = const Duration(days: 7),
    Duration expirationWarning = const Duration(days: 14),
  }) async {
    final keysToRotate = await findKeysNeedingRotation(
      rotationPeriod: rotationPeriod,
      expirationWarning: expirationWarning,
    );

    var rotatedCount = 0;
    for (final key in keysToRotate) {
      try {
        await rotate(key.id, gracePeriod: gracePeriod);
        rotatedCount++;
      } catch (e) {
        // Log error but continue with other keys
        // TODO: Add proper logging
        print('Failed to rotate key ${key.id}: $e');
      }
    }

    return rotatedCount;
  }

  // ── Revoke ────────────────────────────────────────────────────────────────

  Future<void> revoke(String id) => repo.revoke(id);

  Future<List<AqApiKey>> listForUser(String userId) =>
      repo.listByUser(userId);

  // ── Helpers ────────────────────────────────────────────────────────────────

  static String _generate({bool isTest = false}) {
    final rng = Random.secure();
    final bytes = Uint8List(32);
    for (var i = 0; i < bytes.length; i++) {
      bytes[i] = rng.nextInt(256);
    }
    final prefix = isTest ? _prefixTest : _prefixLive;
    return '$prefix${_toHex(bytes)}';
  }

  static String _hash(String key) {
    final bytes = utf8.encode(key);
    return sha256.convert(bytes).toString();
  }

  static String _toHex(Uint8List bytes) =>
      bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

  static int _now() => DateTime.now().millisecondsSinceEpoch ~/ 1000;
}
