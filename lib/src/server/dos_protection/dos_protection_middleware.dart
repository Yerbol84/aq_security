// pkgs/aq_security/lib/src/server/dos_protection/dos_protection_middleware.dart
//
// Server-only. Комплексный middleware для DoS protection.

import 'dart:convert';
import 'package:shelf/shelf.dart';
import 'package:uuid/uuid.dart';
import 'connection_limiter.dart';
import 'request_validator.dart';
import 'ip_blacklist.dart';

/// DoS protection middleware
Middleware dosProtectionMiddleware({
  required ConnectionLimiter connectionLimiter,
  required RequestValidator requestValidator,
  required IpBlacklist ipBlacklist,
}) {
  final uuid = Uuid();

  return (Handler handler) {
    return (Request request) async {
      final ip = _getClientIp(request);
      final connectionId = uuid.v4();

      // 1. Проверить IP blacklist
      if (ipBlacklist.isBlocked(ip)) {
        final entry = ipBlacklist.getEntry(ip);
        return Response(
          403,
          body: jsonEncode({
            'error': 'ip_blocked',
            'message': 'Your IP has been blocked',
            'reason': entry?.reason,
          }),
          headers: {'Content-Type': 'application/json'},
        );
      }

      // 2. Проверить connection limit
      final connectionResult = connectionLimiter.tryConnect(
        connectionId: connectionId,
        ip: ip,
      );

      if (!connectionResult.allowed) {
        return Response(
          503,
          body: jsonEncode({
            'error': 'too_many_connections',
            'message': connectionResult.reason,
            'current': connectionResult.currentConnections,
            'max': connectionResult.maxConnections,
          }),
          headers: {'Content-Type': 'application/json'},
        );
      }

      try {
        // 3. Валидировать запрос
        final validationResult = requestValidator.validate(request);

        if (!validationResult.valid) {
          return Response(
            validationResult.statusCode,
            body: jsonEncode({
              'error': 'validation_failed',
              'message': validationResult.reason,
            }),
            headers: {'Content-Type': 'application/json'},
          );
        }

        // 4. Обработать запрос
        final response = await handler(request);

        return response;
      } finally {
        // Всегда отключить соединение
        connectionLimiter.disconnect(connectionId);
      }
    };
  };
}

/// Получить IP адрес клиента
String _getClientIp(Request request) {
  final forwardedFor = request.headers['x-forwarded-for'];
  if (forwardedFor != null) {
    return forwardedFor.split(',').first.trim();
  }

  final realIp = request.headers['x-real-ip'];
  if (realIp != null) {
    return realIp;
  }

  final connectionInfo = request.context['shelf.io.connection_info'];
  if (connectionInfo != null) {
    try {
      return (connectionInfo as dynamic).remoteAddress.address as String;
    } catch (_) {
      // Ignore
    }
  }

  return 'unknown';
}

/// IP blacklist middleware (только проверка)
Middleware ipBlacklistMiddleware({
  required IpBlacklist blacklist,
}) {
  return (Handler handler) {
    return (Request request) async {
      final ip = _getClientIp(request);

      if (blacklist.isBlocked(ip)) {
        final entry = blacklist.getEntry(ip);
        return Response(
          403,
          body: jsonEncode({
            'error': 'ip_blocked',
            'message': 'Your IP has been blocked',
            'reason': entry?.reason,
            'expires_at': entry?.expiresAt,
          }),
          headers: {'Content-Type': 'application/json'},
        );
      }

      return handler(request);
    };
  };
}
