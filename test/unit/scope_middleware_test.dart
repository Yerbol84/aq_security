// test/unit/scope_middleware_test.dart
//
// Тесты для scope middleware

import 'dart:convert';
import 'package:test/test.dart';
import 'package:shelf/shelf.dart';
import 'package:aq_security/aq_security_server.dart';
import 'package:aq_schema/security/security.dart';

void main() {
  group('Scope Middleware', () {
    late AqTokenClaims claims;
    late Request requestWithClaims;
    late Request requestWithoutClaims;

    setUp(() {
      claims = AqTokenClaims(
        sub: 'user123',
        tid: 'tenant456',
        email: 'test@example.com',
        type: TokenType.access,
        iat: 1000000,
        exp: 1001000,
        jti: 'token123',
        sid: 'session456',
        scopes: [
          'projects:read',
          'projects:write',
          'graphs:admin',
        ],
      );

      requestWithClaims = Request(
        'GET',
        Uri.parse('http://localhost/test'),
        context: {'claims': claims},
      );

      requestWithoutClaims = Request(
        'GET',
        Uri.parse('http://localhost/test'),
      );
    });

    group('requireScopes', () {
      test('пропускает запрос с валидными scopes (requireAll=true)', () async {
        final handler = const Pipeline()
            .addMiddleware(requireScopes(['projects:read']))
            .addHandler((req) => Response.ok('success'));

        final response = await handler(requestWithClaims);

        expect(response.statusCode, equals(200));
        expect(await response.readAsString(), equals('success'));
      });

      test('блокирует запрос без требуемых scopes (requireAll=true)', () async {
        final handler = const Pipeline()
            .addMiddleware(requireScopes(['users:admin']))
            .addHandler((req) => Response.ok('success'));

        final response = await handler(requestWithClaims);

        expect(response.statusCode, equals(403));
        final body = jsonDecode(await response.readAsString());
        expect(body['error'], equals('insufficient_scope'));
      });

      test('пропускает запрос с хотя бы одним scope (requireAll=false)', () async {
        final handler = const Pipeline()
            .addMiddleware(requireScopes(['projects:read', 'users:admin'], requireAll: false))
            .addHandler((req) => Response.ok('success'));

        final response = await handler(requestWithClaims);

        expect(response.statusCode, equals(200));
      });

      test('блокирует запрос без claims', () async {
        final handler = const Pipeline()
            .addMiddleware(requireScopes(['projects:read']))
            .addHandler((req) => Response.ok('success'));

        final response = await handler(requestWithoutClaims);

        expect(response.statusCode, equals(403));
        final body = jsonDecode(await response.readAsString());
        expect(body['error'], equals('unauthorized'));
      });

      test('работает с admin scope', () async {
        final handler = const Pipeline()
            .addMiddleware(requireScopes(['graphs:read', 'graphs:write']))
            .addHandler((req) => Response.ok('success'));

        final response = await handler(requestWithClaims);

        expect(response.statusCode, equals(200));
      });
    });

    group('requireAnyScope', () {
      test('пропускает запрос с хотя бы одним scope', () async {
        final handler = const Pipeline()
            .addMiddleware(requireAnyScope(['projects:read', 'users:admin']))
            .addHandler((req) => Response.ok('success'));

        final response = await handler(requestWithClaims);

        expect(response.statusCode, equals(200));
      });

      test('блокирует запрос без ни одного scope', () async {
        final handler = const Pipeline()
            .addMiddleware(requireAnyScope(['users:read', 'users:write']))
            .addHandler((req) => Response.ok('success'));

        final response = await handler(requestWithClaims);

        expect(response.statusCode, equals(403));
      });
    });

    group('requireAllScopes', () {
      test('пропускает запрос со всеми scopes', () async {
        final handler = const Pipeline()
            .addMiddleware(requireAllScopes(['projects:read', 'projects:write']))
            .addHandler((req) => Response.ok('success'));

        final response = await handler(requestWithClaims);

        expect(response.statusCode, equals(200));
      });

      test('блокирует запрос без всех scopes', () async {
        final handler = const Pipeline()
            .addMiddleware(requireAllScopes(['projects:read', 'users:admin']))
            .addHandler((req) => Response.ok('success'));

        final response = await handler(requestWithClaims);

        expect(response.statusCode, equals(403));
      });
    });

    group('requireAdmin', () {
      test('пропускает запрос с admin scope', () async {
        final handler = const Pipeline()
            .addMiddleware(requireAdmin('graphs'))
            .addHandler((req) => Response.ok('success'));

        final response = await handler(requestWithClaims);

        expect(response.statusCode, equals(200));
      });

      test('блокирует запрос без admin scope', () async {
        final handler = const Pipeline()
            .addMiddleware(requireAdmin('projects'))
            .addHandler((req) => Response.ok('success'));

        final response = await handler(requestWithClaims);

        expect(response.statusCode, equals(403));
      });
    });

    group('requireResourceAccess', () {
      test('пропускает запрос с общим scope', () async {
        final requestWithParams = Request(
          'GET',
          Uri.parse('http://localhost/projects/abc123'),
          context: {
            'claims': claims,
            'params': {'id': 'abc123'},
          },
        );

        final handler = const Pipeline()
            .addMiddleware(requireResourceAccess('projects', 'read'))
            .addHandler((req) => Response.ok('success'));

        final response = await handler(requestWithParams);

        expect(response.statusCode, equals(200));
      });

      test('пропускает запрос с конкретным resource scope', () async {
        final specificClaims = AqTokenClaims(
          sub: 'user123',
          tid: 'tenant456',
          email: 'test@example.com',
          type: TokenType.access,
          iat: 1000000,
          exp: 1001000,
          jti: 'token123',
          sid: 'session456',
          scopes: ['projects:read:abc123'],
        );

        final requestWithParams = Request(
          'GET',
          Uri.parse('http://localhost/projects/abc123'),
          context: {
            'claims': specificClaims,
            'params': {'id': 'abc123'},
          },
        );

        final handler = const Pipeline()
            .addMiddleware(requireResourceAccess('projects', 'read'))
            .addHandler((req) => Response.ok('success'));

        final response = await handler(requestWithParams);

        expect(response.statusCode, equals(200));
      });

      test('блокирует запрос к другому ресурсу', () async {
        final specificClaims = AqTokenClaims(
          sub: 'user123',
          tid: 'tenant456',
          email: 'test@example.com',
          type: TokenType.access,
          iat: 1000000,
          exp: 1001000,
          jti: 'token123',
          sid: 'session456',
          scopes: ['projects:read:abc123'],
        );

        final requestWithParams = Request(
          'GET',
          Uri.parse('http://localhost/projects/xyz789'),
          context: {
            'claims': specificClaims,
            'params': {'id': 'xyz789'},
          },
        );

        final handler = const Pipeline()
            .addMiddleware(requireResourceAccess('projects', 'read'))
            .addHandler((req) => Response.ok('success'));

        final response = await handler(requestWithParams);

        expect(response.statusCode, equals(403));
      });

      test('работает без params (общий scope)', () async {
        final requestWithoutParams = Request(
          'GET',
          Uri.parse('http://localhost/projects'),
          context: {'claims': claims},
        );

        final handler = const Pipeline()
            .addMiddleware(requireResourceAccess('projects', 'read'))
            .addHandler((req) => Response.ok('success'));

        final response = await handler(requestWithoutParams);

        expect(response.statusCode, equals(200));
      });
    });

    group('error responses', () {
      test('возвращает правильную структуру ошибки для insufficient_scope', () async {
        final handler = const Pipeline()
            .addMiddleware(requireScopes(['users:admin']))
            .addHandler((req) => Response.ok('success'));

        final response = await handler(requestWithClaims);

        expect(response.statusCode, equals(403));
        final body = jsonDecode(await response.readAsString());
        expect(body['error'], equals('insufficient_scope'));
        expect(body['message'], isNotNull);
        expect(body['required_scopes'], equals(['users:admin']));
        expect(body['user_scopes'], equals(claims.scopes));
      });

      test('возвращает правильную структуру ошибки для unauthorized', () async {
        final handler = const Pipeline()
            .addMiddleware(requireScopes(['projects:read']))
            .addHandler((req) => Response.ok('success'));

        final response = await handler(requestWithoutClaims);

        expect(response.statusCode, equals(403));
        final body = jsonDecode(await response.readAsString());
        expect(body['error'], equals('unauthorized'));
        expect(body['message'], contains('No authentication token'));
      });
    });

    group('complex scenarios', () {
      test('множественные middleware в цепочке', () async {
        final handler = const Pipeline()
            .addMiddleware(requireScopes(['projects:read']))
            .addMiddleware(requireScopes(['projects:write']))
            .addHandler((req) => Response.ok('success'));

        final response = await handler(requestWithClaims);

        expect(response.statusCode, equals(200));
      });

      test('middleware с разными требованиями', () async {
        final handler = const Pipeline()
            .addMiddleware(requireAnyScope(['projects:read', 'graphs:read']))
            .addMiddleware(requireAllScopes(['projects:write']))
            .addHandler((req) => Response.ok('success'));

        final response = await handler(requestWithClaims);

        expect(response.statusCode, equals(200));
      });

      test('блокирует на первом невалидном middleware', () async {
        final handler = const Pipeline()
            .addMiddleware(requireScopes(['users:admin']))
            .addMiddleware(requireScopes(['projects:read']))
            .addHandler((req) => Response.ok('success'));

        final response = await handler(requestWithClaims);

        expect(response.statusCode, equals(403));
        final body = jsonDecode(await response.readAsString());
        expect(body['required_scopes'], equals(['users:admin']));
      });
    });
  });
}
