// lib/server.dart
//
// Auth Service HTTP server

import 'dart:io';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as io;
import 'package:aq_security/aq_security_server.dart';
import 'config.dart';
import 'middleware/error_handler.dart';

/// Auth Service server
///
/// Provides full authentication and authorization services:
/// - Multiple auth providers (Google OAuth, Email/Password, API Keys)
/// - RBAC system (roles, permissions, policies)
/// - Token management (JWT with refresh tokens)
/// - Introspection endpoint for resource servers
final class AuthServiceServer {
  AuthServiceServer(this.config);

  final AuthServiceConfig config;
  HttpServer? _server;
  late AQAuthServer authServer;

  /// Start the server
  Future<void> start() async {
    print('🔧 Configuring auth service...');

    // Create SecurityConfig
    final securityConfig = SecurityConfig(
      jwtSecret: config.jwtSecret,
      dataServiceUrl: config.dataServiceUrl,
      googleOAuth: config.hasGoogleOAuth
          ? GoogleOAuthConfig(
              clientId: config.googleClientId!,
              clientSecret: config.googleClientSecret!,
              redirectUri: config.googleRedirectUri!,
            )
          : null,
      githubOAuth: config.hasGithubOAuth
          ? GitHubOAuthConfig(
              clientId: config.githubClientId!,
              clientSecret: config.githubClientSecret!,
              redirectUri: config.githubRedirectUri!,
            )
          : null,
      rateLimitConfig: RateLimitConfig(
        maxRequests: 100,
        windowSeconds: 60,
      ),
      corsConfig: CorsConfig(
        allowedOrigins: config.allowedOrigins,
      ),
    );

    print('   JWT Secret: ${config.jwtSecret.substring(0, 8)}...');
    print('   Data Service: ${config.dataServiceUrl}');
    print('   Google OAuth: ${config.hasGoogleOAuth ? "✅" : "❌"}');
    print('   GitHub OAuth: ${config.hasGithubOAuth ? "✅" : "❌"}');
    print('   CORS Origins: ${config.allowedOrigins.join(", ")}');

    // Create AQAuthServer
    print('🚀 Initializing auth server...');
    authServer = AQAuthServer(securityConfig);
    await authServer.initialize();
    print('✅ Auth server initialized');

    // Create HTTP server
    print('🌐 Starting HTTP server...');
    final handler = _createHandler();
    _server = await io.serve(handler, InternetAddress.anyIPv4, config.port);
    print('✅ HTTP server started');
  }

  /// Create request handler with middleware pipeline
  Handler _createHandler() {
    // Middleware pipeline
    final pipeline = Pipeline()
        .addMiddleware(logRequests())
        .addMiddleware(errorHandlerMiddleware())
        .addHandler(authServer.handler);

    return pipeline;
  }

  /// Stop the server
  Future<void> stop() async {
    print('🛑 Stopping server...');
    await _server?.close(force: true);
    await authServer.dispose();
    print('✅ Server stopped');
  }
}
