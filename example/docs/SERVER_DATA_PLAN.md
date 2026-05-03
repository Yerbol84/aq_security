# Server Data Layer — Детальный план

**Компонент**: Data Layer (Vault Server)  
**Приоритет**: Высокий  
**Оценка**: 3 часа  
**Статус**: Планирование

---

## Цель

Создать изолированный Vault server для хранения auth данных:
- Users, Sessions, Roles, Permissions
- API Keys, Tenants, Profiles
- Без проверки прав (изолирован инфраструктурно)
- Доступен только для Auth Service

---

## Структура

```
server_data/
├── bin/
│   └── main.dart               # Точка входа
├── lib/
│   ├── config.dart             # Конфигурация
│   ├── vault_registry.dart     # Регистрация доменов
│   └── server.dart             # HTTP сервер
├── Dockerfile                  # Контейнеризация
├── pubspec.yaml                # Зависимости
└── README.md                   # Документация
```

---

## bin/main.dart

```dart
import 'dart:io';
import 'package:server_data/config.dart';
import 'package:server_data/server.dart';

void main(List<String> args) async {
  // Загрузить конфигурацию
  final config = DataLayerConfig.fromEnv();
  
  print('🚀 Starting AQ Security Data Layer...');
  print('   Port: ${config.port}');
  print('   PostgreSQL: ${config.postgresHost}:${config.postgresPort}');
  print('   Database: ${config.postgresDb}');
  
  // Создать и запустить сервер
  final server = DataLayerServer(config);
  await server.start();
  
  print('✅ Data Layer running on http://localhost:${config.port}');
  print('   Health: http://localhost:${config.port}/health');
  
  // Graceful shutdown
  ProcessSignal.sigint.watch().listen((_) async {
    print('\n🛑 Shutting down...');
    await server.stop();
    exit(0);
  });
}
```

---

## lib/config.dart

```dart
import 'dart:io';

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
  
  factory DataLayerConfig.fromEnv() {
    return DataLayerConfig(
      port: int.parse(Platform.environment['DATA_SERVICE_PORT'] ?? '8090'),
      postgresHost: Platform.environment['POSTGRES_HOST'] ?? 'localhost',
      postgresPort: int.parse(Platform.environment['POSTGRES_PORT'] ?? '5432'),
      postgresDb: Platform.environment['POSTGRES_DB'] ?? 'aq_security',
      postgresUser: Platform.environment['POSTGRES_USER'] ?? 'aq_security_user',
      postgresPassword: Platform.environment['POSTGRES_PASSWORD'] ?? '',
    );
  }
  
  String get postgresUrl =>
      'postgresql://$postgresUser:$postgresPassword@$postgresHost:$postgresPort/$postgresDb';
}
```

---

## lib/vault_registry.dart

```dart
import 'package:dart_vault/dart_vault.dart';
import 'package:aq_schema/security/storable/security_storables.dart';
import 'package:aq_schema/security/storable/storable_rbac.dart';

/// Регистрация всех security доменов
void registerSecurityDomains(VaultRegistry registry) {
  // Users
  registry.registerDirect<StorableUser>(
    collection: SecurityCollections.users,
    fromMap: StorableUser.fromMap,
  );
  
  // Tenants
  registry.registerDirect<StorableTenant>(
    collection: SecurityCollections.tenants,
    fromMap: StorableTenant.fromMap,
  );
  
  // Profiles
  registry.registerDirect<StorableProfile>(
    collection: SecurityCollections.profiles,
    fromMap: StorableProfile.fromMap,
  );
  
  // Roles
  registry.registerDirect<StorableRole>(
    collection: SecurityCollections.roles,
    fromMap: StorableRole.fromMap,
  );
  
  // User Roles
  registry.registerDirect<StorableUserRole>(
    collection: SecurityCollections.userRoles,
    fromMap: StorableUserRole.fromMap,
  );
  
  // Sessions (LoggedStorable)
  registry.registerLogged<StorableSession>(
    collection: SecurityCollections.sessions,
    fromMap: StorableSession.fromMap,
  );
  
  // API Keys (LoggedStorable)
  registry.registerLogged<StorableApiKey>(
    collection: SecurityCollections.apiKeys,
    fromMap: StorableApiKey.fromMap,
  );
  
  // RBAC: Policies
  registry.registerDirect<StorableAqPolicy>(
    collection: AqPolicy.kCollection,
    fromMap: StorableAqPolicy.fromMap,
  );
  
  // RBAC: Access Logs (LoggedStorable)
  registry.registerLogged<StorableAqAccessLog>(
    collection: AqAccessLog.kCollection,
    fromMap: StorableAqAccessLog.fromMap,
  );
  
  // RBAC: Audit Trail (LoggedStorable)
  registry.registerLogged<StorableAqAuditTrail>(
    collection: AqAuditTrail.kCollection,
    fromMap: StorableAqAuditTrail.fromMap,
  );
  
  print('✅ Registered ${registry.domainCount} security domains');
}
```

