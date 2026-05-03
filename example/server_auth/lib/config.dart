// lib/config.dart
//
// Configuration for Auth Service

import 'dart:io';

/// Configuration for the auth service
final class AuthServiceConfig {
  const AuthServiceConfig({
    required this.port,
    required this.dataServiceUrl,
    required this.jwtSecret,
    required this.redisUrl,
    required this.allowedOrigins,
    required this.isDev,
    this.googleClientId,
    this.googleClientSecret,
    this.googleRedirectUri,
    this.githubClientId,
    this.githubClientSecret,
    this.githubRedirectUri,
  });

  final int port;
  final String dataServiceUrl;
  final String jwtSecret;
  final String redisUrl;
  final List<String> allowedOrigins;
  final bool isDev;

  // OAuth providers (optional)
  final String? googleClientId;
  final String? googleClientSecret;
  final String? googleRedirectUri;
  final String? githubClientId;
  final String? githubClientSecret;
  final String? githubRedirectUri;

  /// Load configuration from environment variables
  factory AuthServiceConfig.fromEnv() {
    final originsStr = Platform.environment['ALLOWED_ORIGINS'] ??
        'http://localhost:3000,http://localhost:8081';

    final jwtSecret = Platform.environment['AUTH_JWT_SECRET'];
    if (jwtSecret == null || jwtSecret.length < 32) {
      throw Exception(
        'AUTH_JWT_SECRET is required and must be at least 32 characters',
      );
    }

    return AuthServiceConfig(
      port: int.parse(Platform.environment['AUTH_SERVICE_PORT'] ?? '8080'),
      dataServiceUrl: Platform.environment['AUTH_DATA_SERVICE_URL'] ??
          'http://localhost:8090',
      jwtSecret: jwtSecret,
      redisUrl: Platform.environment['REDIS_URL'] ?? 'redis://localhost:6379',
      allowedOrigins: originsStr.split(',').map((s) => s.trim()).toList(),
      isDev: Platform.environment['ENV'] != 'production',
      googleClientId: Platform.environment['GOOGLE_CLIENT_ID'],
      googleClientSecret: Platform.environment['GOOGLE_CLIENT_SECRET'],
      googleRedirectUri: Platform.environment['GOOGLE_REDIRECT_URI'],
      githubClientId: Platform.environment['GITHUB_CLIENT_ID'],
      githubClientSecret: Platform.environment['GITHUB_CLIENT_SECRET'],
      githubRedirectUri: Platform.environment['GITHUB_REDIRECT_URI'],
    );
  }

  /// Check if Google OAuth is configured
  bool get hasGoogleOAuth =>
      googleClientId != null &&
      googleClientSecret != null &&
      googleRedirectUri != null;

  /// Check if GitHub OAuth is configured
  bool get hasGithubOAuth =>
      githubClientId != null &&
      githubClientSecret != null &&
      githubRedirectUri != null;

  @override
  String toString() => 'AuthServiceConfig(port: $port, isDev: $isDev)';
}
