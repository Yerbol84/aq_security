// pkgs/aq_security/example/vault_security_protocol_example.dart
//
// Пример использования AqVaultSecurityProtocol с dart_vault.

import 'dart:io';
import 'package:aq_security/aq_security.dart';
import 'package:aq_schema/security/interfaces/clients_protocols/i_data_layer_as_clietn_secure_protocol.dart';
import 'package:aq_security/src/server/rate_limiting/rate_limiter.dart';

void main() async {
  // ══════════════════════════════════════════════════════════════════════════
  // 1. Инициализация Security Protocol
  // ══════════════════════════════════════════════════════════════════════════

  final protocol = AqVaultSecurityProtocol(
    // Endpoint для проверки токенов
    introspectionEndpoint:
        Platform.environment['AUTH_INTROSPECTION_ENDPOINT'] ??
            'http://localhost:8080/introspect',

    // Ключ шифрования (минимум 32 символа)
    encryptionKey: Platform.environment['ENCRYPTION_KEY'] ??
        'default-encryption-key-32-chars-long-string-here',

    // Опционально: конфигурация rate limiting
    rateLimitConfig: const RateLimitConfig(
      maxRequests: 1000, // 1000 запросов
      windowSeconds: 60, // за 60 секунд
      burstSize: 100, // burst до 100 запросов
    ),

    // Опционально: карты шифрования для коллекций
    encryptionConfigs: {
      'users': const EncryptionConfig(
        fields: ['password', 'apiKey', 'secret'],
      ),
      'api_keys': const EncryptionConfig(
        fields: ['key', 'secret'],
      ),
    },
  );

  // ══════════════════════════════════════════════════════════════════════════
  // 2. Регистрация singleton
  // ══════════════════════════════════════════════════════════════════════════

  IVaultSecurityProtocol.initialize(protocol);

  print('✓ Security protocol initialized');

  // ══════════════════════════════════════════════════════════════════════════
  // 3. Использование в dart_vault
  // ══════════════════════════════════════════════════════════════════════════

  // Теперь dart_vault автоматически использует security protocol:
  //
  // final storage = PostgresVaultStorage(
  //   pool: pool,
  //   tenantId: 'tenant-1',
  //   headers: request.headers, // HTTP headers с токеном
  // );
  //
  // await storage.read('projects', 'project-1'); // Проверит права автоматически

  // ══════════════════════════════════════════════════════════════════════════
  // 4. Пример прямого использования
  // ══════════════════════════════════════════════════════════════════════════

  // Извлечь claims из headers
  final claims = await protocol.extractClaims({
    'Authorization': 'Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...',
  });

  if (claims != null) {
    print('✓ Claims extracted: ${claims.sub}');

    // Проверить права на чтение
    final readDecision = await protocol.canRead(
      claims: claims,
      collection: 'projects',
      entityId: 'project-1',
    );

    if (readDecision.allowed) {
      print('✓ Read access allowed');
    } else {
      print('✗ Read access denied: ${readDecision.reason}');
    }

    // Проверить rate limit
    final rateLimitOk = await protocol.checkRateLimit(
      claims: claims,
      operation: 'read',
    );

    if (rateLimitOk) {
      print('✓ Rate limit OK');
    } else {
      print('✗ Rate limit exceeded');
    }

    // Валидация данных
    final validationErrors = await protocol.validateData(
      collection: 'projects',
      data: {
        'name': 'My Project',
        'description': 'A safe description',
      },
    );

    if (validationErrors.isEmpty) {
      print('✓ Data validation passed');
    } else {
      print('✗ Data validation failed:');
      for (final error in validationErrors) {
        print('  - ${error.field}: ${error.message}');
      }
    }

    // Шифрование чувствительных полей
    final encrypted = await protocol.encryptSensitiveFields(
      claims: claims,
      collection: 'users',
      data: {
        'email': 'user@example.com',
        'password': 'secret123',
      },
    );

    print('✓ Encrypted data: $encrypted');
    // Результат: {'email': 'user@example.com', 'password': 'encrypted:...'}

    // Расшифрование
    final decrypted = await protocol.decryptSensitiveFields(
      claims: claims,
      collection: 'users',
      data: encrypted,
    );

    print('✓ Decrypted data: $decrypted');
    // Результат: {'email': 'user@example.com', 'password': 'secret123'}
  }

  // ══════════════════════════════════════════════════════════════════════════
  // 5. Обработка неизвестных коллекций
  // ══════════════════════════════════════════════════════════════════════════

  try {
    await protocol.canRead(
      claims: claims,
      collection: 'unknown_collection',
    );
  } on UnknownCollectionException catch (e) {
    print('✗ Unknown collection: $e');
  }

  print('\n✓ Example completed');
}
