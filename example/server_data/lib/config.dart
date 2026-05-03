// lib/config.dart
//
// Configuration for Data Layer server

import 'dart:io';

/// Configuration for the isolated data layer server
final class DataLayerConfig {
  const DataLayerConfig({
    required this.port,
    required this.postgresHost,
    required this.postgresPort,
    required this.postgresDb,
    required this.postgresUser,
    required this.postgresPassword,
  });

  final int port;
  final String postgresHost;
  final int postgresPort;
  final String postgresDb;
  final String postgresUser;
  final String postgresPassword;

  /// Load configuration from environment variables
  factory DataLayerConfig.fromEnv() {
    return DataLayerConfig(
      port: int.parse(Platform.environment['DATA_SERVICE_PORT'] ?? '8090'),
      postgresHost: Platform.environment['POSTGRES_HOST'] ?? 'localhost',
      postgresPort: int.parse(Platform.environment['POSTGRES_PORT'] ?? '5432'),
      postgresDb: Platform.environment['POSTGRES_DB'] ?? 'aq_security',
      postgresUser: Platform.environment['POSTGRES_USER'] ?? 'aq_security_user',
      postgresPassword: Platform.environment['POSTGRES_PASSWORD'] ??
          (throw Exception('POSTGRES_PASSWORD is required')),
    );
  }

  /// PostgreSQL connection string
  String get postgresUrl =>
      'postgresql://$postgresUser:$postgresPassword@$postgresHost:$postgresPort/$postgresDb';

  @override
  String toString() => 'DataLayerConfig(port: $port, db: $postgresDb)';
}
