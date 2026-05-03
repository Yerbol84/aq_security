// pkgs/aq_security/lib/src/server/token_issuer.dart
//
// Server-only. Issues, refreshes and revokes JWT token pairs.
// Builds AqTokenClaims from user + roles, then signs with TokenCodec.

import 'package:uuid/uuid.dart';
import 'package:aq_schema/security/security.dart';

import '../shared/security_config.dart';

final class TokenIssuer {
  const TokenIssuer({required this.config, required this.codec});

  final SecurityConfig config;
  final TokenCodec codec;

  static final _uuid = Uuid();

  /// Issue a fresh access + refresh token pair.
  TokenPair issue({
    required AqUser user,
    required AqSession session,
    required List<AqRole> roles,
  }) {
    final now = _now();
    final perms = _flattenPermissions(roles);
    final scopes = _generateScopes(roles);
    final roleNames = roles.map((r) => r.name).toList();

    final accessClaims = AqTokenClaims(
      sub: user.id,
      tid: user.tenantId,
      email: user.email,
      name: user.displayName,
      type: TokenType.access,
      roles: roleNames,
      perms: perms,
      scopes: scopes,
      utype: user.userType,
      iat: now,
      exp: now + config.accessTokenTtlSeconds,
      jti: _uuid.v4(),
      sid: session.id,
    );

    final refreshClaims = AqTokenClaims(
      sub: user.id,
      tid: user.tenantId,
      email: user.email,
      name: user.displayName,
      type: TokenType.refresh,
      roles: roleNames,
      perms: perms,
      scopes: scopes,
      utype: user.userType,
      iat: now,
      exp: now + config.refreshTokenTtlSeconds,
      jti: _uuid.v4(),
      sid: session.id,
    );

    return TokenPair(
      accessToken: codec.encode(accessClaims),
      refreshToken: codec.encode(refreshClaims),
      accessExpiresAt: accessClaims.exp,
      refreshExpiresAt: refreshClaims.exp,
    );
  }

  /// Re-issue access token from a valid refresh token.
  /// Returns new pair; old refresh token is invalidated by the caller.
  TokenPair reissue({
    required AqTokenClaims refreshClaims,
    required AqUser user,
    required AqSession session,
    required List<AqRole> roles,
  }) {
    // Refresh token retains original expiry
    final now = _now();
    final perms = _flattenPermissions(roles);
    final scopes = _generateScopes(roles);
    final roleNames = roles.map((r) => r.name).toList();

    final accessClaims = AqTokenClaims(
      sub: user.id,
      tid: user.tenantId,
      email: user.email,
      name: user.displayName,
      type: TokenType.access,
      roles: roleNames,
      perms: perms,
      scopes: scopes,
      utype: user.userType,
      iat: now,
      exp: now + config.accessTokenTtlSeconds,
      jti: _uuid.v4(),
      sid: session.id,
    );

    // New refresh token — extends lifetime from now
    final newRefreshClaims = AqTokenClaims(
      sub: user.id,
      tid: user.tenantId,
      email: user.email,
      name: user.displayName,
      type: TokenType.refresh,
      roles: roleNames,
      perms: perms,
      scopes: scopes,
      utype: user.userType,
      iat: now,
      exp: now + config.refreshTokenTtlSeconds,
      jti: _uuid.v4(),
      sid: session.id,
    );

    return TokenPair(
      accessToken: codec.encode(accessClaims),
      refreshToken: codec.encode(newRefreshClaims),
      accessExpiresAt: accessClaims.exp,
      refreshExpiresAt: newRefreshClaims.exp,
    );
  }

  List<String> _flattenPermissions(List<AqRole> roles) {
    final perms = <String>{};
    for (final role in roles) {
      perms.addAll(role.permissions);
    }
    if (perms.contains('*')) return ['*'];
    return perms.toList();
  }

  /// Генерирует scopes из ролей.
  /// Конвертирует legacy permissions в новый scope формат.
  List<String> _generateScopes(List<AqRole> roles) {
    final scopes = <String>{};

    for (final role in roles) {
      // Если роль имеет wildcard permission, добавить все scopes
      if (role.permissions.contains('*')) {
        scopes.addAll(AqScopes.all);
        continue;
      }

      // Конвертировать permissions в scopes
      for (final perm in role.permissions) {
        // Если permission уже в формате scope (resource:action), добавить как есть
        if (perm.contains(':')) {
          scopes.add(perm);
        } else {
          // Legacy permission format — конвертировать в scopes
          // Например: "projects.read" -> "projects:read"
          final converted = perm.replaceAll('.', ':');
          scopes.add(converted);
        }
      }
    }

    return scopes.toList();
  }

  static int _now() => DateTime.now().millisecondsSinceEpoch ~/ 1000;
}
