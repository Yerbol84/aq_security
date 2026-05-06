// pkgs/aq_security/lib/src/client/aq_security.dart
//
// Единая точка инициализации security layer.
//
// RULE-5: Никакой код снаружи не должен вызывать напрямую:
//   - setSecurityServiceInstance(...)
//   - IVaultSecurityProtocol.initialize(...)
//   - IAuthContext.initialize(...)
// Все три вызываются только здесь.

import 'package:aq_schema/security/security.dart';
import 'aq_security_service.dart';
import 'aq_vault_security_protocol.dart';
import '../shared/security_config.dart';

/// Единая точка инициализации security layer.
///
/// ## Использование
///
/// ```dart
/// // main.dart
/// final service = await AqSecurity.init(
///   config: SecurityClientConfig(authEndpoint: 'https://auth.example.com'),
/// );
/// ```
///
/// После вызова доступны:
/// - `ISecurityService.instance` — auth сервис
/// - `IAuthContext.instance` — контекст для data layer
/// - `IVaultSecurityProtocol.instance` — протокол безопасности для vault
final class AqSecurity {
  AqSecurity._();

  /// Инициализировать security layer.
  ///
  /// [config] — клиентская конфигурация (без jwtSecret).
  /// [jwtSecret] — опционально, для offline валидации токенов (workers/backend).
  /// [introspectionEndpoint] — опционально, для IVaultSecurityProtocol.
  ///   Если не передан — используется `${config.authEndpoint}/api/introspect`.
  /// [encryptionKey] — опционально, для шифрования полей в vault.
  /// [resourcePermissions] — опционально, для RLAC.
  static Future<AQSecurityService> init({
    required SecurityClientConfig config,
    String? jwtSecret,
    String? introspectionEndpoint,
    String? encryptionKey,
    IResourcePermissionService? resourcePermissions,
  }) async {
    // 1. Создать сервис через существующий AQSecurityClient
    final codec = TokenCodec(
      secret: jwtSecret ?? 'client-only-no-offline-validation-${config.authEndpoint}',
    );
    final validator = TokenValidator(codec: codec);

    final service = AQSecurityService.create(
      endpoint: config.authEndpoint,
      validator: validator,
    );

    // 2. Зарегистрировать ISecurityService singleton
    setSecurityServiceInstance(service);

    // 3. Зарегистрировать IAuthContext singleton
    IAuthContext.initialize(_AqAuthContextImpl(service));

    // 4. Зарегистрировать IVaultSecurityProtocol singleton (если есть encryptionKey)
    if (encryptionKey != null) {
      final endpoint = introspectionEndpoint ??
          '${config.authEndpoint}/api/introspect';
      IVaultSecurityProtocol.initialize(
        AqVaultSecurityProtocol(
          introspectionEndpoint: endpoint,
          encryptionKey: encryptionKey,
          auditEndpoint: '${config.authEndpoint}/rbac/logs/access',
          resourcePermissions: resourcePermissions,
        ),
      );
    }

    // 5. Восстановить сессию
    await service.restoreSession();

    return service;
  }
}

/// Реализация IAuthContext поверх AQSecurityService.
final class _AqAuthContextImpl implements IAuthContext {
  _AqAuthContextImpl(this._service);
  final AQSecurityService _service;

  @override
  Future<String?> get currentToken => _service.accessToken;

  @override
  Future<String> get currentTenantId async =>
      _service.currentTenant?.id ?? 'system';

  @override
  Future<String?> get currentUserId async => _service.currentUser?.id;
}
