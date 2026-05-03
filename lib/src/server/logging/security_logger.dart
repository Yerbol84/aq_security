// pkgs/aq_security/lib/src/server/logging/security_logger.dart
//
// Server-only. Security-specific logging helpers.

import 'context_logger.dart';
import 'log_context.dart';

/// Security logger для специфичных security событий
final class SecurityLogger {
  SecurityLogger(this.contextLogger);

  final ContextLogger contextLogger;

  /// Log authentication attempt
  void logAuthAttempt({
    LogContext? context,
    required String method,
    required bool success,
    String? userId,
    String? reason,
    String? ip,
  }) {
    contextLogger.authEvent(
      success ? 'Authentication successful' : 'Authentication failed',
      context: context,
      method: method,
      success: success,
      reason: reason,
      metadata: {
        if (userId != null) 'user_id': userId,
        if (ip != null) 'ip': ip,
      },
    );
  }

  /// Log token issued
  void logTokenIssued({
    LogContext? context,
    required String type,
    required String userId,
    int? expiresIn,
  }) {
    contextLogger.info(
      'Token issued',
      context: context,
      component: 'auth',
      metadata: {
        'type': type,
        'user_id': userId,
        if (expiresIn != null) 'expires_in': expiresIn,
      },
    );
  }

  /// Log token validation
  void logTokenValidation({
    LogContext? context,
    required bool valid,
    String? reason,
    String? userId,
  }) {
    contextLogger.debug(
      valid ? 'Token valid' : 'Token invalid',
      context: context,
      component: 'auth',
      metadata: {
        'valid': valid,
        if (reason != null) 'reason': reason,
        if (userId != null) 'user_id': userId,
      },
    );
  }

  /// Log rate limit hit
  void logRateLimitHit({
    LogContext? context,
    required String strategy,
    required String key,
    required int remaining,
    required int limit,
  }) {
    contextLogger.rateLimitEvent(
      'Rate limit checked',
      context: context,
      strategy: strategy,
      blocked: false,
      remaining: remaining,
      limit: limit,
      metadata: {
        'key': key,
      },
    );
  }

  /// Log rate limit blocked
  void logRateLimitBlocked({
    LogContext? context,
    required String strategy,
    required String key,
    required int limit,
    int? retryAfter,
  }) {
    contextLogger.rateLimitEvent(
      'Rate limit exceeded',
      context: context,
      strategy: strategy,
      blocked: true,
      limit: limit,
      metadata: {
        'key': key,
        if (retryAfter != null) 'retry_after': retryAfter,
      },
    );
  }

  /// Log connection attempt
  void logConnectionAttempt({
    LogContext? context,
    required bool allowed,
    required String ip,
    String? reason,
    int? activeConnections,
    int? maxConnections,
  }) {
    contextLogger.dosProtectionEvent(
      allowed ? 'Connection allowed' : 'Connection rejected',
      context: context,
      type: 'connection_limit',
      blocked: !allowed,
      reason: reason,
      metadata: {
        'ip': ip,
        if (activeConnections != null) 'active_connections': activeConnections,
        if (maxConnections != null) 'max_connections': maxConnections,
      },
    );
  }

  /// Log IP blocked
  void logIpBlocked({
    LogContext? context,
    required String ip,
    required String reason,
    int? durationSeconds,
    bool permanent = false,
  }) {
    contextLogger.warn(
      permanent ? 'IP permanently blocked' : 'IP temporarily blocked',
      context: context,
      component: 'dos_protection',
      metadata: {
        'ip': ip,
        'reason': reason,
        'permanent': permanent,
        if (durationSeconds != null) 'duration_seconds': durationSeconds,
      },
    );
  }

  /// Log IP unblocked
  void logIpUnblocked({
    LogContext? context,
    required String ip,
    String? reason,
  }) {
    contextLogger.info(
      'IP unblocked',
      context: context,
      component: 'dos_protection',
      metadata: {
        'ip': ip,
        if (reason != null) 'reason': reason,
      },
    );
  }