---

## lib/server.dart

```dart
import 'dart:io';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as io;
import 'package:shelf_router/shelf_router.dart';
import 'package:dart_vault/dart_vault.dart';
import 'package:dart_vault/adapters/postgres_adapter.dart';
import 'config.dart';
import 'vault_registry.dart';

final class DataLayerServer {
  DataLayerServer(this.config);
  
  final DataLayerConfig config;
  HttpServer? _server;
  VaultStorage? _storage;
  
  Future<void> start() async {
    // Инициализация PostgreSQL storage
    _storage = await PostgresVaultStorage.connect(
      connectionString: config.postgresUrl,
    );
    
    // Регистрация доменов
    final registry = VaultRegistry(_storage!);
    registerSecurityDomains(registry);
    
    // Инициализация Vault
    await Vault.initialize(storage: _storage!);
    
    // Создание HTTP сервера
    final handler = _createHandler();
    _server = await io.serve(handler, InternetAddress.anyIPv4, config.port);
  }
  
  Handler _createHandler() {
    final router = Router();
    
    // Health check
    router.get('/health', (Request request) {
      return Response.ok('OK', headers: {'Content-Type': 'text/plain'});
    });
    
    // Vault API endpoints (автоматически через dart_vault)
    // POST /api/collections/{collection}/save
    // GET /api/collections/{collection}/find/{id}
    // POST /api/collections/{collection}/query
    // DELETE /api/collections/{collection}/delete/{id}
    
    // Middleware
    final pipeline = Pipeline()
        .addMiddleware(logRequests())
        .addMiddleware(_corsMiddleware())
        .addHandler(router);
    
    return pipeline;
  }
  
  Middleware _corsMiddleware() {
    return (Handler handler) {
      return (Request request) async {
        if (request.method == 'OPTIONS') {
          return Response.ok('', headers: {
            'Access-Control-Allow-Origin': '*',
            'Access-Control-Allow-Methods': 'GET, POST, PUT, DELETE, OPTIONS',
            'Access-Control-Allow-Headers': 'Content-Type, Authorization',
          });
        }
        
        final response = await handler(request);
        return response.change(headers: {
          'Access-Control-Allow-Origin': '*',
        });
      };
    };
  }
  
  Future<void> stop() async {
    await _server?.close(force: true);
    await _storage?.close();
  }
}
```

---

## Dockerfile

```dockerfile
FROM dart:3.3-sdk AS build

WORKDIR /app

# Копировать pubspec
COPY pubspec.yaml pubspec.lock ./

# Установить зависимости
RUN dart pub get

# Копировать исходники
COPY . .

# Скомпилировать
RUN dart compile exe bin/main.dart -o bin/server

# Runtime образ
FROM debian:bookworm-slim

# Установить runtime зависимости
RUN apt-get update && apt-get install -y \
    ca-certificates \
    curl \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Копировать скомпилированный бинарник
COPY --from=build /app/bin/server /app/bin/server

# Expose порт
EXPOSE 8090

# Health check
HEALTHCHECK --interval=10s --timeout=5s --retries=5 \
  CMD curl -f http://localhost:8090/health || exit 1

# Запуск
CMD ["/app/bin/server"]
```

---

## pubspec.yaml

