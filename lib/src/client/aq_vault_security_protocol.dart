// pkgs/aq_security/lib/src/client/aq_vault_security_protocol.dart
//
// Реализация IVaultSecurityProtocol для dart_vault Data Layer.
//
// Клиент для auth сервиса — проверяет права через introspection endpoint,
// шифрует чувствительные поля, валидирует данные, логирует операции.

import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:aq_schema/security/security.dart';
import 'package:aq_schema/cache.dart';
import 'package:aq_schema/http/responses/validation_field_error.dart';
import 'introspection_client.dart';
import 'field_encryption_service.dart';
import '../server/rate_limiting/rate_limiter.dart';

/// Реализация IVaultSecurityProtocol для клиента.
///
/// ## Инициализация
///
/// ```dart
/// void main() async {
///   // 1. Создать protocol
///   final protocol = AqVaultSecurityProtocol(
///     introspectionEndpoint: 'https://auth.example.com/introspect',
///     encryptionKey: Platform.environment['ENCRYPTION_KEY']!,
///   );
///
///   // 2. Зарегистрировать singleton
///   IVaultSecurityProtocol.initialize(protocol);
///
///   // 3. Использовать в dart_vault
///   final storage = PostgresVaultStorage(
///     pool: pool,
///     tenantId: 'tenant-1',
///     headers: request.headers,
///   );
/// }
/// ```
final class AqVaultSecurityProtocol implements IVaultSecurityProtocol {
  AqVaultSecurityProtocol({
    required String introspectionEndpoint,
    required String encryptionKey,
    String? auditEndpoint,
    IResourcePermissionService? resourcePermissions,
    RateLimitConfig? rateLimitConfig,
    Map<String, EncryptionConfig>? encryptionConfigs,
    IAQCache? claimsCache,
    IAQCache? decisionsCache,
  })  : _introspectionClient = IntrospectionClient(
          introspectionEndpoint: introspectionEndpoint,
        ),
        _encryptionService = FieldEncryptionService(
          encryptionKey: encryptionKey,
        ),
        _rateLimiter = RateLimiter(
          config: rateLimitConfig ??
              const RateLimitConfig(
                maxRequests: 1000,
                windowSeconds: 60,
              ),
        ),
        _encryptionConfigs = encryptionConfigs ?? {},
        _resourcePermissions = resourcePermissions,
        _auditEndpoint = auditEndpoint,
        _claimsCache = claimsCache,
        _decisionsCache = decisionsCache;

  final IntrospectionClient _introspectionClient;
  final FieldEncryptionService _encryptionService;
  final RateLimiter _rateLimiter;
  final Map<String, EncryptionConfig> _encryptionConfigs;
  final IResourcePermissionService? _resourcePermissions;
  final String? _auditEndpoint;
  final IAQCache? _claimsCache;
  final IAQCache? _decisionsCache;

  // ══════════════════════════════════════════════════════════════════════════
  // Подсервисы
  // ══════════════════════════════════════════════════════════════════════════

  @override
  IResourcePermissionService get resourcePermissions {
    if (_resourcePermissions == null) {
      throw StateError(
        'ResourcePermissionService not configured. '
        'Pass resourcePermissions: to AqVaultSecurityProtocol constructor.',
      );
    }
    return _resourcePermissions;
  }

  // ══════════════════════════════════════════════════════════════════════════
  // Извлечение контекста из запроса
  // ══════════════════════════════════════════════════════════════════════════

