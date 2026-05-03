// test/unit/security_headers_test.dart
//
// Тесты для security headers и CORS

import 'package:test/test.dart';
import 'package:shelf/shelf.dart';
import 'package:aq_security/aq_security_server.dart';

void main() {
  group('SecurityHeadersConfig', () {
    test('production config имеет строгие настройки', () {
      const config = SecurityHeadersConfig.production;

      expect(config.xFrameOptions, equals('DENY'));
      expect(config.enableHsts, isTrue);
      expect(config.enableCsp, isTrue);
      expect(config.contentSecurityPolicy, isNotNull);
    });

    test('development config имеет мягкие настройки', () {
      const config = SecurityHeadersConfig.development;

      expect(config.xFrameOptions, equals('SAMEORIGIN'));
      expect(config.enableHsts, isFalse);
    });

    test('toHeaders возвращает правильные headers', () {
      const config = SecurityHeadersConfig(
        xFrameOptions: 'DENY',
        xContentTypeOptions: 'nosniff',
        enableHsts: true,
        strictTransportSecurity: 'max-age=31536000',
      );

      final headers = config.toHeaders();

      expect(headers['X-Frame-Options'], equals('DENY'));
      expect(headers['X-Content-Type-Options'], equals('nosniff'));
      expect(headers['Strict-Transport-Security'], equals('max-age=31536000'));
    });

    test('toHeaders не включает HSTS если disabled', () {
      const config = SecurityHeadersConfig(
        enableHsts: false,
      );

      final headers = config.toHeaders();

      expect(headers.containsKey('Strict-Transport-Security'), isFalse);
    });

    test('toHeaders не включает CSP если disabled', () {
      const config = SecurityHeadersConfig(
        enableCsp: false,
        contentSecurityPolicy: "default-src 'self'",
      );

      final headers = config.toHeaders();

      expect(headers.containsKey('Content-Security-Policy'), isFalse);
    });
  });

  group('CspBuilder', () {
    test('строит простой CSP', () {
      final csp = CspBuilder()
          .defaultSrc(["'self'"])
          .scriptSrc(["'self'", "'unsafe-inline'"])
          .build();

      expect(csp, contains("default-src 'self'"));
      expect(csp, contains("script-src 'self' 'unsafe-inline'"));
    });

    test('строит CSP с directives без values', () {
      final csp = CspBuilder()
          .defaultSrc(["'self'"])
          .upgradeInsecureRequests()
          .build();

      expect(csp, contains("default-src 'self'"));
      expect(csp, contains('upgrade-insecure-requests'));
    });

    test('strict() возвращает строгий CSP', () {
      final csp = CspBuilder.strict();

      expect(csp, contains("default-src 'self'"));
      expect(csp, contains("frame-ancestors 'none'"));
      expect(csp, contains('upgrade-insecure-requests'));
    });

    test('relaxed() возвращает мягкий CSP', () {
      final csp = CspBuilder.relaxed();

      expect(csp, contains("'unsafe-inline'"));
      expect(csp, contains("'unsafe-eval'"));
    });
  });

  group('CorsConfig', () {
    test('isOriginAllowed проверяет wildcard', () {
      const config = CorsConfig(
        allowedOrigins: ['*'],
      );

      expect(config.isOriginAllowed('https://example.com'), isTrue);
      expect(config.isOriginAllowed('https://any-origin.com'), isTrue);
    });

    test('isOriginAllowed проверяет конкретные origins', () {
      const config = CorsConfig(
        allowedOrigins: ['https://example.com', 'https://app.example.com'],
      );

      expect(config.isOriginAllowed('https://example.com'), isTrue);
      expect(config.isOriginAllowed('https://app.example.com'), isTrue);
      expect(config.isOriginAllowed('https://evil.com'), isFalse);
    });

    test('getHeaders возвращает правильные CORS headers', () {
      const config = CorsConfig(
        allowedOrigins: ['https://example.com'],
        allowedMethods: ['GET', 'POST'],
        allowCredentials: true,
      );

      final headers = config.getHeaders('https://example.com');

      expect(headers['Access-Control-Allow-Origin'], equals('https://example.com'));
      expect(headers['Access-Control-Allow-Methods'], equals('GET, POST'));
      expect(headers['Access-Control-Allow-Credentials'], equals('true'));
    });

    test('getHeaders использует wildcard если нет credentials', () {
      const config = CorsConfig(
        allowedOrigins: ['*'],
        allowCredentials: false,
      );

      final headers = config.getHeaders('https://example.com');

      expect(headers['Access-Control-Allow-Origin'], equals('*'));
    });

    test('getHeaders использует origin если есть credentials', () {
      const config = CorsConfig(
        allowedOrigins: ['*'],
        allowCredentials: true,
      );

      final headers = config.getHeaders('https://example.com');

      expect(headers['Access-Control-Allow-Origin'], equals('https://example.com'));
    });
  });

  group('securityHeadersMiddleware', () {
    test('добавляет security headers к response', () async {
      const config = SecurityHeadersConfig(
        xFrameOptions: 'DENY',
        xContentTypeOptions: 'nosniff',
      );

      final handler = const Pipeline()
          .addMiddleware(securityHeadersMiddleware(config: config))
          .addHandler((req) => Response.ok('OK'));

      final request = Request('GET', Uri.parse('http://localhost/'));
      final response = await handler(request);

      expect(response.headers['X-Frame-Options'], equals('DENY'));
      expect(response.headers['X-Content-Type-Options'], equals('nosniff'));
    });
  });

  group('corsMiddleware', () {
    test('обрабатывает preflight request', () async {
      const config = CorsConfig(
        allowedOrigins: ['https://example.com'],
        allowedMethods: ['GET', 'POST'],
      );

      final handler = const Pipeline()
          .addMiddleware(corsMiddleware(config: config))
          .addHandler((req) => Response.ok('OK'));

      final request = Request(
        'OPTIONS',
        Uri.parse('http://localhost/api/users'),
        headers: {
          'origin': 'https://example.com',
          'access-control-request-method': 'POST',
        },
      );

      final response = await handler(request);

      expect(response.statusCode, equals(200));
      expect(response.headers['Access-Control-Allow-Origin'], equals('https://example.com'));
      expect(response.headers['Access-Control-Allow-Methods'], contains('POST'));
    });

    test('блокирует preflight от неразрешённого origin', () async {
      const config = CorsConfig(
        allowedOrigins: ['https://example.com'],
      );

      final handler = const Pipeline()
          .addMiddleware(corsMiddleware(config: config))
          .addHandler((req) => Response.ok('OK'));

      final request = Request(
        'OPTIONS',
        Uri.parse('http://localhost/api/users'),
        headers: {
          'origin': 'https://evil.com',
        },
      );

      final response = await handler(request);

      expect(response.statusCode, equals(403));
    });

    test('добавляет CORS headers к обычному response', () async {
      const config = CorsConfig(
        allowedOrigins: ['https://example.com'],
      );

      final handler = const Pipeline()
          .addMiddleware(corsMiddleware(config: config))
          .addHandler((req) => Response.ok('OK'));

      final request = Request(
        'GET',
        Uri.parse('http://localhost/api/users'),
        headers: {
          'origin': 'https://example.com',
        },
      );

      final response = await handler(request);

      expect(response.statusCode, equals(200));
      expect(response.headers['Access-Control-Allow-Origin'], equals('https://example.com'));
    });
  });

  group('securityMiddleware', () {
    test('добавляет и security headers и CORS headers', () async {
      const headersConfig = SecurityHeadersConfig(
        xFrameOptions: 'DENY',
      );

      const corsConfig = CorsConfig(
        allowedOrigins: ['https://example.com'],
      );

      final handler = const Pipeline()
          .addMiddleware(securityMiddleware(
            headersConfig: headersConfig,
            corsConfig: corsConfig,
          ))
          .addHandler((req) => Response.ok('OK'));

      final request = Request(
        'GET',
        Uri.parse('http://localhost/api/users'),
        headers: {
          'origin': 'https://example.com',
        },
      );

      final response = await handler(request);

      expect(response.headers['X-Frame-Options'], equals('DENY'));
      expect(response.headers['Access-Control-Allow-Origin'], equals('https://example.com'));
    });
  });
}
