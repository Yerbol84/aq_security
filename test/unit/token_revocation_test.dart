// test/unit/token_revocation_test.dart
//
// Тесты для TokenRevocationService

import 'package:test/test.dart';
import 'package:aq_security/aq_security_server.dart';
import 'package:aq_schema/security/security.dart';

// Mock repository для тестирования
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

void main() {
  group('TokenRevocationService', () {
    late TokenRevocationService service;
    late MockRevokedTokenRepository repo;

    setUp(() {
      repo = MockRevokedTokenRepository();
      service = TokenRevocationService(repo: repo);
    });

    group('revokeToken', () {
      test('добавляет token в blacklist', () async {
        await service.revokeToken(
          jti: 'token123',
          userId: 'user456',
          tenantId: 'tenant789',
          expiresAt: 2000000,
          reason: 'test_revocation',
        );

        final isRevoked = await service.isRevoked('token123');
        expect(isRevoked, isTrue);
      });

      test('сохраняет metadata о revocation', () async {
        await service.revokeToken(
          jti: 'token123',
          userId: 'user456',
          tenantId: 'tenant789',
          expiresAt: 2000000,
          reason: 'password_changed',
          revokedBy: 'admin123',
        );

        final token = await service.getRevokedToken('token123');
        expect(token, isNotNull);
        expect(token!.jti, equals('token123'));
        expect(token.userId, equals('user456'));
        expect(token.reason, equals('password_changed'));
        expect(token.revokedBy, equals('admin123'));
      });
    });

    group('revokeFromClaims', () {
      test('revoke token из claims', () async {
        final claims = AqTokenClaims(
          sub: 'user123',
          tid: 'tenant456',
          email: 'test@example.com',
          type: TokenType.access,
          iat: 1000000,
          exp: 2000000,
          jti: 'token789',
          sid: 'session123',
        );

        await service.revokeFromClaims(
          claims: claims,
          reason: 'user_logout',
        );

        final isRevoked = await service.isRevoked('token789');
        expect(isRevoked, isTrue);
      });
    });

    group('isRevoked', () {
      test('возвращает true для revoked token', () async {
        await service.revokeToken(
          jti: 'token123',
          userId: 'user456',
          tenantId: 'tenant789',
          expiresAt: 2000000,
          reason: 'test',
        );

        expect(await service.isRevoked('token123'), isTrue);
      });

      test('возвращает false для не-revoked token', () async {
        expect(await service.isRevoked('nonexistent'), isFalse);
      });
    });

    group('isRevokedFromClaims', () {
      test('проверяет revocation по claims', () async {
        final claims = AqTokenClaims(
          sub: 'user123',
          tid: 'tenant456',
          email: 'test@example.com',
          type: TokenType.access,
          iat: 1000000,
          exp: 2000000,
          jti: 'token789',
          sid: 'session123',
        );

        await service.revokeFromClaims(claims: claims, reason: 'test');

        expect(await service.isRevokedFromClaims(claims), isTrue);
      });
    });

    group('revokeAllUserTokens', () {
      test('revoke все tokens пользователя', () async {
        // Создать несколько tokens для пользователя
        await service.revokeToken(
          jti: 'token1',
          userId: 'user123',
          tenantId: 'tenant456',
          expiresAt: 2000000,
          reason: 'test',
        );
        await service.revokeToken(
          jti: 'token2',
          userId: 'user123',
          tenantId: 'tenant456',
          expiresAt: 2000000,
          reason: 'test',
        );

        final count = await service.revokeAllUserTokens(
          userId: 'user123',
          reason: RevocationReasons.passwordChanged,
        );

        expect(count, equals(2));
      });
    });

    group('listUserRevokedTokens', () {
      test('возвращает список revoked tokens пользователя', () async {
        await service.revokeToken(
          jti: 'token1',
          userId: 'user123',
          tenantId: 'tenant456',
          expiresAt: 2000000,
          reason: 'test1',
        );
        await service.revokeToken(
          jti: 'token2',
          userId: 'user123',
          tenantId: 'tenant456',
          expiresAt: 2000000,
          reason: 'test2',
        );

        final tokens = await service.listUserRevokedTokens('user123');

        expect(tokens, hasLength(2));
        expect(tokens.map((t) => t.jti), containsAll(['token1', 'token2']));
      });
    });

    group('cleanupExpired', () {
      test('удаляет истёкшие tokens', () async {
        final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;

        // Истёкший token
        await service.revokeToken(
          jti: 'expired',
          userId: 'user123',
          tenantId: 'tenant456',
          expiresAt: now - 1000,
          reason: 'test',
        );

        // Активный token
        await service.revokeToken(
          jti: 'active',
          userId: 'user123',
          tenantId: 'tenant456',
          expiresAt: now + 1000,
          reason: 'test',
        );

        final cleaned = await service.cleanupExpired();

        expect(cleaned, equals(1));
        expect(await service.isRevoked('expired'), isFalse);
        expect(await service.isRevoked('active'), isTrue);
      });
    });

    group('RevocationReasons', () {
      test('содержит стандартные причины', () {
        expect(RevocationReasons.userLogout, equals('user_logout'));
        expect(RevocationReasons.passwordChanged, equals('password_changed'));
        expect(RevocationReasons.accountCompromised, equals('account_compromised'));
        expect(RevocationReasons.adminRevoked, equals('admin_revoked'));
      });
    });
  });
}
