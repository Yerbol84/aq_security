# AqVaultSecurityProtocol

Реализация `IVaultSecurityProtocol` для интеграции `aq_security` с `dart_vault` Data Layer.

## Архитектура

```
┌─────────────────────────────────────────────────────────────┐
│                     dart_vault (Data Layer)                  │
│  ┌──────────────────────────────────────────────────────┐   │
│  │ PostgresVaultStorage / LocalVaultStorage             │   │
│  │                                                       │   │
│  │  read() / write() / delete()                         │   │
│  └──────────────────┬───────────────────────────────────┘   │
│                     │                                        │
│                     ▼                                        │
│  ┌──────────────────────────────────────────────────────┐   │
│  │      IVaultSecurityProtocol.instance                 │   │
│  │                                                       │   │
│  │  • extractClaims()                                   │   │
│  │  • canRead() / canWrite() / canDelete()              │   │
│  │  • checkRateLimit()                                  │   │
│  │  • validateData()                                    │   │
│  │  • encryptSensitiveFields()                          │   │
│  │  • logOperation()                                    │   │
│  └──────────────────┬───────────────────────────────────┘   │
└────────────────────┼────────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────────┐
│              AqVaultSecurityProtocol (aq_security)           │
│  ┌──────────────────────────────────────────────────────┐   │
│  │ IntrospectionClient                                  │   │
│  │  → POST /introspect (auth service)                   │   │
│  │  → Проверка прав через auth сервер                   │   │
│  └──────────────────────────────────────────────────────┘   │
│  ┌──────────────────────────────────────────────────────┐   │
│  │ FieldEncryptionService                               │   │
│  │  → AES-256-GCM шифрование                            │   │
│  │  → Карта шифрования из модели                        │   │
│  └──────────────────────────────────────────────────────┘   │
│  ┌──────────────────────────────────────────────────────┐   │
│  │ RateLimiter                                          │   │
│  │  → Token bucket algorithm                            │   │
│  │  → In-memory rate limiting                           │   │
│  └──────────────────────────────────────────────────────┘   │
│  ┌──────────────────────────────────────────────────────┐   │
│  │ RequestValidator                                     │   │
│  │  → SQL injection detection                           │   │
│  │  → XSS detection                                     │   │
│  │  → Data size validation                              │   │
│  └──────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
```

## Инициализация

### В production (Data Service)

```dart
import 'dart:io';
import 'package:aq_security/aq_security.dart';
import 'package:aq_schema/security/interfaces/clients_protocols/i_data_layer_as_clietn_secure_protocol.dart';

void main() async {
  // 1. Создать security protocol
  final protocol = AqVaultSecurityProtocol(
    introspectionEndpoint: Platform.environment['AUTH_INTROSPECTION_ENDPOINT']!,
    encryptionKey: Platform.environment['ENCRYPTION_KEY']!,
    
    // Опционально: rate limiting
    rateLimitConfig: const RateLimitConfig(
      maxRequests: 1000,
      windowSeconds: 60,
    ),
    
    // Опционально: карты шифрования
    encryptionConfigs: {
      'users': const EncryptionConfig(fields: ['password', 'apiKey']),
      'api_keys': const EncryptionConfig(fields: ['key', 'secret']),
    },
  );

  // 2. Зарегистрировать singleton
  IVaultSecurityProtocol.initialize(protocol);

  // 3. Запустить сервер
  // Теперь dart_vault автоматически использует security
}
```

### В тестах (Mock)

```dart
import 'package:aq_schema/security/security.dart';
import 'package:test/test.dart';

void main() {
  setUp(() {
    // Mock protocol для тестов
    IVaultSecurityProtocol.initialize(MockVaultSecurityProtocol());
  });

  tearDown(() {
    IVaultSecurityProtocol.reset();
  });

  test('admin can delete projects', () async {
    // Тесты с mock protocol
  });
}
```

### В development (без security)

```dart
import 'package:aq_schema/security/security.dart';

void main() async {
  // NoOp protocol — всё разрешено
  IVaultSecurityProtocol.initialize(NoOpVaultSecurityProtocol());
  
  // Запустить приложение
}
```

