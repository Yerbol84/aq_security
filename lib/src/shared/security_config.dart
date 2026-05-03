// pkgs/aq_security/lib/src/shared/security_config.dart
//
// Configuration constants for the security system.
// Shared between client and server.

final class SecurityConfig {
  const SecurityConfig({
    required this.authEndpoint,
    required this.jwtSecret,
    this.accessTokenTtl = const Duration(minutes: 15),
    this.refreshTokenTtl = const Duration(days: 30),
    this.sessionTtl = const Duration(days: 30),
    this.allowedOrigins = const [],
  });

  /// Base URL of the auth server. Example: 'https://auth.aqstudio.dev'
  final String authEndpoint;

  /// HMAC-SHA256 secret. Must be >=32 chars. NEVER expose to client.
  final String jwtSecret;

  /// Allowed CORS origins. Empty list = allow none. Use ['*'] for development only.
  final List<String> allowedOrigins;

  final Duration accessTokenTtl;
  final Duration refreshTokenTtl;
  final Duration sessionTtl;

  int get accessTokenTtlSeconds => accessTokenTtl.inSeconds;
  int get refreshTokenTtlSeconds => refreshTokenTtl.inSeconds;
  int get sessionTtlSeconds => sessionTtl.inSeconds;

  /// Client-safe config (no secret).
  SecurityClientConfig toClientConfig() =>
      SecurityClientConfig(authEndpoint: authEndpoint);
}

/// Safe config for the client — no JWT secret.
final class SecurityClientConfig {
  const SecurityClientConfig({required this.authEndpoint});
  final String authEndpoint;
}
