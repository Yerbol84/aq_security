// lib/server.dart
//
// HTTP server for the isolated data layer

import 'dart:io';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as io;
import 'package:shelf_router/shelf_router.dart';
import 'package:dart_vault/dart_vault.dart';
import 'package:dart_vault/adapters/postgres_adapter.dart';
import 'config.dart';
import 'vault_registry.dart';

/// Isolated data layer server
///
/// This server provides storage for auth service data.
/// It is isolated from the outside world and only accessible
/// by the auth service through Docker network.
///
/// Security model:
/// - No authentication (protected by network isolation)
/// - No authorization (auth service is trusted)
/// - All requests are logged for audit
final class DataLayerServer {
  DataLayerServer(this.config);

  final DataLayerConfig config;
  HttpServer? _server;
  VaultStorage? _storage;

  /// Start the server
  Future<void> start() async {
    print('🔌 Connecting to PostgreSQL...');
    print('   URL: ${config.postgresHost}:${config.postgresPort}/${config.postgresDb}');

    // Initialize PostgreSQL storage
    _storage = await PostgresVaultStorage.connect(
      connectionString: config.postgresUrl,
    );
    print('✅ Connected to PostgreSQL');

    // Register security domains
    final registry = VaultRegistry(_storage!);
    registerSecurityDomains(registry);

    // Initialize Vault
    print('🔧 Initializing Vault...');
    await Vault.initialize(storage: _storage!);
    print('✅ Vault initialized');

    // Create HTTP server
    print('🚀 Starting HTTP server...');
    final handler = _createHandler();
    _server = await io.serve(handler, InternetAddress.anyIPv4, config.port);
    print('✅ HTTP server started');
  }

  /// Create request handler
  Handler _createHandler() {
    final router = Router();

    // Health check endpoint
    router.get('/health', (Request request) {
      return Response.ok(
        'OK',
        headers: {'Content-Type': 'text/plain'},
      );
    });

    // Info endpoint (for debugging)
    router.get('/info', (Request request) {
      return Response.ok(
        '''
Data Layer Server
-----------------
Collections: ${SecurityCollections.all.join(', ')}
Storage: PostgreSQL
Status: Running
        ''',
        headers: {'Content-Type': 'text/plain'},
      );
    });

    // Vault API endpoints are automatically provided by dart_vault:
    // - POST /api/collections/{collection}/save
    // - GET /api/collections/{collection}/find/{id}
    // - POST /api/collections/{collection}/query
    // - DELETE /api/collections/{collection}/delete/{id}
    // - GET /api/collections/{collection}/history/{id} (for LoggedStorable)

    // Middleware pipeline
    final pipeline = Pipeline()
        .addMiddleware(logRequests())
        .addMiddleware(_corsMiddleware())
        .addMiddleware(_securityHeadersMiddleware())
        .addHandler(router);

    return pipeline;
  }

  /// CORS middleware
  ///
  /// Allow all origins since this is an internal service
  /// protected by Docker network isolation
  Middleware _corsMiddleware() {
    return (Handler handler) {
      return (Request request) async {
        // Handle preflight
        if (request.method == 'OPTIONS') {
          return Response.ok('', headers: {
            'Access-Control-Allow-Origin': '*',
            'Access-Control-Allow-Methods': 'GET, POST, PUT, DELETE, OPTIONS',
            'Access-Control-Allow-Headers': 'Content-Type, Authorization',
            'Access-Control-Max-Age': '86400',
          });
        }

        final response = await handler(request);
        return response.change(headers: {
          'Access-Control-Allow-Origin': '*',
        });
      };
    };
  }

  /// Security headers middleware
  Middleware _securityHeadersMiddleware() {
    return createMiddleware(
      responseHandler: (Response response) {
        return response.change(headers: {
          'X-Content-Type-Options': 'nosniff',
          'X-Frame-Options': 'DENY',
          'X-XSS-Protection': '1; mode=block',
        });
      },
    );
  }

  /// Stop the server
  Future<void> stop() async {
    print('🛑 Stopping server...');
    await _server?.close(force: true);
    await _storage?.close();
    print('✅ Server stopped');
  }
}