## Компоненты

### 1. IntrospectionClient

Проверяет права доступа через auth сервис:

```dart
final client = IntrospectionClient(
  introspectionEndpoint: 'http://localhost:8080/introspect',
);

final response = await client.introspect(
  token: 'eyJ...',
  resource: 'project',
  action: 'read',
  resourceId: 'project-1',
);

if (response.allowed) {
  // Доступ разрешён
}
```

### 2. FieldEncryptionService

Шифрует чувствительные поля с использованием AES-256-GCM:

```dart
final service = FieldEncryptionService(
  encryptionKey: 'secret-key-32-bytes-long-string',
);

// Шифрование
final encrypted = await service.encryptFields(
  data: {'email': 'user@example.com', 'password': 'secret'},
  config: EncryptionConfig(fields: ['password']),
);
// Результат: {'email': 'user@example.com', 'password': 'encrypted:...'}

// Расшифрование
final decrypted = await service.decryptFields(
  data: encrypted,
  config: EncryptionConfig(fields: ['password']),
);
// Результат: {'email': 'user@example.com', 'password': 'secret'}
```

**Важно:** Если `EncryptionConfig` не указан для коллекции, шифрование не применяется.

### 3. RateLimiter

Token bucket algorithm для защиты от DoS:

```dart
final limiter = RateLimiter(
  config: RateLimitConfig(
    maxRequests: 100,
    windowSeconds: 60,
  ),
);

final result = limiter.checkLimit('user:123');

if (result.allowed) {
  // Запрос разрешён
  print('Remaining: ${result.remaining}/${result.limit}');
} else {
  // Rate limit превышен
  print('Retry after: ${result.retryAfter} seconds');
}
```

### 4. RequestValidator

Валидация данных на SQL injection, XSS, размер:

```dart
final validator = RequestValidator(
  config: RequestValidationConfig(
    maxBodySize: 10 * 1024 * 1024, // 10 MB
  ),
);

final errors = await protocol.validateData(
  collection: 'projects',
  data: {'name': 'My Project'},
);

if (errors.isEmpty) {
  // Данные валидны
} else {
  // Ошибки валидации
  for (final error in errors) {
    print('${error.field}: ${error.message}');
  }
}
```

## Маппинг коллекций

Все коллекции должны быть явно замаплены на `ResourceType`:

```dart
'projects' → ResourceType.project
'graphs' → ResourceType.graph
'instructions' → ResourceType.instruction
'prompts' → ResourceType.prompt
'datasets' → ResourceType.dataset
'models' → ResourceType.model
'api_keys' → ResourceType.apiKey
'sessions' → ResourceType.session
```

**Неизвестная коллекция → `UnknownCollectionException`**

## Rate Limiting

По умолчанию:

- **Read**: 1000 req/min
- **Write**: 1000 req/min (можно настроить отдельно)
- **Delete**: 1000 req/min (можно настроить отдельно)

Ключ для rate limiting: `user:{userId}` или `ip:{ip}` для анонимных запросов.

## Шифрование

Карта шифрования задаётся при инициализации:

```dart
encryptionConfigs: {
  'users': EncryptionConfig(fields: ['password', 'apiKey', 'secret']),
  'api_keys': EncryptionConfig(fields: ['key', 'secret']),
}
```

Если карты нет для коллекции → шифрование не применяется.

## Audit Logging

**TODO:** Будет реализовано отдельно после обсуждения.

Пока метод `logOperation()` ничего не делает.

## Примеры

См. `example/vault_security_protocol_example.dart` для полного примера использования.

## Тестирование

```bash
cd pkgs/aq_security
flutter pub get
flutter test
```

## Зависимости

- `aq_schema` — модели и интерфейсы
- `crypto` — SHA-256 для ключей
- `pointycastle` — AES-256-GCM шифрование
- `http` — HTTP клиент для introspection
- `uuid` — генерация ID

## Лицензия

Proprietary — AQ Studio
