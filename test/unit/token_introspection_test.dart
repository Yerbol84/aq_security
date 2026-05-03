// test/unit/token_introspection_test.dart
//
// Тесты для TokenIntrospectionService

import 'package:test/test.dart';
import 'package:aq_security/aq_security_server.dart';
import 'package:aq_schema/security/security.dart';

void main() {
  group('TokenIntrospectionService', () {
    late TokenIntrospectionService service;
    late TokenCodec codec;
    late TokenRevocationService revocationService;
    late MockRevokedTokenRepository revokedRepo;

    setUp(() {
      codec = TokenCodec(secret: 'test_secret_key_for_testing_only');
      revokedRepo = MockRevokedTokenRepository();
      revocationService = TokenRevocationService(repo: revokedRepo);
      service = TokenIntrospectionService(
        codec: codec,
        revocationService: revocationService,
      );
    });

    group('introspect', () {
      test('возвращает active=true для валидного token', () async {
        final claims = AqTokenClaims(
          sub: 'user123',
          tid: 'tenant456',
          email: 'test@example.com',
          type: TokenType.access,
          iat: DateTime.now().millisecondsSinceEpoch ~/ 1000,
          exp: DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600,
          jti: 'token123',
          sid: 'session456',
          scopes: ['projects:read', 'graphs:write'],
        );

        final token = codec.encode(claims);
        final response = await service.introspect(token);

        expect(response.active, isTrue);
        expect(response.sub, equals('user123'));
        expect(response.username, equals('test@example.com'));
        expect(response.clientId, equals('tenant456'));
        expect(response.scope, equals('projects:read graphs:write'));
        expect(response.tokenType, equals('Bearer'));
      });

      test('возвращает active=false для истёкшего token', () async {
        final claims = AqTokenClaims(
          sub: 'user123',
          tid: 'tenant456',
          email: 'test@example.com',
          type: TokenType.access,
          iat: 1000000,
          exp: 1000001, // Истёк
          jti: 'token123',
          sid: 'session456',
        );

        final token = codec.encode(claims);
        final response = await service.introspect(token);

        expect(response.active, isFalse);
      });

      test('возвращает active=false для невалидного token', () async {
        final response = await service.introspect('invalid_token');

        expect(response.active, isFalse);
      });

      test('возвращает active=false для revoked token', () async {
        final claims = AqTokenClaims(
          sub: 'user123',
          tid: 'tenant456',
          email: 'test@example.com',
          type: TokenType.access,
          iat: DateTime.now().millisecondsSinceEpoch ~/ 1000,
          exp: DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600,
          jti: 'token123',
          sid: 'session456',
        );

        final token = codec.encode(claims);

        // Revoke token
        await revocationService.revokeFromClaims(
          claims: claims,
          reason: 'test',
        );

        final response = await service.introspect(token);

        expect(response.active, isFalse);
      });
    });

    group('introspectWithScopes', () {
      test('возвращает authorized=true если есть требуемые scopes', () async {
        final claims = AqTokenClaims(
          sub: 'user123',
          tid: 'tenant456',
          email: 'test@example.com',
          type: TokenType.access,
          iat: DateTime.now().millisecondsSinceEpoch ~/ 1000,
          exp: DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600,
          jti: 'token123',
          sid: 'session456',
          scopes: ['projects:read', 'projects:write'],
        );

        final token = codec.encode(claims);
        final result = await service.introspectWithScopes(
          token,
          ['projects:read'],
        );

        expect(result.active, isTrue);
        expect(result.authorized, isTrue);
        expect(result.claims, isNotNull);
      });

      test('возвращает authorized=false если нет требуемых scopes', () async {
        final claims = AqTokenClaims(
          sub: 'user123',
          tid: 'tenant456',
          email: 'test@example.com',
          type: TokenType.access,
          iat: DateTime.now().millisecondsSinceEpoch ~/ 1000,
          exp: DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600,
          jti: 'token123',
          sid: 'session456',
          scopes: ['projects:read'],
        );

        final token = codec.encode(claims);
        final result = await service.introspectWithScopes(
          token,
          ['projects:write'],
        );

        expect(result.active, isTrue);
        expect(result.authorized, isFalse);
      });

      test('возвращает active=false для невалидного token', () async {
        final result = await service.introspectWithScopes(
          'invalid_token',
          ['projects:read'],
        );

        expect(result.active, isFalse);
        expect(result.authorized, isFalse);
        expect(result.claims, isNull);
      });
    });

    group('introspectBatch', () {
      test('introspect несколько tokens', () async {
        final claims1 = AqTokenClaims(
          sub: 'user123',
          tid: 'tenant456',
          email: 'test1@example.com',
          type: TokenType.access,
          iat: DateTime.now().millisecondsSinceEpoch ~/ 1000,
          exp: DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600,
          jti: 'token1',
          sid: 'session1',
        );

        final claims2 = AqTokenClaims(
          sub: 'user456',
          tid: 'tenant789',
          email: 'test2@example.com',
          type: TokenType.access,
          iat: 1000000,
          exp: 1000001, // Истёк
          jti: 'token2',
          sid: 'session2',
        );

        final token1 = codec.encode(claims1);
        final token2 = codec.encode(claims2);

        final results = await service.introspectBatch([token1, token2]);

        expect(results, hasLength(2));
        expect(results[token1]!.active, isTrue);
        expect(results[token2]!.active, isFalse);
      });
    });

    group('TokenIntrospectionResponse', () {
      test('toJson включает все поля для active token', () {
        final response = TokenIntrospectionResponse(
          active: true,
          scope: 'projects:read graphs:write',
          clientId: 'tenant123',
          username: 'test@example.com',
          tokenType: 'Bearer',
          exp: 2000000,
          iat: 1000000,
          sub: 'user123',
          jti: 'token456',
        );

        final json = response.toJson();

        expect(json['active'], isTrue);
        expect(json['scope'], equals('projects:read graphs:write'));
        expect(json['client_id'], equals('tenant123'));
        expect(json['username'], equals('test@example.com'));
        expect(json['token_type'], equals('Bearer'));
        expect(json['exp'], equals(2000000));
        expect(json['iat'], equals(1000000));
        expect(json['sub'], equals('user123'));
        expect(json['jti'], equals('token456'));
      });

      test('toJson возвращает только active=false для inactive token', () {
        final response = TokenIntrospectionResponse.inactive();
        final json = response.toJson();

        expect(json, hasLength(1));
        expect(json['active'], isFalse);
      });

      test('fromClaims создаёт response из claims', () {
        final claims = AqTokenClaims(
          sub: 'user123',
          tid: 'tenant456',
          email: 'test@example.com',
          type: TokenType.access,
          iat: 1000000,
          exp: 2000000,
          jti: 'token789',
          sid: 'session123',
          scopes: ['projects:read', 'graphs:admin'],
        );

        final response = TokenIntrospectionResponse.fromClaims(claims);

        expect(response.active, isTrue);
        expect(response.sub, equals('user123'));
        expect(response.clientId, equals('tenant456'));
        expect(response.username, equals('test@example.com'));
        expect(response.scope, equals('projects:read graphs:admin'));
        expect(response.exp, equals(2000000));
        expect(response.iat, equals(1000000));
        expect(response.jti, equals('token789'));
      });
    });
  });
}