  @override
  Future<AqTokenClaims?> extractClaims(Map<String, String> headers) async {
    final authHeader = headers['authorization'] ?? headers['Authorization'];
    if (authHeader == null || authHeader.isEmpty) return null;

    final token =
        authHeader.startsWith('Bearer ') ? authHeader.substring(7) : authHeader;

    try {
      final claims = TokenCodec.decodeUnverified(token);

      if (_claimsCache != null) {
        await _claimsCache.put(claims);
      }

      return claims;
    } catch (e) {
      return null;
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // Проверка прав доступа
  // ══════════════════════════════════════════════════════════════════════════

  @override
  Future<AccessDecision> canRead({
    required AqTokenClaims? claims,
    required String collection,
    String? entityId,
  }) async {
    return _checkAccess(
      claims: claims,
      collection: collection,
      action: 'read',
      entityId: entityId,
    );
  }

  @override
  Future<AccessDecision> canWrite({
    required AqTokenClaims? claims,
    required String collection,
    String? entityId,
    required Map<String, dynamic> data,
  }) async {
    return _checkAccess(
      claims: claims,
      collection: collection,
      action: 'write',
      entityId: entityId,
    );
  }

  @override
  Future<AccessDecision> canDelete({
    required AqTokenClaims? claims,
    required String collection,
    required String entityId,
  }) async {
    return _checkAccess(
      claims: claims,
      collection: collection,
      action: 'delete',
      entityId: entityId,
    );
  }

  @override
  Future<AccessDecision> canPublish({
    required AqTokenClaims? claims,
    required String collection,
    required String entityId,
  }) async {
    return _checkAccess(
      claims: claims,
      collection: collection,
      action: 'publish',
      entityId: entityId,
    );
  }

  @override
  Future<AccessDecision> canGrant({
    required AqTokenClaims? claims,
    required String collection,
    required String entityId,
    required String targetUserId,
    required AccessLevel level,
  }) async {
    return _checkAccess(
      claims: claims,
      collection: collection,
      action: 'grant',
      entityId: entityId,
    );
  }

  /// Общая логика проверки доступа через introspection.
  Future<AccessDecision> _checkAccess({
    required AqTokenClaims? claims,
    required String collection,
    required String action,
    String? entityId,
  }) async {
    if (claims == null) {
      return AccessDecision.deny(reason: 'Anonymous access not allowed');
    }

    final resourceType = _mapCollectionToResourceType(collection);
    if (resourceType == null) {
      return AccessDecision.deny(reason: 'Unknown collection: $collection');
    }

    final permission = '${resourceType.value}:$action';
    final cacheKey = 'decision:${claims.sub}:$permission';

    // Проверить кэш решений
    if (_decisionsCache != null) {
      final cached = await _decisionsCache.get<AccessDecision>(cacheKey);
      if (cached != null) return cached;
    }

    try {
      final response = await _introspectionClient.introspect(
        token: claims.jti,
        resource: resourceType.value,
        action: action,
        resourceId: entityId ?? '*',
      );

      if (!response.active) {
        return AccessDecision.deny(reason: 'Token is not active');
      }

      final decision = response.allowed
          ? AccessDecision.withCacheKey(
              userId: claims.sub,
              permission: permission,
              allowed: true,
              reason: 'Access granted',
            )
          : AccessDecision.withCacheKey(
              userId: claims.sub,
              permission: permission,
              allowed: false,
              reason: response.reason ?? 'Access denied',
            );

      if (_decisionsCache != null) {
        await _decisionsCache.put(decision);
      }

      return decision;
    } on IntrospectionException catch (e) {
      return AccessDecision.deny(reason: 'Introspection failed: ${e.message}');
    }
  }

  /// Маппинг коллекции на ResourceType.
  ///
  /// Возвращает null для неизвестных коллекций — вызывающий код должен
  /// вернуть AccessDecision.deny (principle of least privilege).
  ResourceType? _mapCollectionToResourceType(String collection) {
    switch (collection) {
      case 'projects':
      case 'aq_studio_projects':
        return ResourceType.project;
      case 'graphs':
      case 'workflow_graphs':
        return ResourceType.graph;
      case 'instructions':
      case 'instruction_graphs':
        return ResourceType.instruction;
      case 'prompts':
      case 'prompt_graphs':
        return ResourceType.prompt;
      case 'datasets':
        return ResourceType.dataset;
      case 'models':
        return ResourceType.model;
      case 'api_keys':
        return ResourceType.apiKey;
      case 'sessions':
        return ResourceType.session;
      default:
        return null;
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // Rate Limiting
  // ══════════════════════════════════════════════════════════════════════════

  @override
  Future<bool> checkRateLimit({
    required AqTokenClaims? claims,
    required String operation,
    String? ip,
  }) async {
    // Ключ для rate limiting: userId или IP
    final key = claims != null ? 'user:${claims.sub}' : 'ip:${ip ?? "unknown"}';

    final result = _rateLimiter.checkLimit(key);

    return result.allowed;
  }

  // ══════════════════════════════════════════════════════════════════════════
  // Валидация данных
  // ══════════════════════════════════════════════════════════════════════════

  @override
  Future<List<ValidationFieldError>> validateData({
    required String collection,
    required Map<String, dynamic> data,
  }) async {
    final errors = <ValidationFieldError>[];

    // 1. Проверить размер данных
    final jsonString = data.toString();
    if (jsonString.length > 10 * 1024 * 1024) {
      // 10 MB
      errors.add(const ValidationFieldError(
        field: '_size',
        message: 'Data size exceeds 10 MB',
        code: 'data_too_large',
      ));
    }

    // SQL injection prevention — ответственность ORM/query builder в data layer,
    // не security layer. Regex-проверки здесь создают ложное ощущение безопасности
    // и ломают легитимные данные (например, апостроф в имени O'Brien).

    // 2. Проверить на XSS паттерны
    for (final entry in data.entries) {
      if (entry.value is String) {
        final value = entry.value as String;
        if (_containsXss(value)) {
          errors.add(ValidationFieldError(
            field: entry.key,
            message: 'Potential XSS detected',
            code: 'xss',
          ));
        }
      }
    }

    return errors;
  }

  /// Проверить на XSS паттерны.
  bool _containsXss(String value) {
    final patterns = [
      RegExp(r'<script[^>]*>.*?</script>', caseSensitive: false),
      RegExp(r'javascript:', caseSensitive: false),
      RegExp(r'on\w+\s*=', caseSensitive: false), // onclick=, onerror=, etc.
    ];

    for (final pattern in patterns) {
      if (pattern.hasMatch(value)) {
        return true;
      }
    }

    return false;
  }

  // ══════════════════════════════════════════════════════════════════════════
  // Шифрование
  // ══════════════════════════════════════════════════════════════════════════

  @override
  Future<Map<String, dynamic>> encryptSensitiveFields({
    required AqTokenClaims? claims,
    required String collection,
    required Map<String, dynamic> data,
  }) async {
    // Получить конфигурацию шифрования для коллекции
    final config = _encryptionConfigs[collection];

    // Если конфигурации нет — шифрование не применяется
    if (config == null) {
      return data;
    }

    return _encryptionService.encryptFields(
      data: data,
      config: config,
    );
  }

  @override
  Future<Map<String, dynamic>> decryptSensitiveFields({
    required AqTokenClaims? claims,
    required String collection,
    required Map<String, dynamic> data,
  }) async {
    // Получить конфигурацию шифрования для коллекции
    final config = _encryptionConfigs[collection];

    // Если конфигурации нет — расшифрование не применяется
    if (config == null) {
      return data;
    }

    return _encryptionService.decryptFields(
      data: data,
      config: config,
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // Аудит
  // ══════════════════════════════════════════════════════════════════════════

  @override
  Future<void> logOperation({
    required AqTokenClaims? claims,
    required String operation,
    required String collection,
    String? entityId,
    required bool success,
    String? errorMessage,
  }) async {
    if (claims == null || _auditEndpoint == null) return;
    final endpoint = _auditEndpoint;

    // fire-and-forget: не блокируем data layer
    unawaited(Future(() async {
      try {
        await http.post(
          Uri.parse(endpoint),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'userId': claims.sub,
            'tenantId': claims.tid,
            'operation': operation,
            'collection': collection,
            if (entityId != null) 'entityId': entityId,
            'success': success,
            if (errorMessage != null) 'errorMessage': errorMessage,
            'timestamp': DateTime.now().millisecondsSinceEpoch ~/ 1000,
          }),
        );
      } catch (_) {}
    }));
  }
}

// ══════════════════════════════════════════════════════════════════════════
// ══════════════════════════════════════════════════════════════════════════
// Вспомогательные классы
// ══════════════════════════════════════════════════════════════════════════