  /// Log request validation failure
  void logRequestValidationFailure({
    LogContext? context,
    required String reason,
    String? ip,
    Map<String, dynamic>? details,
  }) {
    contextLogger.warn(
      'Request validation failed',
      context: context,
      component: 'dos_protection',
      metadata: {
        'reason': reason,
        if (ip != null) 'ip': ip,
        if (details != null) ...details,
      },
    );
  }

  /// Log policy evaluation
  void logPolicyEvaluation({
    LogContext? context,
    required bool allowed,
    required String policy,
    String? resource,
    String? action,
    String? userId,
  }) {
    contextLogger.securityEvent(
      allowed ? 'Policy allowed' : 'Policy denied',
      context: context,
      action: 'policy_evaluation',
      allowed: allowed,
      metadata: {
        'policy': policy,
        if (resource != null) 'resource': resource,
        if (action != null) 'action': action,
        if (userId != null) 'user_id': userId,
      },
    );
  }

  /// Log permission check
  void logPermissionCheck({
    LogContext? context,
    required bool granted,
    required String resource,
    required String action,
    String? userId,
    String? reason,
  }) {
    contextLogger.securityEvent(
      granted ? 'Permission granted' : 'Permission denied',
      context: context,
      action: 'permission_check',
      allowed: granted,
      reason: reason,
      metadata: {
        'resource': resource,
        'action': action,
        if (userId != null) 'user_id': userId,
      },
    );
  }

  /// Log security header violation
  void logSecurityHeaderViolation({
    LogContext? context,
    required String header,
    required String violation,
    String? ip,
  }) {
    contextLogger.warn(
      'Security header violation',
      context: context,
      component: 'security_headers',
      metadata: {
        'header': header,
        'violation': violation,
        if (ip != null) 'ip': ip,
      },
    );
  }

  /// Log CORS violation
  void logCorsViolation({
    LogContext? context,
    required String origin,
    String? reason,
    String? ip,
  }) {
    contextLogger.warn(
      'CORS violation',
      context: context,
      component: 'cors',
      metadata: {
        'origin': origin,
        if (reason != null) 'reason': reason,
        if (ip != null) 'ip': ip,
      },
    );
  }

  /// Log suspicious activity
  void logSuspiciousActivity({
    LogContext? context,
    required String activity,
    required String reason,
    String? ip,
    String? userId,
    Map<String, dynamic>? details,
  }) {
    contextLogger.warn(
      'Suspicious activity detected',
      context: context,
      component: 'security',
      metadata: {
        'activity': activity,
        'reason': reason,
        if (ip != null) 'ip': ip,
        if (userId != null) 'user_id': userId,
        if (details != null) ...details,
      },
    );
  }

  /// Log security incident
  void logSecurityIncident({
    LogContext? context,
    required String incident,
    required String severity,
    String? ip,
    String? userId,
    Map<String, dynamic>? details,
  }) {
    contextLogger.error(
      'Security incident',
      context: context,
      component: 'security',
      metadata: {
        'incident': incident,
        'severity': severity,
        if (ip != null) 'ip': ip,
        if (userId != null) 'user_id': userId,
        if (details != null) ...details,
      },
    );
  }
}

/// Global security logger instance
SecurityLogger? _globalSecurityLogger;

/// Get global security logger
SecurityLogger get securityLogger {
  if (_globalSecurityLogger == null) {
    throw StateError(
      'Security logger not initialized. Call initializeSecurityLogger() first.',
    );
  }
  return _globalSecurityLogger!;
}

/// Initialize global security logger
void initializeSecurityLogger(ContextLogger contextLogger) {
  _globalSecurityLogger = SecurityLogger(contextLogger);
}

/// Reset security logger (для тестов)
void resetSecurityLogger() {
  _globalSecurityLogger = null;
}
