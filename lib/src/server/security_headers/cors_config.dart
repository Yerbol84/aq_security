// pkgs/aq_security/lib/src/server/security_headers/cors_config.dart
//
// Server-only. CORS configuration для cross-origin requests.

/// CORS configuration
final class CorsConfig {
  const CorsConfig({
    this.allowedOrigins = const ['*'],
    this.allowedMethods = const ['GET', 'POST', 'PUT', 'DELETE', 'PATCH', 'OPTIONS'],
    this.allowedHeaders = const ['*'],
    this.exposedHeaders = const [],
    this.allowCredentials = false,
    this.maxAge = 86400, // 24 hours
  });

  /// Разрешённые origins
  /// ['*'] - все origins
  /// ['https://example.com'] - конкретные origins
  final List<String> allowedOrigins;

  /// Разрешённые HTTP методы
  final List<String> allowedMethods;

  /// Разрешённые headers
  /// ['*'] - все headers
  /// ['Content-Type', 'Authorization'] - конкретные headers
  final List<String> allowedHeaders;

  /// Headers которые можно expose клиенту
  final List<String> exposedHeaders;

  /// Разрешить credentials (cookies, authorization headers)
  final bool allowCredentials;

  /// Max age для preflight cache (в секундах)
  final int maxAge;

  /// Production config (строгий)
  static const production = CorsConfig(
    allowedOrigins: [], // Должны быть указаны явно
    allowedMethods: ['GET', 'POST', 'PUT', 'DELETE', 'PATCH'],
    allowedHeaders: ['Content-Type', 'Authorization'],
    exposedHeaders: ['X-RateLimit-Limit', 'X-RateLimit-Remaining', 'X-RateLimit-Reset'],
    allowCredentials: true,
    maxAge: 86400,
  );

  /// Development config (мягкий)
  static const development = CorsConfig(
    allowedOrigins: ['*'],
    allowedMethods: ['GET', 'POST', 'PUT', 'DELETE', 'PATCH', 'OPTIONS'],
    allowedHeaders: ['*'],
    exposedHeaders: ['*'],
    allowCredentials: false,
    maxAge: 3600,
  );

  /// Проверить, разрешён ли origin
  bool isOriginAllowed(String? origin) {
    if (origin == null) return false;

    // Если разрешены все origins
    if (allowedOrigins.contains('*')) return true;

    // Проверить конкретные origins
    return allowedOrigins.contains(origin);
  }

  /// Получить CORS headers для response
  Map<String, String> getHeaders(String? origin) {
    final headers = <String, String>{};

    // Access-Control-Allow-Origin
    if (isOriginAllowed(origin)) {
      if (allowCredentials) {
        // Если credentials, нельзя использовать '*'
        headers['Access-Control-Allow-Origin'] = origin!;
      } else {
        headers['Access-Control-Allow-Origin'] = allowedOrigins.contains('*') ? '*' : origin!;
      }
    }

    // Access-Control-Allow-Methods
    headers['Access-Control-Allow-Methods'] = allowedMethods.join(', ');

    // Access-Control-Allow-Headers
    if (allowedHeaders.contains('*')) {
      headers['Access-Control-Allow-Headers'] = '*';
    } else {
      headers['Access-Control-Allow-Headers'] = allowedHeaders.join(', ');
    }

    // Access-Control-Expose-Headers
    if (exposedHeaders.isNotEmpty) {
      if (exposedHeaders.contains('*')) {
        headers['Access-Control-Expose-Headers'] = '*';
      } else {
        headers['Access-Control-Expose-Headers'] = exposedHeaders.join(', ');
      }
    }

    // Access-Control-Allow-Credentials
    if (allowCredentials) {
      headers['Access-Control-Allow-Credentials'] = 'true';
    }

    // Access-Control-Max-Age
    headers['Access-Control-Max-Age'] = maxAge.toString();

    return headers;
  }

  /// Получить headers для preflight request
  Map<String, String> getPreflightHeaders(String? origin, String? requestMethod, String? requestHeaders) {
    final headers = getHeaders(origin);

    // Добавить Vary header
    headers['Vary'] = 'Origin, Access-Control-Request-Method, Access-Control-Request-Headers';

    return headers;
  }
}
