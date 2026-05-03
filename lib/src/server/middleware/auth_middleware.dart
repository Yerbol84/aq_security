// pkgs/aq_security/lib/src/server/middleware/auth_middleware.dart
//
// Shelf middleware for Bearer token validation.
// Used by: aq_auth_service, aq_data_service, aq_worker_service.
//
// Any Shelf server that needs auth protection wraps its handler:
//
//   final handler = const Pipeline()
//     .addMiddleware(authMiddleware(validator, sessions))
//     .addHandler(router);
//
// After the middleware passes, the handler can read:
//   final claims = AuthMiddleware.claimsOf(request); // AqTokenClaims?

import 'dart:convert';
import 'package:shelf/shelf.dart';
import 'package:aq_schema/security/security.dart';

import '../../server/session_service.dart';

const _claimsKey = 'aq.security.claims';

/// Middleware factory. [requireAuth] = false allows unauthenticated requests
/// to pass through (claims will be null for those).
Middleware authMiddleware(
  TokenValidator validator,
  SessionService sessions, {
  bool requireAuth = true,
  List<String> publicPaths = const [],
}) {
  return (Handler inner) {
    return (Request request) async {
      // Skip auth for public paths
      final path = request.url.path;
      final isPublic = publicPaths.any((p) => path.startsWith(p));
      if (isPublic) return inner(request);

      final token = _extractToken(request);

      if (token == null) {
        if (!requireAuth) return inner(request);
        return _unauthorized('Missing Authorization header');
      }

      // 1. Validate signature + expiry locally (fast, no DB)
      final result = validator.validateAccess(token);
      if (!result.valid) {
        return _unauthorized(result.message ?? 'Invalid token');
      }

      final claims = result.claims!;

      // 2. Validate session exists and is not revoked (DB check)
      final session = await sessions.validate(claims.sid);
      if (session == null) {
        return _unauthorized('Session expired or revoked');
      }

      // 3. Touch session (fire-and-forget — don't block the request)
      sessions.touch(claims.sid).ignore();

      // 4. Attach claims to request context
      final updated = request.change(context: {
        ...request.context,
        _claimsKey: claims,
      });

      return inner(updated);
    };
  };
}

/// Light middleware for services that only need to verify tokens
/// (no session DB access). Used by data service and workers
/// for intra-service calls.
Middleware tokenOnlyMiddleware(
  TokenValidator validator, {
  bool requireAuth = true,
  List<String> publicPaths = const [],
}) {
  return (Handler inner) {
    return (Request request) async {
      final path = request.url.path;
      final isPublic = publicPaths.any((p) => path.startsWith(p));
      if (isPublic) return inner(request);

      final token = _extractToken(request);

      if (token == null) {
        if (!requireAuth) return inner(request);
        return _unauthorized('Missing Authorization header');
      }

      final result = validator.validate(token);
      if (!result.valid) {
        return _unauthorized(result.message ?? 'Invalid token');
      }

      final updated = request.change(context: {
        ...request.context,
        _claimsKey: result.claims!,
      });

      return inner(updated);
    };
  };
}

/// Extension helpers for reading auth state from a request.
extension AuthMiddlewareRequest on Request {
  AqTokenClaims? get claims =>
      context[_claimsKey] as AqTokenClaims?;

  AqTokenClaims get requireClaims {
    final c = claims;
    if (c == null) throw StateError('No auth claims on request');
    return c;
  }

  bool hasPermission(String perm) => claims?.hasPermission(perm) ?? false;

  bool hasAllPermissions(List<String> perms) =>
      claims?.hasAllPermissions(perms) ?? false;
}

// ── Helpers ───────────────────────────────────────────────────────────────────

String? _extractToken(Request request) {
  final header = request.headers['authorization'] ??
      request.headers['Authorization'];
  if (header == null) return null;
  if (!header.startsWith('Bearer ')) return null;
  return header.substring(7).trim();
}

Response _unauthorized(String message) => Response(
      401,
      body: jsonEncode({'code': 'unauthorized', 'message': message}),
      headers: {'Content-Type': 'application/json'},
    );

Response _forbidden(String message) => Response(
      403,
      body: jsonEncode({'code': 'forbidden', 'message': message}),
      headers: {'Content-Type': 'application/json'},
    );

/// Helper: require specific permission, return 403 if missing.
Future<Response?> requirePermission(
  Request request,
  String perm,
) async {
  if (!request.hasPermission(perm)) {
    return _forbidden('Permission required: $perm');
  }
  return null;
}