// Mock repository (same as in token_revocation_test.dart)
class MockRevokedTokenRepository implements IRevokedTokenRepository {
  final Map<String, AqRevokedToken> _storage = {};
  final Map<String, List<String>> _userTokens = {};
  final Map<String, List<String>> _sessionTokens = {};

  @override
  Future<void> revoke(AqRevokedToken token) async {
    _storage[token.jti] = token;
    _userTokens.putIfAbsent(token.userId, () => []).add(token.jti);
  }

  @override
  Future<bool> isRevoked(String jti) async {
    return _storage.containsKey(jti);
  }

  @override
  Future<AqRevokedToken?> findByJti(String jti) async {
    return _storage[jti];
  }

  @override
  Future<int> revokeAllForUser(String userId, {String? reason}) async {
    final tokens = _userTokens[userId] ?? [];
    return tokens.length;
  }

  @override
  Future<int> revokeAllForSession(String sessionId, {String? reason}) async {
    final tokens = _sessionTokens[sessionId] ?? [];
    return tokens.length;
  }

  @override
  Future<int> cleanupExpired() async {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final expired = _storage.values.where((t) => t.expiresAt <= now).toList();

    for (final token in expired) {
      _storage.remove(token.jti);
    }

    return expired.length;
  }

  @override
  Future<List<AqRevokedToken>> listByUser(String userId) async {
    final jtis = _userTokens[userId] ?? [];
    return jtis.map((jti) => _storage[jti]!).toList();
  }
}
