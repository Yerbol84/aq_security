// pkgs/aq_security/lib/aq_security.dart
//
// CLIENT barrel — safe for all nodes (Flutter, worker, Dart CLI).
// Does NOT export server internals.

export 'package:aq_schema/security/security.dart';

// Client
export 'src/client/aq_security_client.dart';
export 'src/client/introspection_client.dart';
export 'src/client/field_encryption_service.dart';
export 'src/client/aq_vault_security_protocol.dart';

// Shared config (client-safe portion)
export 'src/shared/security_config.dart' show SecurityClientConfig;
export 'src/server/repositories/vault_security_repositories.dart';

// RBAC
export 'src/rbac/rbac.dart';
