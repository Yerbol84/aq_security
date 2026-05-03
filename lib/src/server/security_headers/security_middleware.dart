// pkgs/aq_security/lib/src/server/security_headers/security_middleware.dart
//
// Server-only. Middleware для security headers и CORS.

import 'package:shelf/shelf.dart';
import 'security_headers.dart';
import 'cors_config.dart';

/// Security headers middleware
Middleware securityHeadersMiddleware({
  required SecurityHeadersConfig config,
}) {
  return (Handler handler) {
    return (Request request) async {
      final response = await handler(request);

      // Добавить security headers
      return response.change(headers: config.toHeaders());
    };
  };
}

/// CORS middleware
Middleware corsMiddleware({
  required CorsConfig config,
}) {
  return (Handler handler) {
    return (Request request) async {
      final origin = request.headers['origin'];

      // Обработать preflight request (OPTIONS)
      if (request.method == 'OPTIONS') {
        final requestMethod = request.headers['access-control-request-method'];
        final requestHeaders = request.headers['access-control-request-headers'];

        // Проверить, разрешён ли origin
        if (!config.isOriginAllowed(origin)) {
          return Response.forbidden('Origin not allowed');
        }

        // Вернуть preflight response
        return Response.ok(
          '',
          headers: config.getPreflightHeaders(origin, requestMethod, requestHeaders),
        );
      }

      // Обработать обычный request
      final response = await handler(request);

      // Добавить CORS headers
      if (config.isOriginAllowed(origin)) {
        return response.change(headers: config.getHeaders(origin));
      }

      return response;
    };
  };
}

/// Combined security middleware (headers + CORS)
Middleware securityMiddleware({
  required SecurityHeadersConfig headersConfig,
  required CorsConfig corsConfig,
}) {
  return (Handler handler) {
    return (Request request) async {
      final origin = request.headers['origin'];

      // Обработать preflight
      if (request.method == 'OPTIONS') {
        if (!corsConfig.isOriginAllowed(origin)) {
          return Response.forbidden('Origin not allowed');
        }

        final requestMethod = request.headers['access-control-request-method'];
        final requestHeaders = request.headers['access-control-request-headers'];

        return Response.ok(
          '',
          headers: {
            ...headersConfig.toHeaders(),
            ...corsConfig.getPreflightHeaders(origin, requestMethod, requestHeaders),
          },
        );
      }

      // Обработать обычный request
      final response = await handler(request);

      // Добавить все headers
      final headers = <String, String>{
        ...headersConfig.toHeaders(),
      };

      if (corsConfig.isOriginAllowed(origin)) {
        headers.addAll(corsConfig.getHeaders(origin));
      }

      return response.change(headers: headers);
    };
  };
}