```yaml
name: server_data
description: AQ Security Data Layer (Vault Server)
version: 1.0.0

environment:
  sdk: ^3.3.0

dependencies:
  shelf: ^1.4.0
  shelf_router: ^1.1.0
  dart_vault: 
    path: ../../../../dart_vault_package
  aq_schema:
    path: ../../../aq_schema

dev_dependencies:
  lints: ^3.0.0
```

---

## README.md

```markdown
# AQ Security Data Layer

Изолированный Vault server для хранения auth данных.

## Особенности

- **Изолирован инфраструктурно**: Доступен только Auth Service через Docker network
- **Без проверки прав**: Не проверяет токены (нет другого слоя безопасности)
- **PostgreSQL**: Хранение всех security данных
- **Автоматические миграции**: Через dart_vault

## Запуск локально

```bash
# Установить зависимости
dart pub get

# Настроить переменные окружения
export DATA_SERVICE_PORT=8090
export POSTGRES_HOST=localhost
export POSTGRES_PORT=5432
export POSTGRES_DB=aq_security
export POSTGRES_USER=aq_security_user
export POSTGRES_PASSWORD=secure_password

# Запустить
dart run bin/main.dart
```

## Запуск в Docker

```bash
# Собрать образ
docker build -t aq_security_data .

# Запустить
docker run -p 8090:8090 \
  -e POSTGRES_HOST=postgres \
  -e POSTGRES_PASSWORD=secure_password \
  aq_security_data
```

## Endpoints

- Health: `GET /health`
- Vault API: автоматически через dart_vault

## Зарегистрированные домены

- `security_users` (DirectStorable)
- `security_tenants` (DirectStorable)
- `security_profiles` (DirectStorable)
- `security_roles` (DirectStorable)
- `security_user_roles` (DirectStorable)
- `security_sessions` (LoggedStorable)
- `security_api_keys` (LoggedStorable)
- `rbac_policies` (DirectStorable)
- `rbac_access_logs` (LoggedStorable)
- `rbac_audit_trail` (LoggedStorable)
```

---

## Задачи реализации

### Задача 2.1: Создать структуру проекта
**Оценка**: 15 минут
- Создать папки bin/, lib/
- Создать pubspec.yaml
- Установить зависимости

### Задача 2.2: Реализовать config.dart
**Оценка**: 20 минут
- DataLayerConfig класс
- Чтение из environment
- Валидация

### Задача 2.3: Реализовать vault_registry.dart
**Оценка**: 30 минут
- Регистрация всех security доменов
- DirectStorable регистрации
- LoggedStorable регистрации

### Задача 2.4: Реализовать server.dart
**Оценка**: 45 минут
- HTTP сервер на shelf
- Health endpoint
- CORS middleware
- Graceful shutdown

### Задача 2.5: Реализовать main.dart
**Оценка**: 15 минут
- Инициализация
- Запуск сервера
- Signal handling

### Задача 2.6: Создать Dockerfile
**Оценка**: 20 минут
- Multi-stage build
- Runtime образ
- Healthcheck

### Задача 2.7: Создать README.md
**Оценка**: 15 минут
- Инструкции по запуску
- Описание endpoints
- Примеры

### Задача 2.8: Тестирование
**Оценка**: 20 минут
- Запустить локально
- Проверить подключение к PostgreSQL
- Проверить health endpoint
- Проверить регистрацию доменов

---

## Acceptance Criteria

- ✅ Сервер запускается на порту 8090
- ✅ Подключается к PostgreSQL
- ✅ Регистрирует все security домены
- ✅ Health endpoint возвращает 200
- ✅ Dockerfile собирается без ошибок
- ✅ Образ запускается в Docker
- ✅ README содержит все инструкции

---

## Зависимости

**Блокирует**:
- Server Auth реализацию

**Зависит от**:
- Docker Stack (PostgreSQL)

---

## Статус

- [ ] Задача 2.1: Структура проекта
- [ ] Задача 2.2: config.dart
- [ ] Задача 2.3: vault_registry.dart
- [ ] Задача 2.4: server.dart
- [ ] Задача 2.5: main.dart
- [ ] Задача 2.6: Dockerfile
- [ ] Задача 2.7: README.md
- [ ] Задача 2.8: Тестирование
