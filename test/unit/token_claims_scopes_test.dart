// test/unit/token_claims_scopes_test.dart
//
// Тесты для AqTokenClaims с scope support

import 'package:test/test.dart';
import 'package:aq_schema/security/security.dart';

void main() {
  group('AqTokenClaims with Scopes', () {
    late AqTokenClaims claims;

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
    });

    group('hasScope', () {
      test('возвращает true для существующего scope', () {
        expect(claims.hasScope('projects:read'), isTrue);
        expect(claims.hasScope('projects:write'), isTrue);
      });

      test('возвращает false для отсутствующего scope', () {
        expect(claims.hasScope('projects:delete'), isFalse);
        expect(claims.hasScope('users:read'), isFalse);
      });

      test('admin scope покрывает все действия', () {
        expect(claims.hasScope('graphs:read'), isTrue);
        expect(claims.hasScope('graphs:write'), isTrue);
        expect(claims.hasScope('graphs:execute'), isTrue);
        expect(claims.hasScope('graphs:delete'), isTrue);
      });

      test('общий scope покрывает конкретные ресурсы', () {
        expect(claims.hasScope('projects:read:abc123'), isTrue);
        expect(claims.hasScope('projects:write:xyz789'), isTrue);
      });
    });

    group('hasAnyScope', () {
      test('возвращает true если есть хотя бы один scope', () {
        expect(claims.hasAnyScope(['projects:read']), isTrue);
        expect(claims.hasAnyScope(['projects:read', 'users:admin']), isTrue);
        expect(claims.hasAnyScope(['users:admin', 'projects:write']), isTrue);
      });

      test('возвращает false если нет ни одного scope', () {
        expect(claims.hasAnyScope(['users:read', 'users:write']), isFalse);
      });

      test('возвращает true для пустого списка', () {
        expect(claims.hasAnyScope([]), isTrue);
      });
    });

    group('hasAllScopes', () {
      test('возвращает true если есть все scopes', () {
        expect(claims.hasAllScopes(['projects:read', 'projects:write']), isTrue);
        expect(claims.hasAllScopes(['projects:read']), isTrue);
      });

      test('возвращает false если нет хотя бы одного scope', () {
        expect(claims.hasAllScopes(['projects:read', 'users:admin']), isFalse);
      });

      test('возвращает true для пустого списка', () {
        expect(claims.hasAllScopes([]), isTrue);
      });

      test('работает с admin scope', () {
        expect(claims.hasAllScopes(['graphs:read', 'graphs:write', 'graphs:execute']), isTrue);
      });
    });

    group('JSON serialization', () {
      test('toJson включает scopes', () {
        final json = claims.toJson();

        expect(json['scopes'], isNotNull);
        expect(json['scopes'], isA<List<String>>());
        expect(json['scopes'], contains('projects:read'));
        expect(json['scopes'], contains('projects:write'));
        expect(json['scopes'], contains('graphs:admin'));
      });

      test('fromJson парсит scopes', () {
        final json = {
          'sub': 'user123',
          'tid': 'tenant456',
          'email': 'test@example.com',
          'type': 'access',
          'iat': 1000000,
          'exp': 1001000,
          'jti': 'token123',
          'sid': 'session456',
          'scopes': ['projects:read', 'graphs:admin'],
        };

        final parsed = AqTokenClaims.fromJson(json);

        expect(parsed.scopes, hasLength(2));
        expect(parsed.scopes, contains('projects:read'));
        expect(parsed.scopes, contains('graphs:admin'));
      });

      test('fromJson работает без scopes (backward compatibility)', () {
        final json = {
          'sub': 'user123',
          'tid': 'tenant456',
          'email': 'test@example.com',
          'type': 'access',
          'iat': 1000000,
          'exp': 1001000,
          'jti': 'token123',
          'sid': 'session456',
        };

        final parsed = AqTokenClaims.fromJson(json);

        expect(parsed.scopes, isEmpty);
      });
    });

    group('legacy permissions compatibility', () {
      test('hasPermission всё ещё работает', () {
        final claimsWithPerms = AqTokenClaims(
          sub: 'user123',
          tid: 'tenant456',
          email: 'test@example.com',
          type: TokenType.access,
          iat: 1000000,
          exp: 1001000,
          jti: 'token123',
          sid: 'session456',
          perms: ['projects:read', 'graphs:*'],
        );

        expect(claimsWithPerms.hasPermission('projects:read'), isTrue);
        expect(claimsWithPerms.hasPermission('graphs:write'), isTrue);
        expect(claimsWithPerms.hasPermission('users:read'), isFalse);
      });

      test('можно использовать и perms и scopes одновременно', () {
        final claimsWithBoth = AqTokenClaims(
          sub: 'user123',
          tid: 'tenant456',
          email: 'test@example.com',
          type: TokenType.access,
          iat: 1000000,
          exp: 1001000,
          jti: 'token123',
          sid: 'session456',
          perms: ['legacy:read'],
          scopes: ['projects:read'],
        );

        expect(claimsWithBoth.hasPermission('legacy:read'), isTrue);
        expect(claimsWithBoth.hasScope('projects:read'), isTrue);
      });
    });

    group('complex scenarios', () {
      test('system:admin покрывает всё в system', () {
        final adminClaims = AqTokenClaims(
          sub: 'admin123',
          tid: 'tenant456',
          email: 'admin@example.com',
          type: TokenType.access,
          iat: 1000000,
          exp: 1001000,
          jti: 'token123',
          sid: 'session456',
          scopes: ['system:admin'],
        );

        expect(adminClaims.hasScope('system:audit'), isTrue);
        expect(adminClaims.hasScope('system:read'), isTrue);
        expect(adminClaims.hasScope('system:write'), isTrue);
      });

      test('множественные admin scopes', () {
        final multiAdminClaims = AqTokenClaims(
          sub: 'user123',
          tid: 'tenant456',
          email: 'test@example.com',
          type: TokenType.access,
          iat: 1000000,
          exp: 1001000,
          jti: 'token123',
          sid: 'session456',
          scopes: ['projects:admin', 'graphs:admin', 'users:read'],
        );

        expect(multiAdminClaims.hasAllScopes([
          'projects:read',
          'projects:write',
          'graphs:execute',
          'users:read',
        ]), isTrue);

        expect(multiAdminClaims.hasScope('users:write'), isFalse);
      });

      test('конкретные resource scopes', () {
        final specificClaims = AqTokenClaims(
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
            'projects:write:abc123',
          ],
        );

        expect(specificClaims.hasScope('projects:read:any'), isTrue);
        expect(specificClaims.hasScope('projects:write:abc123'), isTrue);
        expect(specificClaims.hasScope('projects:write:xyz789'), isFalse);
      });
    });
  });
}
