// pkgs/aq_security/lib/src/server/middleware/scope_middleware.dart
//
// Middleware для проверки scopes в JWT tokens.
// Используется для защиты endpoints требующих определённых permissions.

import 'dart:convert';
import 'package:shelf/shelf.dart';
import 'package:aq_schema/security/security.dart';

/// Middleware для проверки наличия требуемых scopes в JWT token.
///
/// Использование:
/// ```dart
/// final handler = Pipeline()
///   .addMiddleware(jwtMiddleware(secret: secret))
///   .addMiddleware(requireScopes(['projects:read']))
///   .addHandler(myHandler);
/// ```
Middleware requireScopes(
  List<String> requiredScopes, {
  bool requireAll = true,
}) {
  return (Handler innerHandler) {
    return (Request request) async {
      // Получить claims из request context (установлены jwtMiddleware)
      final claims = request.context['claims'] as AqTokenClaims?;

      if (claims == null) {
        return Response.forbidden(
          jsonEncode({
            'error': 'unauthorized',
            'message': 'No authentication token provided',
          }),
          headers: {'Content-Type': 'application/json'},
        );
      }

      // Проверить scopes
      final hasAccess = requireAll
          ? claims.hasAllScopes(requiredScopes)
          : claims.hasAnyScope(requiredScopes);

      if (!hasAccess) {
        return Response.forbidden(
          jsonEncode({
            'error': 'insufficient_scope',
            'message': 'Insufficient permissions to access this resource',
            'required_scopes': requiredScopes,
            'user_scopes': claims.scopes,
          }),
          headers: {'Content-Type': 'application/json'},
        );
      }

      // Scopes валидны, продолжить
      return innerHandler(request);
    };
  };
}

/// Middleware для проверки хотя бы одного из требуемых scopes.
Middleware requireAnyScope(List<String> requiredScopes) {
  return requireScopes(requiredScopes, requireAll: false);
}

/// Middleware для проверки всех требуемых scopes.
Middleware requireAllScopes(List<String> requiredScopes) {
  return requireScopes(requiredScopes, requireAll: true);
}

/// Middleware для проверки admin доступа к ресурсу.
Middleware requireAdmin(String resource) {
  return requireScopes(['$resource:admin']);
}

/// Middleware для проверки доступа к конкретному ресурсу.
///
/// Извлекает resourceId из path параметров и проверяет scope.
///
/// Использование:
/// ```dart
/// router.get('/projects/<id>', Pipeline()
///   .addMiddleware(requireResourceAccess('projects', 'read'))
///   .addHandler(getProject));
/// ```
Middleware requireResourceAccess(String resource, String action) {
  return (Handler innerHandler) {
    return (Request request) async {
      final claims = request.context['claims'] as AqTokenClaims?;

      if (claims == null) {
        return Response.forbidden(
          jsonEncode({
            'error': 'unauthorized',
            'message': 'No authentication token provided',
          }),
          headers: {'Content-Type': 'application/json'},
        );
      }

      // Извлечь resourceId из path params
      final params = request.context['params'] as Map<String, String>?;
      final resourceId = params?['id'];

      // Проверить общий scope или scope для конкретного ресурса
      final generalScope = '$resource:$action';
      final specificScope =
          resourceId != null ? '$resource:$action:$resourceId' : null;

      final hasAccess = claims.hasScope(generalScope) ||
          (specificScope != null && claims.hasScope(specificScope));

      if (!hasAccess) {
        return Response.forbidden(
          jsonEncode({
            'error': 'insufficient_scope',
            'message': 'Insufficient permissions to access this resource',
            'required_scope': specificScope ?? generalScope,
            'user_scopes': claims.scopes,
          }),
          headers: {'Content-Type': 'application/json'},
        );
      }

      return innerHandler(request);
    };
  };
}

/// Helper для создания response с ошибкой scope.
Response scopeError({
  required String message,
  required List<String> requiredScopes,
  List<String>? userScopes,
}) {
  return Response.forbidden(
    jsonEncode({
      'error': 'insufficient_scope',
      'message': message,
      'required_scopes': requiredScopes,
      if (userScopes != null) 'user_scopes': userScopes,
    }),
    headers: {'Content-Type': 'application/json'},
  );
}
