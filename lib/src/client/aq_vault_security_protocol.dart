// pkgs/aq_security/lib/src/client/aq_vault_security_protocol.dart
//
// Реализация IVaultSecurityProtocol для dart_vault Data Layer.
//
// Клиент для auth сервиса — проверяет права через introspection endpoint,
// шифрует чувствительные поля, валидирует данные, логирует операции.

import 'package:aq_schema/security/interfaces/clients_protocols/i_data_layer_as_clietn_secure_protocol.dart';
import 'package:aq_schema/security/models/aq_token_claims.dart';
import 'package:aq_schema/security/models/aq_resource_permission.dart';
import 'package:aq_schema/security/models/access_decision.dart';
import 'package:aq_schema/security/security.dart';
import 'package:aq_schema/security/token/token_codec.dart';
import 'package:aq_schema/http/responses/validation_field_error.dart';
import 'introspection_client.dart';
import 'field_encryption_service.dart';
import '../server/rate_limiting/rate_limiter.dart';
import '../server/dos_protection/request_validator.dart';

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
    RateLimitConfig? rateLimitConfig,
    RequestValidationConfig? validationConfig,
    Map<String, EncryptionConfig>? encryptionConfigs,
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
        _requestValidator = RequestValidator(
          config: validationConfig ?? const RequestValidationConfig(),
        ),
        _encryptionConfigs = encryptionConfigs ?? {};

  final IntrospectionClient _introspectionClient;
  final FieldEncryptionService _encryptionService;
  final RateLimiter _rateLimiter;
  final RequestValidator _requestValidator;
  final Map<String, EncryptionConfig> _encryptionConfigs;

  // Кэш для claims (TTL 5 минут)
  final Map<String, _CachedClaims> _claimsCache = {};

  // Сервис управления правами на ресурсы (lazy initialization)
  IResourcePermissionService? _resourcePermissionService;

  // ══════════════════════════════════════════════════════════════════════════
  // Подсервисы
  // ══════════════════════════════════════════════════════════════════════════

  @override
  IResourcePermissionService get resourcePermissions {
    // TODO: Инициализировать реальную реализацию
    // Пока возвращаем заглушку
    _resourcePermissionService ??= _NoOpResourcePermissionService();
    return _resourcePermissionService!;
  }

  // ══════════════════════════════════════════════════════════════════════════
  // Извлечение контекста из запроса
  // ══════════════════════════════════════════════════════════════════════════

  @override
  Future<AqTokenClaims?> extractClaims(Map<String, String> headers) async {
    final authHeader = headers['authorization'] ?? headers['Authorization'];
    if (authHeader == null || authHeader.isEmpty) {
      return null; // Анонимный запрос
    }

    // Извлечь токен из "Bearer <token>"
    final token =
        authHeader.startsWith('Bearer ') ? authHeader.substring(7) : authHeader;

    // Проверить кэш
    final cached = _claimsCache[token];
    if (cached != null && !cached.isExpired) {
      return cached.claims;
    }

    // Декодировать токен (без проверки подписи — это сделает introspection)
    try {
      final claims = TokenCodec.decodeUnverified(token);

      // Кэшировать на 5 минут
      _claimsCache[token] = _CachedClaims(
        claims: claims,
        cachedAt: DateTime.now(),
      );

      return claims;
    } catch (e) {
      return null; // Невалидный токен
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
    // Анонимные запросы запрещены
    if (claims == null) {
      return AccessDecision.deny(reason: 'Anonymous access not allowed');
    }

    // Маппинг коллекции на ResourceType
    final resourceType = _mapCollectionToResourceType(collection);

    // Получить токен из кэша (он там должен быть после extractClaims)
    final token = _findTokenByClaims(claims);
    if (token == null) {
      return AccessDecision.deny(reason: 'Token not found');
    }

    try {
      // Вызвать introspection endpoint
      final response = await _introspectionClient.introspect(
        token: token,
        resource: resourceType.value,
        action: action,
        resourceId: entityId ?? '*',
      );

      if (!response.active) {
        return AccessDecision.deny(reason: 'Token is not active');
      }

      if (!response.allowed) {
        return AccessDecision.deny(
          reason: response.reason ?? 'Access denied',
        );
      }

      return AccessDecision.allow(reason: 'Access granted');
    } on IntrospectionException catch (e) {
      return AccessDecision.deny(reason: 'Introspection failed: ${e.message}');
    }
  }

  /// Маппинг коллекции на ResourceType.
  ///
  /// Выбрасывает исключение для неизвестных коллекций.
  ResourceType _mapCollectionToResourceType(String collection) {
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
        throw UnknownCollectionException(
          'Unknown collection: $collection. '
          'All collections must be explicitly mapped to ResourceType.',
        );
    }
  }

  /// Найти токен по claims в кэше.
  String? _findTokenByClaims(AqTokenClaims claims) {
    for (final entry in _claimsCache.entries) {
      if (entry.value.claims.jti == claims.jti) {
        return entry.key;
      }
    }
    return null;
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

    // 2. Проверить на SQL injection паттерны
    for (final entry in data.entries) {
      if (entry.value is String) {
        final value = entry.value as String;
        if (_containsSqlInjection(value)) {
          errors.add(ValidationFieldError(
            field: entry.key,
            message: 'Potential SQL injection detected',
            code: 'sql_injection',
          ));
        }
      }
    }

    // 3. Проверить на XSS паттерны
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

  /// Проверить на SQL injection паттерны.
  bool _containsSqlInjection(String value) {
    final patterns = [
      RegExp(r"('|(--)|;|\*|\/\*|\*\/)", caseSensitive: false),
      RegExp(
          r'\b(union|select|insert|update|delete|drop|create|alter|exec|execute)\b',
          caseSensitive: false),
    ];

    for (final pattern in patterns) {
      if (pattern.hasMatch(value)) {
        return true;
      }
    }

    return false;
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
    // TODO: Реализовать audit logging
    // Пока просто игнорируем — обсудим отдельно
  }
}

