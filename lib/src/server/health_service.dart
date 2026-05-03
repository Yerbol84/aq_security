// pkgs/aq_security/lib/src/server/health_service.dart
//
// Health check service для проверки зависимостей

/// Health check result
final class HealthCheckResult {
  const HealthCheckResult({
    required this.status,
    required this.checks,
    required this.timestamp,
  });

  final String status; // 'healthy' | 'degraded' | 'unhealthy'
  final Map<String, String> checks; // component -> status
  final String timestamp;

  Map<String, dynamic> toJson() => {
        'status': status,
        'checks': checks,
        'timestamp': timestamp,
      };
}

/// Health check service
final class HealthService {
  HealthService({
    this.databaseCheck,
    this.redisCheck,
  });

  /// Database connectivity check (optional)
  final Future<bool> Function()? databaseCheck;

  /// Redis connectivity check (optional)
  final Future<bool> Function()? redisCheck;

  /// Perform health check
  Future<HealthCheckResult> check() async {
    final checks = <String, String>{};
    var overallHealthy = true;

    // Check database
    if (databaseCheck != null) {
      try {
        final dbOk = await databaseCheck!();
        checks['database'] = dbOk ? 'ok' : 'failed';
        if (!dbOk) overallHealthy = false;
      } catch (e) {
        checks['database'] = 'error: $e';
        overallHealthy = false;
      }
    }

    // Check redis
    if (redisCheck != null) {
      try {
        final redisOk = await redisCheck!();
        checks['redis'] = redisOk ? 'ok' : 'failed';
        if (!redisOk) overallHealthy = false;
      } catch (e) {
        checks['redis'] = 'error: $e';
        overallHealthy = false;
      }
    }

    // If no checks configured, just return ok
    if (checks.isEmpty) {
      checks['app'] = 'ok';
    }

    final status = overallHealthy ? 'healthy' : 'unhealthy';
    final timestamp = DateTime.now().toUtc().toIso8601String();

    return HealthCheckResult(
      status: status,
      checks: checks,
      timestamp: timestamp,
    );
  }
}
