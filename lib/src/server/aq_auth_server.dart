// pkgs/aq_security/lib/src/server/aq_auth_server.dart
//
// Top-level auth server. Assembles all services and starts Shelf.
// Used by server_apps/aq_auth_service/bin/main.dart.
//
// Usage:
//   final server = AQAuthServer(config: config, repos: repos);
//   await server.start();

import 'dart:io';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';
import 'package:aq_schema/security/security.dart';

import '../shared/security_config.dart';
import 'google_oauth_service.dart';
import 'user_service.dart';
import 'session_service.dart';
import 'token_issuer.dart';
import 'password_service.dart';
import 'api_key_service.dart';
import 'auth_router.dart';
import 'introspection_router.dart';
import 'rbac_router.dart';
import 'middleware/auth_middleware.dart';
import '../rbac/rbac_service.dart';
import '../rbac/access_control_engine.dart';
import 'repositories/rbac_repositories.dart';

/// Repository bundle — inject your implementations here.
final class AuthServerRepos {
  const AuthServerRepos({
    required this.users,
    required this.profiles,
    required this.roles,
    required this.tenants,
    required this.sessions,
    required this.apiKeys,
    required this.storage,
  });

  final IUserRepository users;
  final IProfileRepository profiles;
  final IRoleRepository roles;
  final ITenantRepository tenants;
  final ISessionRepository sessions;
  final IApiKeyRepository apiKeys;
  final dynamic storage; // VaultStorage для RBAC репозиториев
}

final class AQAuthServer {
  AQAuthServer({
    required this.config,
    required this.repos,
    required this.googleConfig,
  });

  final SecurityConfig config;
  final AuthServerRepos repos;
  final GoogleOAuthConfig googleConfig;

  HttpServer? _server;

  // ── Assembled services ─────────────────────────────────────────────────────

  late final TokenCodec _codec = TokenCodec(secret: config.jwtSecret);
  late final TokenValidator _validator = TokenValidator(codec: _codec);
  late final TokenIssuer _issuer = TokenIssuer(config: config, codec: _codec);

  late final SessionService _sessions = SessionService(
    repo: repos.sessions,
    config: config,
  );

  late final PasswordService _passwordService = PasswordService();

  late final UserService _userService = UserService(
    users: repos.users,
    profiles: repos.profiles,
    roles: repos.roles,
    tenants: repos.tenants,
    passwordService: _passwordService,
  );

  late final GoogleOAuthService _googleOAuth = GoogleOAuthService(
    config: googleConfig,
  );

  late final ApiKeyService _apiKeyService = ApiKeyService(repo: repos.apiKeys);

  // RBAC services
  late final RBACVaultRoleRepository _rbacRoleRepo =
      RBACVaultRoleRepository(repos.storage);
  late final VaultUserRoleRepository _rbacUserRoleRepo =
      VaultUserRoleRepository(repos.storage);
  late final VaultPolicyRepository _rbacPolicyRepo =
      VaultPolicyRepository(repos.storage);
  late final VaultAccessLogRepository _rbacAccessLogRepo =
      VaultAccessLogRepository(repos.storage);

  late final AccessControlEngine _rbacEngine = AccessControlEngine(
    roleRepository: _rbacRoleRepo,
    userRoleRepository: _rbacUserRoleRepo,
    policyRepository: _rbacPolicyRepo,
    cache: AccessCache(),
  );

  late final RBACService _rbacService = RBACService(
    engine: _rbacEngine,
    roleRepository: _rbacRoleRepo,
    userRoleRepository: _rbacUserRoleRepo,
    policyRepository: _rbacPolicyRepo,
    accessLogRepository: _rbacAccessLogRepo,
  );

  // ── Start / Stop ───────────────────────────────────────────────────────────

  Future<void> start({int port = 8080, String address = '0.0.0.0'}) async {
    // Seed system roles (idempotent - checks if exists before creating)
    try {
      await _userService.seedSystemRoles();
    } catch (e) {
      // ignore: avoid_print
      print('[AQAuthServer] Warning: Failed to seed system roles: $e');
    }

    // Start session purge timer
    _sessions.startPurgeTimer();

    // Build routers
    final authRouter = AuthRouter(
      googleOAuth: _googleOAuth,
      userService: _userService,
      sessionService: _sessions,
      tokenIssuer: _issuer,
      apiKeyService: _apiKeyService,
      validator: _validator,
    );

    final rbacRouter = RBACRouter(_rbacService);

    final introspectionRouter = IntrospectionRouter(
      tokenValidator: _validator,
      rbacService: _rbacService,
    );

    // Shelf pipeline
    final publicPaths = ['health', 'login', 'refresh', 'validate', 'api/introspect'];

    final handler = const Pipeline()
        .addMiddleware(logRequests())
        .addMiddleware(_corsMiddleware())
        .addMiddleware(authMiddleware(
          _validator,
          _sessions,
          requireAuth: false, // router handlers check individually
          publicPaths: publicPaths,
        ))
        .addHandler(_buildHandler(authRouter, rbacRouter, introspectionRouter));

    _server = await shelf_io.serve(handler, address, port);
    _server!.autoCompress = true;

    // ignore: avoid_print
    print('[AQAuthServer] Listening on $address:$port');
  }

  Future<void> stop() async {
    _sessions.dispose();
    await _server?.close(force: true);
    // ignore: avoid_print
    print('[AQAuthServer] Stopped');
  }

  /// The validator — used by other services to verify tokens without HTTP call.
  TokenValidator get validator => _validator;

  // ── Handler assembly ───────────────────────────────────────────────────────

  Handler _buildHandler(
    AuthRouter authRouter,
    RBACRouter rbacRouter,
    IntrospectionRouter introspectionRouter,
  ) {
    final root = Router();
    root.mount('/auth/', authRouter.router);
    root.mount('/rbac/', rbacRouter.router);
    root.mount('/api/', introspectionRouter.router);

    // 404 fallback
    root.all(
        '/<ignored|.*>',
        (Request req) => Response.notFound(
              '{"code":"not_found","message":"Route not found"}',
              headers: {'Content-Type': 'application/json'},
            ));

    return root;
  }

  Middleware _corsMiddleware() {
    return (Handler innerHandler) {
      return (Request request) async {
        final origin = request.headers['origin'] ?? '';

        // Handle preflight OPTIONS request
        if (request.method == 'OPTIONS') {
          return Response.ok('', headers: _buildCorsHeaders(origin));
        }

        // Process request and add CORS headers to response
        final response = await innerHandler(request);
        return response.change(headers: _buildCorsHeaders(origin));
      };
    };
  }

  Map<String, String> _buildCorsHeaders(String origin) {
    final allowed = config.allowedOrigins;
    final isAllowed = allowed.contains('*') || allowed.contains(origin);

    return {
      'Access-Control-Allow-Origin': isAllowed ? origin : '',
      'Access-Control-Allow-Methods': 'GET, POST, DELETE, OPTIONS',
      'Access-Control-Allow-Headers': 'Authorization, Content-Type',
      'Access-Control-Allow-Credentials': 'true',
      'Vary': 'Origin',
    };
  }
}
