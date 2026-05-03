// pkgs/aq_security/lib/src/server/token_introspection_service.dart
//
// Server-only. Token introspection (RFC 7662).
// Проверяет token validity и возвращает metadata.

import 'package:aq_schema/security/security.dart';
import 'token_revocation_service.dart';

/// Token introspection response (RFC 7662).
final class TokenIntrospectionResponse {
  const TokenIntrospectionResponse({
    required this.active,
    this.scope,
    this.clientId,
    this.username,
    this.tokenType,
    this.exp,
    this.iat,
    this.sub,
    this.aud,
    this.iss,
    this.jti,
    this.claims,
  });

  /// Активен ли token
  final bool active;

  /// Scopes (space-separated)
  final String? scope;

  /// Client ID (tenant ID)
  final String? clientId;

  /// Username (email)
  final String? username;

  /// Token type (обычно "Bearer")
  final String? tokenType;

  /// Expiration time (Unix seconds)
  final int? exp;

  /// Issued at (Unix seconds)
  final int? iat;

  /// Subject (user ID)
  final String? sub;

  /// Audience
  final String? aud;

  /// Issuer
  final String? iss;

  /// JWT ID
  final String? jti;

  /// Полные claims (опционально)
  final AqTokenClaims? claims;

  factory TokenIntrospectionResponse.inactive() =>
      const TokenIntrospectionResponse(active: false);

  factory TokenIntrospectionResponse.fromClaims(AqTokenClaims claims) =>
      TokenIntrospectionResponse(
        active: true,
        scope: claims.scopes.join(' '),
        clientId: claims.tid,
        username: claims.email,
        tokenType: 'Bearer',
        exp: claims.exp,
        iat: claims.iat,
        sub: claims.sub,
        jti: claims.jti,
        claims: claims,
      );

  Map<String, dynamic> toJson() {
    final m = <String, dynamic>{'active': active};
    if (!active) return m;

    if (scope != null) m['scope'] = scope;
    if (clientId != null) m['client_id'] = clientId;
    if (username != null) m['username'] = username;
    if (tokenType != null) m['token_type'] = tokenType;
    if (exp != null) m['exp'] = exp;
    if (iat != null) m['iat'] = iat;
    if (sub != null) m['sub'] = sub;
    if (aud != null) m['aud'] = aud;
    if (iss != null) m['iss'] = iss;
    if (jti != null) m['jti'] = jti;

    return m;
  }
}

final class TokenIntrospectionService {
  TokenIntrospectionService({
    required this.codec,
    required this.revocationService,
  });

  final TokenCodec codec;
  final TokenRevocationService revocationService;

  /// Introspect token и вернуть metadata.
  ///
  /// Проверяет:
  /// - Token signature
  /// - Token expiration
  /// - Token revocation
  Future<TokenIntrospectionResponse> introspect(String token) async {
    // Декодировать и валидировать token
    final AqTokenClaims claims;
    try {
      claims = codec.decode(token);
    } catch (e) {
      // Invalid token format or signature
      return TokenIntrospectionResponse.inactive();
    }

    // Проверить expiration
    if (claims.isExpired) {
      return TokenIntrospectionResponse.inactive();
    }

    // Проверить revocation
    final isRevoked = await revocationService.isRevoked(claims.jti);
    if (isRevoked) {
      return TokenIntrospectionResponse.inactive();
    }

    // Token активен
    return TokenIntrospectionResponse.fromClaims(claims);
  }

  /// Introspect token и проверить требуемые scopes.
  Future<({bool active, bool authorized, AqTokenClaims? claims})> introspectWithScopes(
    String token,
    List<String> requiredScopes,
  ) async {
    final response = await introspect(token);

    if (!response.active) {
      return (active: false, authorized: false, claims: null);
    }

    final claims = response.claims!;
    final authorized = claims.hasAllScopes(requiredScopes);

    return (active: true, authorized: authorized, claims: claims);
  }

  /// Batch introspection для нескольких tokens.
  Future<Map<String, TokenIntrospectionResponse>> introspectBatch(
    List<String> tokens,
  ) async {
    final results = <String, TokenIntrospectionResponse>{};

    for (final token in tokens) {
      final response = await introspect(token);
      results[token] = response;
    }

    return results;
  }
}