// ══════════════════════════════════════════════════════════════════════════
// Вспомогательные классы
// ══════════════════════════════════════════════════════════════════════════

/// Кэшированные claims с TTL.
final class _CachedClaims {
  _CachedClaims({
    required this.claims,
    required this.cachedAt,
  });

  final AqTokenClaims claims;
  final DateTime cachedAt;

  bool get isExpired {
    final age = DateTime.now().difference(cachedAt);
    return age > const Duration(minutes: 5);
  }
}

/// Исключение для неизвестной коллекции.
final class UnknownCollectionException implements Exception {
  const UnknownCollectionException(this.message);

  final String message;

  @override
  String toString() => 'UnknownCollectionException: $message';
}

/// NoOp реализация IResourcePermissionService (заглушка).
///
/// Используется до тех пор, пока не будет реализован полноценный сервис
/// управления правами на ресурсы.
///
/// Все методы возвращают пустые результаты или ничего не делают.
final class _NoOpResourcePermissionService
    implements IResourcePermissionService {
  @override
  Future<void> grant({
    required String resourceId,
    required String userId,
    required AccessLevel level,
    required String grantedBy,
    DateTime? expiresAt,
  }) async {
    // NoOp: ничего не делаем
  }

  @override
  Future<void> revoke({
    required String resourceId,
    required String userId,
    required String revokedBy,
  }) async {
    // NoOp: ничего не делаем
  }

  @override
  Future<List<AqResourcePermission>> list(String resourceId) async {
    // NoOp: возвращаем пустой список
    return [];
  }

  @override
  Future<bool> hasAccess({
    required String resourceId,
    required String userId,
    required AccessLevel minimumLevel,
  }) async {
    // NoOp: всегда возвращаем false
    return false;
  }

  @override
  Future<List<String>> listUserResources({
    required String userId,
    AccessLevel? minimumLevel,
  }) async {
    // NoOp: возвращаем пустой список
    return [];
  }

  @override
  Future<void> copyPermissions({
    required String sourceResourceId,
    required String targetResourceId,
    required String copiedBy,
  }) async {
    // NoOp: ничего не делаем
  }

  @override
  Future<void> deleteAllPermissions({
    required String resourceId,
    required String deletedBy,
  }) async {
    // NoOp: ничего не делаем
  }
}
