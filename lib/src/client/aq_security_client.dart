// pkgs/aq_security/lib/src/client/aq_security_client.dart
//
// Entry point for any client node (Flutter web, worker, data service).
// Give it the endpoint → get back a fully configured AQSecurityService.
//
// Usage (Flutter app):
//   final service = await AQSecurityClient.init('https://auth.aqstudio.dev');
//
// Usage (worker / Dart CLI):
//   final service = await AQSecurityClient.init(
//     Platform.environment['AUTH_ENDPOINT']!,
//   );
//   await service.loginWithApiKey(Platform.environment['API_KEY']!);

import 'package:aq_schema/security/security.dart';
import 'aq_security_service.dart';
import 'http_auth_transport.dart';

final class AQSecurityClient {
  AQSecurityClient._();

  /// Initialize the security service.
  ///
  /// [endpoint] — base URL of the auth server.
  /// [jwtSecret] — optional. If provided, tokens are validated locally
  ///   without a network call. Recommended for workers and backend services.
  ///   Leave null for Flutter/web clients — they use POST /auth/validate.
  ///
  /// Returns the ready-to-use [AQSecurityService].
  static Future<AQSecurityService> init(
    String endpoint, {
    String? jwtSecret,
  }) async {
    if (_serviceInstance != null) return _serviceInstance!;
    // Fetch server public config (validates connectivity + gets config)
    await HttpAuthTransport(baseUrl: endpoint).healthCheck();

    final codec =
        TokenCodec(secret: jwtSecret ?? _deriveClientSecret(endpoint));
    final validator = TokenValidator(codec: codec);

    final service = AQSecurityService.create(
      endpoint: endpoint,
      validator: validator,
    );

    // Register as singleton instance for ISecurityService
    setSecurityServiceInstance(service);

    // Attempt to restore persisted session
    await service.restoreSession();
    _serviceInstance ??= service;
    return _serviceInstance!;
  }

  static AQSecurityService? _serviceInstance;
  static AQSecurityService get service => _serviceInstance!;

  /// Derive a deterministic-but-safe client secret when jwtSecret is not provided.
  /// Client-side validation without the real secret = we rely on server validation.
  /// This secret is intentionally wrong — validateAccess on client without secret
  /// will always "fail" signature check and fall through to server validation.
  ///
  /// Workers and services MUST provide jwtSecret for offline validation.
  static String _deriveClientSecret(String endpoint) =>
      'client-only-no-offline-validation-$endpoint';
}
