// pkgs/aq_security/lib/aq_security_server.dart
//
// SERVER barrel — бизнес-логика security layer без транспортного слоя.
//
// Shelf/HTTP middleware НЕ экспортируются отсюда.
// Приложение подключает shelf самостоятельно и инжектирует его в сервисы.

export 'aq_security.dart';

// Shared config
export 'src/shared/security_config.dart';

// Core server services (pure Dart, no shelf)
export 'src/server/token_issuer.dart';
export 'src/server/session_service.dart';
export 'src/server/user_service.dart';
export 'src/server/api_key_service.dart';
export 'src/server/password_service.dart';
export 'src/server/email_verification_service.dart';
export 'src/server/magic_link_service.dart';
export 'src/server/token_revocation_service.dart';
export 'src/server/token_introspection_service.dart';
export 'src/server/resource_permission_service.dart';
export 'src/server/permission_inheritance_service.dart';
export 'src/server/policy_engine.dart';
export 'src/server/health_service.dart';
export 'src/server/google_oauth_service.dart';
export 'src/server/github_oauth_service.dart';

// Rate limiting (pure Dart — no shelf)
export 'src/server/rate_limiting/rate_limiter.dart';

// DoS protection (pure Dart — no shelf)
export 'src/server/dos_protection/connection_limiter.dart';
export 'src/server/dos_protection/ip_blacklist.dart';

// Security headers config (pure Dart — no shelf)
export 'src/server/security_headers/security_headers.dart';
export 'src/server/security_headers/cors_config.dart';

// OAuth stores (pure Dart — no shelf)
export 'src/server/oauth/csrf_store.dart';
export 'src/server/oauth/pkce_store.dart';

// RBAC
export 'src/server/repositories/rbac_repositories.dart';

// Metrics & Monitoring (pure Dart — no shelf)
export 'src/server/metrics/metrics_collector.dart';
export 'src/server/metrics/metrics_aggregator.dart';
export 'src/server/monitoring/metrics.dart';

// Logging (pure Dart — no shelf)
export 'src/server/logging/structured_logger.dart';
export 'src/server/logging/log_context.dart';
export 'src/server/logging/context_logger.dart';
export 'src/server/logging/security_logger.dart';

// Alerts
export 'src/server/alerts/alert_generator.dart';
export 'src/server/alerts/alert_rules.dart';

// Testing / In-memory implementations
export 'src/testing/in_memory_repositories.dart';
export 'src/testing/in_memory_vault_security_protocol.dart';
