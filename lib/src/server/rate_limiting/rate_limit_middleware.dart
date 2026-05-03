// pkgs/aq_security/lib/src/server/rate_limiting/rate_limit_middleware.dart
//
// Server-only. Shelf middleware для rate limiting.

import 'dart:convert';
import 'package:shelf/shelf.dart';
import 'rate_limiter.dart';
import '../monitoring/metrics.dart';

/// Стратегия извлечения ключа для rate limiting
enum RateLimitStrategy {
  /// По IP адресу
  byIp,

  /// По user ID из токена
  byUser,

  /// По IP + user ID
  byIpAndUser,

  /// По API key
  byApiKey,

  /// Global (один лимит на всех)
  global,
}

/// Middleware для rate limiting
Middleware rateLimitMiddleware({
  required RateLimiter limiter,
  RateLimitStrategy strategy = RateLimitStrategy.byIp,
  String? keyPrefix,
  SecurityMetrics? metrics,
}) {
  return (Handler handler) {
    return (Request request) async {
      // Извлечь ключ на основе стратегии
      final key = _extractKey(request, strategy, keyPrefix);

      // Проверить rate limit
      final result = limiter.checkLimit(key);

      // Record metrics
      if (metrics != null) {
        metrics.recordRateLimitHit(strategy: strategy.name);
        if (result.remaining != null) {
          metrics.setRateLimitRemaining(key, result.remaining!);
        }
      }

      // Если превышен лимит, вернуть 429
      if (!result.allowed) {
        // Record blocked request
        if (metrics != null) {
          metrics.recordRateLimitBlocked(strategy: strategy.name);
        }

        return Response(
          429,
          body: jsonEncode({
            'error': 'rate_limit_exceeded',
            'message': 'Too many requests. Please try again later.',
            'limit': result.limit,
            'reset_at': result.resetAt,
            'retry_after': result.retryAfter,
          }),
          headers: {
            'Content-Type': 'application/json',
            ...result.headers,
          },
        );
      }

      // Продолжить обработку запроса
      final response = await handler(request);

      // Добавить rate limit headers к response
      return response.change(headers: result.headers);
    };
  };
}

/// Извлечь ключ для rate limiting
String _extractKey(
  Request request,
  RateLimitStrategy strategy,
  String? keyPrefix,
) {
  final prefix = keyPrefix ?? 'rl';

  switch (strategy) {
    case RateLimitStrategy.byIp:
      final ip = _getClientIp(request);
      return '$prefix:ip:$ip';

    case RateLimitStrategy.byUser:
      final userId = _getUserId(request);
      if (userId == null) {
        // Fallback to IP если нет user ID
        final ip = _getClientIp(request);
        return '$prefix:ip:$ip';
      }
      return '$prefix:user:$userId';

    case RateLimitStrategy.byIpAndUser:
      final ip = _getClientIp(request);
      final userId = _getUserId(request);
      if (userId == null) {
        return '$prefix:ip:$ip';
      }
      return '$prefix:ip:$ip:user:$userId';

    case RateLimitStrategy.byApiKey:
      final apiKey = _getApiKey(request);
      if (apiKey == null) {
        // Fallback to IP
        final ip = _getClientIp(request);
        return '$prefix:ip:$ip';
      }
      return '$prefix:apikey:$apiKey';

    case RateLimitStrategy.global:
      return '$prefix:global';
  }
}

/// Получить IP адрес клиента
String _getClientIp(Request request) {
  // Проверить X-Forwarded-For (если за proxy)
  final forwardedFor = request.headers['x-forwarded-for'];
  if (forwardedFor != null) {
    // Взять первый IP из списка
    return forwardedFor.split(',').first.trim();
  }

  // Проверить X-Real-IP
  final realIp = request.headers['x-real-ip'];
  if (realIp != null) {
    return realIp;
  }

  // Fallback to connection IP
  final connectionInfo = request.context['shelf.io.connection_info'];
  if (connectionInfo != null) {
    try {
      // connectionInfo is HttpConnectionInfo
      return (connectionInfo as dynamic).remoteAddress.address as String;
    } catch (_) {
      // Ignore
    }
  }

  return 'unknown';
}

/// Получить user ID из токена
String? _getUserId(Request request) {
  final claims = request.context['claims'];
  if (claims == null) return null;

  // Предполагаем что claims это Map с 'sub' полем
  if (claims is Map<String, dynamic>) {
    return claims['sub'] as String?;
  }

  return null;
}

/// Получить API key из заголовка
String? _getApiKey(Request request) {
  final authHeader = request.headers['authorization'];
  if (authHeader == null) return null;

  // Формат: "Bearer <api_key>"
  if (authHeader.startsWith('Bearer ')) {
    return authHeader.substring(7);
  }

  return null;
}

/// Multiple rate limiters middleware
/// Применяет несколько rate limiters последовательно
Middleware multiRateLimitMiddleware({
  required List<({RateLimiter limiter, RateLimitStrategy strategy, String? keyPrefix})> limiters,
  SecurityMetrics? metrics,
}) {
  return (Handler handler) {
    return (Request request) async {
      final allHeaders = <String, String>{};

      // Проверить каждый limiter
      for (final config in limiters) {
        final key = _extractKey(request, config.strategy, config.keyPrefix);
        final result = config.limiter.checkLimit(key);

        // Record metrics
        if (metrics != null) {
          metrics.recordRateLimitHit(strategy: config.strategy.name);
          if (result.remaining != null) {
            metrics.setRateLimitRemaining(key, result.remaining!);
          }
        }

        // Собрать headers
        allHeaders.addAll(result.headers);

        // Если хотя бы один limiter блокирует, вернуть 429
        if (!result.allowed) {
          // Record blocked request
          if (metrics != null) {
            metrics.recordRateLimitBlocked(strategy: config.strategy.name);
          }

          return Response(
            429,
            body: jsonEncode({
              'error': 'rate_limit_exceeded',
              'message': 'Too many requests. Please try again later.',
              'limit': result.limit,
              'reset_at': result.resetAt,
              'retry_after': result.retryAfter,
            }),
            headers: {
              'Content-Type': 'application/json',
              ...allHeaders,
            },
          );
        }
      }

      // Все limiters пропустили, продолжить
      final response = await handler(request);
      return response.change(headers: allHeaders);
    };
  };
}
