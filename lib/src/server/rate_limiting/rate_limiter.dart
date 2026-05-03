// pkgs/aq_security/lib/src/server/rate_limiting/rate_limiter.dart
//
// Server-only. Rate limiting implementation using token bucket algorithm.
// Защита от DoS атак и abuse.

import 'dart:async';

/// Rate limit configuration
final class RateLimitConfig {
  const RateLimitConfig({
    required this.maxRequests,
    required this.windowSeconds,
    this.burstSize,
  });

  /// Максимальное количество запросов в окне
  final int maxRequests;

  /// Размер окна в секундах
  final int windowSeconds;

  /// Burst size (если null, то = maxRequests)
  final int? burstSize;

  int get effectiveBurstSize => burstSize ?? maxRequests;

  /// Requests per second
  double get requestsPerSecond => maxRequests / windowSeconds;
}

/// Token bucket для rate limiting
final class TokenBucket {
  TokenBucket({
    required this.config,
    int? lastRefillTime,
    double? tokens,
  })  : _tokens = tokens ?? config.effectiveBurstSize.toDouble(),
        _lastRefillTime = lastRefillTime ?? _now();

  final RateLimitConfig config;
  double _tokens;
  int _lastRefillTime;

  /// Попытаться взять токен
  bool tryConsume({int tokens = 1}) {
    _refill();

    if (_tokens >= tokens) {
      _tokens -= tokens;
      return true;
    }

    return false;
  }

  /// Получить количество доступных токенов
  double get availableTokens {
    _refill();
    return _tokens;
  }

  /// Получить время до следующего токена (в секундах)
  double get timeToNextToken {
    _refill();

    if (_tokens >= 1) return 0;

    final tokensNeeded = 1 - _tokens;
    return tokensNeeded / config.requestsPerSecond;
  }

  /// Refill токенов на основе прошедшего времени
  void _refill() {
    final now = _now();
    final elapsed = now - _lastRefillTime;

    if (elapsed <= 0) return;

    // Добавить токены на основе прошедшего времени
    final tokensToAdd = elapsed * config.requestsPerSecond;
    _tokens = (_tokens + tokensToAdd).clamp(0, config.effectiveBurstSize.toDouble());
    _lastRefillTime = now;
  }

  static int _now() => DateTime.now().millisecondsSinceEpoch ~/ 1000;
}

/// Rate limiter с in-memory storage
final class RateLimiter {
  RateLimiter({
    required this.config,
    this.cleanupIntervalSeconds = 300, // 5 минут
  }) {
    _startCleanupTimer();
  }

  final RateLimitConfig config;
  final int cleanupIntervalSeconds;
  final Map<String, TokenBucket> _buckets = {};
  Timer? _cleanupTimer;

  /// Проверить rate limit для ключа
  RateLimitResult checkLimit(String key) {
    final bucket = _buckets.putIfAbsent(
      key,
      () => TokenBucket(config: config),
    );

    final allowed = bucket.tryConsume();

    return RateLimitResult(
      allowed: allowed,
      limit: config.maxRequests,
      remaining: bucket.availableTokens.floor(),
      resetAt: _now() + bucket.timeToNextToken.ceil(),
      retryAfter: allowed ? null : bucket.timeToNextToken.ceil(),
    );
  }

  /// Получить текущий статус для ключа
  RateLimitResult getStatus(String key) {
    final bucket = _buckets[key];

    if (bucket == null) {
      return RateLimitResult(
        allowed: true,
        limit: config.maxRequests,
        remaining: config.effectiveBurstSize,
        resetAt: _now() + config.windowSeconds,
        retryAfter: null,
      );
    }

    return RateLimitResult(
      allowed: bucket.availableTokens >= 1,
      limit: config.maxRequests,
      remaining: bucket.availableTokens.floor(),
      resetAt: _now() + bucket.timeToNextToken.ceil(),
      retryAfter: bucket.availableTokens >= 1 ? null : bucket.timeToNextToken.ceil(),
    );
  }

  /// Очистить bucket для ключа
  void clear(String key) {
    _buckets.remove(key);
  }

  /// Очистить все buckets
  void clearAll() {
    _buckets.clear();
  }

  /// Запустить cleanup timer
  void _startCleanupTimer() {
    _cleanupTimer?.cancel();
    _cleanupTimer = Timer.periodic(
      Duration(seconds: cleanupIntervalSeconds),
      (_) => _cleanup(),
    );
  }

  /// Cleanup старых buckets
  void _cleanup() {
    final now = _now();
    final keysToRemove = <String>[];

    for (final entry in _buckets.entries) {
      final bucket = entry.value;
      final timeSinceLastUse = now - bucket._lastRefillTime;

      // Удалить если не использовался > 2 * windowSeconds
      if (timeSinceLastUse > config.windowSeconds * 2) {
        keysToRemove.add(entry.key);
      }
    }

    for (final key in keysToRemove) {
      _buckets.remove(key);
    }
  }

  /// Dispose
  void dispose() {
    _cleanupTimer?.cancel();
    _buckets.clear();
  }

  static int _now() => DateTime.now().millisecondsSinceEpoch ~/ 1000;
}

/// Результат проверки rate limit
final class RateLimitResult {
  const RateLimitResult({
    required this.allowed,
    required this.limit,
    required this.remaining,
    required this.resetAt,
    this.retryAfter,
  });

  /// Разрешён ли запрос
  final bool allowed;

  /// Максимальное количество запросов
  final int limit;

  /// Оставшееся количество запросов
  final int remaining;

  /// Timestamp когда лимит сбросится
  final int resetAt;

  /// Через сколько секунд можно повторить (если !allowed)
  final int? retryAfter;

  /// Заголовки для HTTP response
  Map<String, String> get headers => {
        'X-RateLimit-Limit': limit.toString(),
        'X-RateLimit-Remaining': remaining.toString(),
        'X-RateLimit-Reset': resetAt.toString(),
        if (retryAfter != null) 'Retry-After': retryAfter.toString(),
      };
}
