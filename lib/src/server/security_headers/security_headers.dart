// pkgs/aq_security/lib/src/server/security_headers/security_headers.dart
//
// Server-only. Security headers для защиты от XSS, clickjacking, и других атак.

/// Security headers configuration
final class SecurityHeadersConfig {
  const SecurityHeadersConfig({
    this.xFrameOptions = 'DENY',
    this.xContentTypeOptions = 'nosniff',
    this.xXssProtection = '1; mode=block',
    this.strictTransportSecurity = 'max-age=31536000; includeSubDomains',
    this.contentSecurityPolicy,
    this.referrerPolicy = 'strict-origin-when-cross-origin',
    this.permissionsPolicy,
    this.enableHsts = true,
    this.enableCsp = true,
  });

  /// X-Frame-Options: защита от clickjacking
  /// Values: DENY, SAMEORIGIN, ALLOW-FROM uri
  final String xFrameOptions;

  /// X-Content-Type-Options: предотвращает MIME type sniffing
  /// Value: nosniff
  final String xContentTypeOptions;

  /// X-XSS-Protection: защита от XSS (legacy, но всё ещё полезно)
  /// Values: 0, 1, 1; mode=block
  final String xXssProtection;

  /// Strict-Transport-Security: принудительный HTTPS
  /// Format: max-age=<seconds>; includeSubDomains; preload
  final String strictTransportSecurity;

  /// Content-Security-Policy: защита от XSS и injection атак
  final String? contentSecurityPolicy;

  /// Referrer-Policy: контроль referrer information
  /// Values: no-referrer, no-referrer-when-downgrade, origin,
  ///         origin-when-cross-origin, same-origin, strict-origin,
  ///         strict-origin-when-cross-origin, unsafe-url
  final String referrerPolicy;

  /// Permissions-Policy: контроль browser features
  /// Format: feature=(self "origin"), feature=()
  final String? permissionsPolicy;

  /// Включить HSTS
  final bool enableHsts;

  /// Включить CSP
  final bool enableCsp;

  /// Default production config
  static const production = SecurityHeadersConfig(
    xFrameOptions: 'DENY',
    xContentTypeOptions: 'nosniff',
    xXssProtection: '1; mode=block',
    strictTransportSecurity: 'max-age=31536000; includeSubDomains; preload',
    contentSecurityPolicy: "default-src 'self'; "
        "script-src 'self' 'unsafe-inline' 'unsafe-eval'; "
        "style-src 'self' 'unsafe-inline'; "
        "img-src 'self' data: https:; "
        "font-src 'self' data:; "
        "connect-src 'self'; "
        "frame-ancestors 'none'; "
        "base-uri 'self'; "
        "form-action 'self'",
    referrerPolicy: 'strict-origin-when-cross-origin',
    permissionsPolicy: 'geolocation=(), microphone=(), camera=()',
    enableHsts: true,
    enableCsp: true,
  );

  /// Development config (более мягкий)
  static const development = SecurityHeadersConfig(
    xFrameOptions: 'SAMEORIGIN',
    xContentTypeOptions: 'nosniff',
    xXssProtection: '1; mode=block',
    strictTransportSecurity: 'max-age=0',
    contentSecurityPolicy: "default-src 'self' 'unsafe-inline' 'unsafe-eval'; "
        "img-src 'self' data: https:; "
        "connect-src 'self' ws: wss:",
    referrerPolicy: 'no-referrer-when-downgrade',
    permissionsPolicy: null,
    enableHsts: false,
    enableCsp: true,
  );

  /// Получить headers map
  Map<String, String> toHeaders() {
    final headers = <String, String>{
      'X-Frame-Options': xFrameOptions,
      'X-Content-Type-Options': xContentTypeOptions,
      'X-XSS-Protection': xXssProtection,
      'Referrer-Policy': referrerPolicy,
    };

    if (enableHsts) {
      headers['Strict-Transport-Security'] = strictTransportSecurity;
    }

    if (enableCsp && contentSecurityPolicy != null) {
      headers['Content-Security-Policy'] = contentSecurityPolicy!;
    }

    if (permissionsPolicy != null) {
      headers['Permissions-Policy'] = permissionsPolicy!;
    }

    return headers;
  }
}

/// CSP Builder для удобного создания CSP
final class CspBuilder {
  CspBuilder();

  final Map<String, List<String>> _directives = {};

  /// default-src
  CspBuilder defaultSrc(List<String> sources) {
    _directives['default-src'] = sources;
    return this;
  }

  /// script-src
  CspBuilder scriptSrc(List<String> sources) {
    _directives['script-src'] = sources;
    return this;
  }

  /// style-src
  CspBuilder styleSrc(List<String> sources) {
    _directives['style-src'] = sources;
    return this;
  }

  /// img-src
  CspBuilder imgSrc(List<String> sources) {
    _directives['img-src'] = sources;
    return this;
  }

  /// font-src
  CspBuilder fontSrc(List<String> sources) {
    _directives['font-src'] = sources;
    return this;
  }

  /// connect-src
  CspBuilder connectSrc(List<String> sources) {
    _directives['connect-src'] = sources;
    return this;
  }

  /// frame-src
  CspBuilder frameSrc(List<String> sources) {
    _directives['frame-src'] = sources;
    return this;
  }

  /// frame-ancestors
  CspBuilder frameAncestors(List<String> sources) {
    _directives['frame-ancestors'] = sources;
    return this;
  }

  /// base-uri
  CspBuilder baseUri(List<String> sources) {
    _directives['base-uri'] = sources;
    return this;
  }

  /// form-action
  CspBuilder formAction(List<String> sources) {
    _directives['form-action'] = sources;
    return this;
  }

  /// upgrade-insecure-requests
  CspBuilder upgradeInsecureRequests() {
    _directives['upgrade-insecure-requests'] = [];
    return this;
  }

  /// block-all-mixed-content
  CspBuilder blockAllMixedContent() {
    _directives['block-all-mixed-content'] = [];
    return this;
  }

  /// Build CSP string
  String build() {
    final parts = <String>[];

    for (final entry in _directives.entries) {
      if (entry.value.isEmpty) {
        parts.add(entry.key);
      } else {
        parts.add('${entry.key} ${entry.value.join(' ')}');
      }
    }

    return parts.join('; ');
  }

  /// Strict CSP для production
  static String strict() {
    return CspBuilder()
        .defaultSrc(["'self'"])
        .scriptSrc(["'self'"])
        .styleSrc(["'self'"])
        .imgSrc(["'self'", 'data:', 'https:'])
        .fontSrc(["'self'", 'data:'])
        .connectSrc(["'self'"])
        .frameAncestors(["'none'"])
        .baseUri(["'self'"])
        .formAction(["'self'"])
        .upgradeInsecureRequests()
        .build();
  }

  /// Relaxed CSP для development
  static String relaxed() {
    return CspBuilder()
        .defaultSrc(["'self'", "'unsafe-inline'", "'unsafe-eval'"])
        .imgSrc(["'self'", 'data:', 'https:'])
        .connectSrc(["'self'", 'ws:', 'wss:'])
        .build();
  }
}
