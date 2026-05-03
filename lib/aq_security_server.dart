// pkgs/aq_security/lib/aq_security_server.dart
//
// SERVER barrel — import this in server apps only.
// Exports everything from aq_security.dart PLUS server internals.

export 'aq_security.dart';

// Server internals
export 'src/shared/security_config.dart';
export 'src/server/aq_auth_server.dart';
export 'src/server/repositories/vault_security_repositories.dart';
export 'src/server/token_issuer.dart';
export 'src/server/session_service.dart';
export 'src/server/user_service.dart';
export 'src/server/api_key_service.dart';
export 'src/server/google_oauth_service.dart';
export 'src/server/github_oauth_service.dart';
export 'src/server/password_service.dart';
export 'src/server/email_verification_service.dart';
export 'src/server/magic_link_service.dart';
export 'src/server/token_revocation_service.dart';
export 'src/server/token_introspection_service.dart';
export 'src/server/resource_permission_service.dart';
export 'src/server/permission_inheritance_service.dart';
export 'src/server/policy_engine.dart';
export 'src/server/health_service.dart';
export 'src/server/rate_limiting/rate_limiter.dart';
export 'src/server/rate_limiting/rate_limit_middleware.dart';
export 'src/server/dos_protection/connection_limiter.dart';
export 'src/server/dos_protection/request_validator.dart';
export 'src/server/dos_protection/ip_blacklist.dart';
export 'src/server/dos_protection/dos_protection_middleware.dart';
export 'src/server/security_headers/security_headers.dart';
export 'src/server/security_headers/cors_config.dart';
export 'src/server/security_headers/security_middleware.dart';
export 'src/server/auth_router.dart';
export 'src/server/introspection_router.dart';
export 'src/server/middleware/auth_middleware.dart';
export 'src/server/middleware/scope_middleware.dart';

// OAuth
export 'src/server/oauth/csrf_store.dart';
export 'src/server/oauth/pkce_store.dart';

// RBAC Server
export 'src/server/rbac_router.dart';
export 'src/server/repositories/rbac_repositories.dart';

// Metrics & Monitoring
export 'src/server/metrics/metrics_collector.dart';
export 'src/server/metrics/metrics_aggregator.dart';
export 'src/server/monitoring/metrics.dart';
export 'src/server/monitoring/metrics_middleware.dart';
export 'src/server/monitoring/metrics_handler.dart';

// Logging & Tracing
export 'src/server/logging/structured_logger.dart';
export 'src/server/logging/log_context.dart';
export 'src/server/logging/context_logger.dart';
export 'src/server/logging/logging_middleware.dart';
export 'src/server/logging/security_logger.dart';

// Alerts & Security
export 'src/server/alerts/alert_generator.dart';
export 'src/server/alerts/alert_rules.dart';
