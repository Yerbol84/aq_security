# Интеграция AqVaultSecurityProtocol с Data Service

## Быстрый старт

### 1. В Data Service (server_apps/aq_studio_data_service)

```dart
// server_apps/aq_studio_data_service/bin/server.dart

import 'dart:io';
import 'package:aq_security/aq_security.dart';
import 'package:aq_schema/security/interfaces/clients_protocols/i_data_layer_as_clietn_secure_protocol.dart';

void main() async {
  // 1. Инициализировать security protocol
  final securityProtocol = AqVaultSecurityProtocol(
    introspectionEndpoint: Platform.environment['AUTH_INTROSPECTION_ENDPOINT'] ??
        'http://localhost:8080/introspect',
    encryptionKey: Platform.environment['ENCRYPTION_KEY'] ??
        'default-encryption-key-32-chars-long',
    
    // Карты шифрования для коллекций
    encryptionConfigs: {
      'users': const EncryptionConfig(fields: ['password', 'apiKey']),
      'api_keys': const EncryptionConfig(fields: ['key', 'secret']),
    },
  );

  // 2. Зарегистрировать singleton
  IVaultSecurityProtocol.initialize(securityProtocol);

  // 3. Запустить сервер
  // dart_vault теперь автоматически использует security
  final server = await createServer();
  await server.listen();
}
```

### 2. Переменные окружения

Добавить в `.env`:

```bash
# Auth service endpoint для introspection
AUTH_INTROSPECTION_ENDPOINT=http://localhost:8080/introspect

# Ключ шифрования (минимум 32 символа)
ENCRYPTION_KEY=your-secret-encryption-key-32-chars-long-string-here
```

### 3. Docker Compose

Обновить `deploys/aq_studio_dl_stack/docker-compose.yml`:

```yaml
services:
  aq_studio_data_service:
    environment:
      - AUTH_INTROSPECTION_ENDPOINT=http://aq_auth_service:8080/introspect
      - ENCRYPTION_KEY=${ENCRYPTION_KEY}
    depends_on:
      - aq_auth_service
```

## Как это работает

### Автоматическая проверка прав

Когда dart_vault выполняет операцию:

```dart
// В PostgresVaultStorage.read()
final protocol = IVaultSecurityProtocol.instance;
if (protocol != null) {
  // 1. Извлечь claims из headers
  final claims = await protocol.extractClaims(headers);
  
  // 2. Проверить права
  final decision = await protocol.canRead(
    claims: claims,
    collection: collection,
    entityId: id,
  );
  
  // 3. Обработать решение
  if (decision.allowed) {
    // Выполнить операцию
  } else {
    throw SecurityException(decision.reason ?? 'Access denied');
  }
}
```

### Автоматическое шифрование

```dart
// В PostgresVaultStorage.write()
final protocol = IVaultSecurityProtocol.instance;
if (protocol != null) {
  // Зашифровать чувствительные поля
  final encrypted = await protocol.encryptSensitiveFields(
    claims: claims,
    collection: collection,
    data: data,
  );
  
  // Сохранить зашифрованные данные
  await db.insert(collection, encrypted);
}
```

## Маппинг коллекций

Все коллекции должны быть известны:

| Коллекция | ResourceType |
|-----------|--------------|
| `projects`, `aq_studio_projects` | `ResourceType.project` |
| `graphs`, `workflow_graphs` | `ResourceType.graph` |
| `instructions`, `instruction_graphs` | `ResourceType.instruction` |
| `prompts`, `prompt_graphs` | `ResourceType.prompt` |
| `datasets` | `ResourceType.dataset` |
| `models` | `ResourceType.model` |
| `api_keys` | `ResourceType.apiKey` |
| `sessions` | `ResourceType.session` |

**Неизвестная коллекция → `UnknownCollectionException`**

## Тестирование

### Unit тесты

```dart
import 'package:aq_security/aq_security.dart';
import 'package:test/test.dart';

void main() {
  test('encrypt and decrypt fields', () async {
    final service = FieldEncryptionService(
      encryptionKey: 'test-key-32-chars-long-string-here',
    );
    
    final encrypted = await service.encryptFields(
      data: {'password': 'secret'},
      config: EncryptionConfig(fields: ['password']),
    );
    
    expect(encrypted['password'], startsWith('encrypted:'));
    
    final decrypted = await service.decryptFields(
      data: encrypted,
      config: EncryptionConfig(fields: ['password']),
    );
    
    expect(decrypted['password'], equals('secret'));
  });
}
```

### Integration тесты

```dart
void main() {
  setUp(() {
    // Инициализировать protocol для тестов
    final protocol = AqVaultSecurityProtocol(
      introspectionEndpoint: 'http://localhost:8080/introspect',
      encryptionKey: 'test-key-32-chars-long-string-here',
    );
    IVaultSecurityProtocol.initialize(protocol);
  });
  
  tearDown(() {
    IVaultSecurityProtocol.reset();
  });
  
  test('data service respects security', () async {
    // Тесты с реальным protocol
  });
}
```

## Troubleshooting

### 1. UnknownCollectionException

**Проблема:** `Unknown collection: my_collection`

**Решение:** Добавить маппинг в `_mapCollectionToResourceType()`:

```dart
case 'my_collection':
  return ResourceType.project; // или другой тип
```

### 2. IntrospectionException

**Проблема:** `Introspection failed: Connection refused`

**Решение:** Проверить, что auth service запущен и доступен:

```bash
curl http://localhost:8080/health
```

### 3. EncryptionException

**Проблема:** `Encryption key must be at least 32 characters`

**Решение:** Использовать ключ минимум 32 символа:

```bash
export ENCRYPTION_KEY="your-secret-key-must-be-32-chars-long-at-least"
```

## Следующие шаги

1. ✅ Реализован `AqVaultSecurityProtocol`
2. ✅ Реализован `FieldEncryptionService`
3. ✅ Интеграция с `IntrospectionClient`
4. ✅ Rate limiting через `RateLimiter`
5. ✅ Валидация через `RequestValidator`
6. ⏳ Audit logging (TODO — обсудить отдельно)
7. ⏳ Интеграция в `server_apps/aq_studio_data_service`
8. ⏳ Тесты для `AqVaultSecurityProtocol`

## Вопросы?

См. `VAULT_SECURITY_PROTOCOL.md` для полной документации.
