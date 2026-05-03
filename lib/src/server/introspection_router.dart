// pkgs/aq_security/lib/src/server/introspection_router.dart
//
// OAuth 2.0 Token Introspection endpoint (RFC 7662).
// Используется Resource Servers (Data Service) для проверки прав доступа.
//
// POST /api/introspect - проверить может ли токен выполнить действие

import 'dart:convert';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:aq_schema/aq_schema.dart';
import 'package:aq_schema/security/security.dart';

import '../rbac/rbac_service.dart';

/// Router для Token Introspection (RFC 7662).
class IntrospectionRouter {
  IntrospectionRouter({
    required this.tokenValidator,
    required this.rbacService,
  });

  final TokenValidator tokenValidator;
  final RBACService rbacService;

  Router get router {
    final r = Router();
    r.post('/introspect', _introspect);
    return r;
  }

  /// POST /api/introspect
  ///
  /// Request:
  /// {
  ///   "token": "eyJhbGc...",
  ///   "resource": "project",
  ///   "action": "read",
  ///   "resourceId": "proj789",
  ///   "context": {
  ///     "ip": "192.168.1.1",
  ///     "userAgent": "Mozilla/5.0..."
  ///   }
  /// }
  ///
  /// Response (allowed):
  /// {
  ///   "active": true,
  ///   "allowed": true,
  ///   "userId": "user123",
  ///   "tenantId": "tenant456",
  ///   "scopes": ["project:proj789:read", "project:proj789:write"],
  ///   "roles": ["project.editor"],
  ///   "expiresAt": 1234567890
  /// }
  ///
  /// Response (denied):
  /// {
  ///   "active": true,
  ///   "allowed": false,
  ///   "userId": "user123",
  ///   "tenantId": "tenant456",
  ///   "reason": "Permission denied: project:proj789:read"
  /// }
  Future<Response> _introspect(Request req) async {
    try {
      final body = await req.readAsString();
      final data = jsonDecode(body) as Map<String, dynamic>;

      final token = data['token'] as String;
      final resource = data['resource'] as String;
      final action = data['action'] as String;
      final resourceId = data['resourceId'] as String;
      final contextData = data['context'] as Map<String, dynamic>?;

      // 1. Валидировать токен (подпись + expiry)
      final validation = tokenValidator.validate(token);
      if (!validation.valid) {
        return _ok({
          'active': false,
          'allowed': false,
          'reason': validation.message ?? 'Invalid token',
        });
      }

      final claims = validation.claims!;

      // 2. Быстрая проверка: tenant admin?
      if (claims.roles.contains('tenant:admin')) {
        // Админ тенанта - полный доступ
        final scopes = await rbacService.getUserEffectivePermissions(claims.sub);
        return _ok({
          'active': true,
          'allowed': true,
          'userId': claims.sub,
          'tenantId': claims.tid,
          'scopes': scopes,
          'roles': claims.roles,
          'expiresAt': claims.exp,
        });
      }

      // 3. Проверить права через RBAC
      final context = contextData != null
          ? AccessContext(
              userId: claims.sub,
              tenantId: claims.tid,
              resource: resource,
              action: action,
              ipAddress: contextData['ip'] as String?,
              userAgent: contextData['userAgent'] as String?,
              timestamp: DateTime.now().millisecondsSinceEpoch,
            )
          : null;

      final decision = await rbacService.can(
        claims.sub,
        resource,
        action,
        resourceId,
        context: context,
      );

      // 4. Получить эффективные права (scopes)
      final scopes = decision.allowed
          ? await rbacService.getUserEffectivePermissions(claims.sub)
          : <String>[];

      // 5. Вернуть результат
      return _ok({
        'active': true,
        'allowed': decision.allowed,
        'userId': claims.sub,
        'tenantId': claims.tid,
        'scopes': scopes,
        'roles': claims.roles,
        'expiresAt': claims.exp,
        if (!decision.allowed) 'reason': decision.reason,
      });
    } catch (e) {
      return _error('Introspection failed: $e');
    }
  }

  Response _ok(Map<String, dynamic> data) => Response.ok(
        jsonEncode(data),
        headers: {'Content-Type': 'application/json'},
      );

  Response _error(String message) => Response(500,
        body: jsonEncode({'error': message}),
        headers: {'Content-Type': 'application/json'});
}
