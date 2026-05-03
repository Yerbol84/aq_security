// pkgs/aq_security/lib/src/server/token_revocation_service.dart
//
// Server-only. Token revocation и blacklist management.
// Используется для немедленной инвалидации JWT tokens.

import 'package:aq_schema/security/security.dart';

final class TokenRevocationService {
  TokenRevocationService({required this.repo});

  final IRevokedTokenRepository repo;

  /// Revoke конкретный token по jti.
  Future<void> revokeToken({
    required String jti,
    required String userId,
    required String tenantId,
    required int expiresAt,
    required String reason,
    String? revokedBy,
  }) async {
    final revokedToken = AqRevokedToken(
      jti: jti,
      userId: userId,
      tenantId: tenantId,
      revokedAt: _now(),
      expiresAt: expiresAt,
      reason: reason,
      revokedBy: revokedBy,
    );

    await repo.revoke(revokedToken);
  }

  /// Revoke token из claims.
  Future<void> revokeFromClaims({
    required AqTokenClaims claims,
    required String reason,
    String? revokedBy,
  }) async {
    await revokeToken(
      jti: claims.jti,
      userId: claims.sub,
      tenantId: claims.tid,
      expiresAt: claims.exp,
      reason: reason,
      revokedBy: revokedBy,
    );
  }

  /// Проверить, revoked ли token.
  Future<bool> isRevoked(String jti) async {
    return repo.isRevoked(jti);
  }

  /// Проверить, revoked ли token из claims.
  Future<bool> isRevokedFromClaims(AqTokenClaims claims) async {
    return repo.isRevoked(claims.jti);
  }

  /// Revoke все tokens пользователя.
  /// Используется при:
  /// - Смене пароля
  /// - Компрометации аккаунта
  /// - Удалении пользователя
  Future<int> revokeAllUserTokens({
    required String userId,
    String reason = 'user_revoked_all',
    String? revokedBy,
  }) async {
    return repo.revokeAllForUser(userId, reason: reason);
  }

  /// Revoke все tokens сессии.
  /// Используется при logout.
  Future<int> revokeAllSessionTokens({
    required String sessionId,
    String reason = 'session_logout',
    String? revokedBy,
  }) async {
    return repo.revokeAllForSession(sessionId, reason: reason);
  }

  /// Получить список revoked tokens пользователя.
  Future<List<AqRevokedToken>> listUserRevokedTokens(String userId) async {
    return repo.listByUser(userId);
  }

  /// Cleanup истёкших tokens из blacklist.
  /// Должен вызываться периодически (cron job).
  Future<int> cleanupExpired() async {
    return repo.cleanupExpired();
  }

  /// Получить информацию о revoked token.
  Future<AqRevokedToken?> getRevokedToken(String jti) async {
    return repo.findByJti(jti);
  }

  static int _now() => DateTime.now().millisecondsSinceEpoch ~/ 1000;
}

/// Причины revocation для стандартных сценариев.
abstract final class RevocationReasons {
  static const userLogout = 'user_logout';
  static const userRevokedAll = 'user_revoked_all';
  static const passwordChanged = 'password_changed';
  static const accountCompromised = 'account_compromised';
  static const accountDeleted = 'account_deleted';
  static const sessionExpired = 'session_expired';
  static const adminRevoked = 'admin_revoked';
  static const suspiciousActivity = 'suspicious_activity';
  static const tokenRefreshed = 'token_refreshed';
}
