# Последовательность реализации системы безопасности

**Дата:** 2026-04-07
**Цель:** Готовый продукт, который можно поднять и использовать

---

## 🎯 Конечная цель

Поднять стек командой `docker-compose up` и получить:
- ✅ PostgreSQL с auth данными
- ✅ AQ Auth Data Service (data layer для auth)
- ✅ AQ Auth Service (JWT, OAuth2, sessions)
- ✅ Возможность подключиться из Flutter/Worker через `AQSecurityClient.init()`

---

## 📐 Правильная архитектура

```
┌─────────────────────────────────────────┐
│   Flutter/Dart Client                   │
│   AQSecurityClient.init(endpoint)       │
└──────────────┬──────────────────────────┘
               │ HTTPS
               ↓
┌─────────────────────────────────────────┐
│   AQ Auth Service (порт 8080)           │
│   • JWT issuer                          │
│   • OAuth2                              │
│   • Session management                  │
│   • НЕ ЗНАЕТ о PostgreSQL!              │
│   • Использует dart_vault как клиент    │
└──────────────┬──────────────────────────┘
               │ RemoteVaultStorage (HTTP)
               ↓
┌─────────────────────────────────────────┐
│   AQ Auth Data Service (порт 8090)      │
│   • VaultRegistry                       │
│   • PostgresVaultStorage                │
│   • Security domains                    │
└──────────────┬──────────────────────────┘
               │ SQL
               ↓
┌─────────────────────────────────────────┐
│   PostgreSQL (порт 5433)                │
│   • security_users                      │
│   • security_sessions + _log            │
│   • security_roles                      │
│   • security_api_keys + _log            │
└─────────────────────────────────────────┘
```

**Ключевой принцип:** Auth Service — это КЛИЕНТ для data layer. Он не знает о БД.

---

## 📋 Последовательность реализации

### Шаг 1: Проверить текущее состояние aq_auth_data_service

**Цель:** Понять что уже есть, что нужно добавить.

**Действия:**
1. Прочитать `server_apps/aq_auth_data_service/bin/main.dart`
2. Проверить есть ли регистрация security доменов
3. Проверить подключение к PostgreSQL
4. Проверить есть ли Dockerfile

**Ожидаемый результат:** Понимание текущего состояния.

---

### Шаг 2: Реализовать aq_auth_data_service

**Цель:** Отдельный data service для auth данных.

**Файл:** `server_apps/aq_auth_data_service/bin/main.dart`

```dart
import 'dart:io';
import 'package:postgres/postgres.dart';
import 'package:dart_vault/server.dart';
import 'package:aq_schema/security/security.dart';
import 'package:shelf/shelf_io.dart' as io;

void main() async {
  print('[AQAuthDataService] Starting...');

  // 1. Подключение к PostgreSQL
  final connection = await Connection.open(
    Endpoint(
      host: Platform.environment['PG_HOST'] ?? 'localhost',
      port: int.parse(Platform.environment['PG_PORT'] ?? '5432'),
      database: Platform.environment['PG_DB'] ?? 'aq_auth',
      username: Platform.environment['PG_USER'] ?? 'aq',
      password: Platform.environment['PG_PASSWORD'] ?? 'aq_secret',
    ),
  );

  print('[AQAuthDataService] PostgreSQL connected');

  // 2. Создать VaultRegistry
  final registry = VaultRegistry(
    storageFactory: (tenantId) => PostgresVaultStorage(
      connection: connection,
      tenantId: tenantId,
    ),
    deployer: PostgresSchemaDeployer(pool: connection),
  );

  // 3. Зарегистрировать security домены
  for (final domain in AqSecurityDomains.all) {
    registry.register(DomainRegistration(
      collection: domain.collection,
      mode: domain.mode,
      fromMap: domain.fromMap,
      indexes: domain.indexes,
    ));
  }

  print('[AQAuthDataService] Registered ${AqSecurityDomains.all.length} domains');

  // 4. Deploy схемы (создаст таблицы автоматически)
  await registry.deploy();
  print('[AQAuthDataService] Schema deployed');

  // 5. Запустить HTTP сервер
  final handler = createVaultHandler(registry);
  final port = int.parse(Platform.environment['PORT'] ?? '8090');
  await io.serve(handler, '0.0.0.0', port);

  print('[AQAuthDataService] ✅ Running on :$port');
}
```

**Создать Dockerfile:**
```dockerfile
FROM dart:stable AS build
WORKDIR /app
COPY pubspec.yaml ./
COPY pkgs/ ./pkgs/
RUN cd pkgs/aq_schema && dart pub get
RUN cd pkgs/dart_vault_package && dart pub get
COPY server_apps/aq_auth_data_service/ ./server_apps/aq_auth_data_service/
WORKDIR /app/server_apps/aq_auth_data_service
RUN dart pub get
RUN dart compile exe bin/main.dart -o /app/server

FROM scratch
COPY --from=build /runtime/ /
COPY --from=build /app/server /app/server
EXPOSE 8090
ENTRYPOINT ["/app/server"]
```

**Результат:** Data service готов принимать запросы на порту 8090.

---

### Шаг 3: Проверить aq_auth_service

**Цель:** Убедиться что auth service правильно использует dart_vault.

**Проверить файл:** `server_apps/aq_auth_service/bin/main.dart`

**Должно быть:**
```dart
// ✅ Правильно — использует RemoteVaultStorage
final storage = RemoteVaultStorage(
  endpoint: config.authDataServiceUrl,  // http://auth_data_service:8090
  tenantId: 'auth',
);

await storage.connect();

// ✅ Правильно — получает репозитории через Vault
final repos = vaultSecurityRepos(storage);

// ✅ Правильно — передает репозитории в AQAuthServer
final server = AQAuthServer(
  config: SecurityConfig(...),
  repos: repos,
  googleConfig: GoogleOAuthConfig(...),
);
```

**Если что-то не так — исправить.**

**Создать Dockerfile (если нет):**
```dockerfile
FROM dart:stable AS build
WORKDIR /app
COPY pubspec.yaml ./
COPY pkgs/ ./pkgs/
RUN cd pkgs/aq_schema && dart pub get
RUN cd pkgs/aq_security && dart pub get
RUN cd pkgs/dart_vault_package && dart pub get
COPY server_apps/aq_auth_service/ ./server_apps/aq_auth_service/
WORKDIR /app/server_apps/aq_auth_service
RUN dart pub get
RUN dart compile exe bin/main.dart -o /app/server

FROM scratch
COPY --from=build /runtime/ /
COPY --from=build /app/server /app/server
EXPOSE 8080
ENTRYPOINT ["/app/server"]
```

**Результат:** Auth service готов работать как клиент data layer.

---

### Шаг 4: Обновить Docker Compose stack

**Файл:** `deploys/aq_auth_stack/docker-compose.yml`

```yaml
version: '3.8'

services:
  postgres:
    image: postgres:14-alpine
    container_name: aq_auth_postgres
    restart: unless-stopped
    environment:
      POSTGRES_DB: ${POSTGRES_DB:-aq_auth}
      POSTGRES_USER: ${POSTGRES_USER:-aq}
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD:-aq_secret}
    ports:
      - "${POSTGRES_PORT:-5433}:5432"
    volumes:
      - ./aq_auth_data:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U ${POSTGRES_USER:-aq}"]
      interval: 10s
      timeout: 5s
      retries: 5
    networks:
      - aq_auth_network

  auth_data_service:
    build:
      context: ../..
      dockerfile: server_apps/aq_auth_data_service/Dockerfile
    container_name: aq_auth_data_service
    restart: unless-stopped
    depends_on:
      postgres:
        condition: service_healthy
    environment:
      PG_HOST: postgres
      PG_PORT: 5432
      PG_DB: ${POSTGRES_DB:-aq_auth}
      PG_USER: ${POSTGRES_USER:-aq}
      PG_PASSWORD: ${POSTGRES_PASSWORD:-aq_secret}
      PORT: 8090
    ports:
      - "8090:8090"
    networks:
      - aq_auth_network
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8090/health"]
      interval: 10s
      timeout: 5s
      retries: 5

  auth_service:
    build:
      context: ../..
      dockerfile: server_apps/aq_auth_service/Dockerfile
    container_name: aq_auth_service
    restart: unless-stopped
    depends_on:
      auth_data_service:
        condition: service_healthy
    environment:
      AUTH_DATA_SERVICE_URL: http://auth_data_service:8090
      AUTH_ENDPOINT: ${AUTH_ENDPOINT:-http://localhost:8080}
      JWT_SECRET: ${JWT_SECRET:-change-me-in-production}
      GOOGLE_CLIENT_ID: ${GOOGLE_CLIENT_ID}
      GOOGLE_CLIENT_SECRET: ${GOOGLE_CLIENT_SECRET}
      PORT: 8080
    ports:
      - "8080:8080"
    networks:
      - aq_auth_network

networks:
  aq_auth_network:
    driver: bridge
```

**Обновить .env:**
```bash
# PostgreSQL
POSTGRES_DB=aq_auth
POSTGRES_USER=aq
POSTGRES_PASSWORD=aq_secret_change_in_production
POSTGRES_PORT=5433

# Auth Service
AUTH_ENDPOINT=http://localhost:8080
JWT_SECRET=your-super-secret-jwt-key-change-in-production

# Google OAuth (опционально)
GOOGLE_CLIENT_ID=
GOOGLE_CLIENT_SECRET=
```

**Обновить README.md** с инструкциями по запуску.

**Результат:** Полный стек готов к запуску.

---

### Шаг 5: Протестировать стек

**Запустить:**
```bash
cd deploys/aq_auth_stack
docker-compose up --build
```

**Проверить:**
```bash
# 1. PostgreSQL
psql -h localhost -p 5433 -U aq -d aq_auth -c "\dt"
# Должны быть таблицы: security_users, security_sessions, etc.

# 2. Auth Data Service
curl http://localhost:8090/health
curl http://localhost:8090/domains

# 3. Auth Service
curl http://localhost:8080/auth/health
```

**Результат:** Стек работает.

---

### Шаг 6: Проверить клиентскую часть

**Цель:** Убедиться что клиент может подключиться.

**Тест (Dart CLI):**
```dart
import 'package:aq_security/aq_security.dart';

void main() async {
  // Инициализация
  final service = await AQSecurityClient.init('http://localhost:8080');

  print('✅ Connected to auth service');
  print('State: ${service.state}');

  // TODO: Тест login когда будет mock provider
}
```

**Результат:** Клиент подключается.

---

### Шаг 7: Добавить недостающие компоненты (если нужно)

**Проверить что работает:**
- ✅ JWT token issuer
- ✅ Session management
- ✅ Google OAuth2
- ✅ API key validation
- ✅ Token refresh

**Если чего-то не хватает — добавить.**

---

### Шаг 8: Создать систему Credentials (опционально)

**Цель:** Унифицировать способы аутентификации.

**Создать:** `pkgs/aq_schema/lib/security/models/credentials.dart`

```dart
abstract class Credentials {
  String get type;
  Map<String, dynamic> toJson();

  factory Credentials.fromJson(Map<String, dynamic> json) {
    final type = json['type'] as String;
    return switch (type) {
      'email_password' => EmailPasswordCredentials.fromJson(json),
      'google_oauth' => GoogleOAuthCredentials.fromJson(json),
      'api_key' => ApiKeyCredentials.fromJson(json),
      'token' => TokenCredentials.fromJson(json),
      _ => throw Exception('Unknown credentials type: $type'),
    };
  }
}

class EmailPasswordCredentials extends Credentials {
  final String email;
  final String password;

  String get type => 'email_password';

  EmailPasswordCredentials({required this.email, required this.password});

  factory EmailPasswordCredentials.fromJson(Map<String, dynamic> json) =>
      EmailPasswordCredentials(
        email: json['email'] as String,
        password: json['password'] as String,
      );

  Map<String, dynamic> toJson() => {
    'type': type,
    'email': email,
    'password': password,
  };
}

class GoogleOAuthCredentials extends Credentials {
  final String code;
  final String redirectUri;

  String get type => 'google_oauth';

  GoogleOAuthCredentials({required this.code, required this.redirectUri});

  factory GoogleOAuthCredentials.fromJson(Map<String, dynamic> json) =>
      GoogleOAuthCredentials(
        code: json['code'] as String,
        redirectUri: json['redirectUri'] as String,
      );

  Map<String, dynamic> toJson() => {
    'type': type,
    'code': code,
    'redirectUri': redirectUri,
  };
}

class ApiKeyCredentials extends Credentials {
  final String apiKey;

  String get type => 'api_key';

  ApiKeyCredentials({required this.apiKey});

  factory ApiKeyCredentials.fromJson(Map<String, dynamic> json) =>
      ApiKeyCredentials(apiKey: json['apiKey'] as String);

  Map<String, dynamic> toJson() => {
    'type': type,
    'apiKey': apiKey,
  };
}

class TokenCredentials extends Credentials {
  final String token;

  String get type => 'token';

  TokenCredentials({required this.token});

  factory TokenCredentials.fromJson(Map<String, dynamic> json) =>
      TokenCredentials(token: json['token'] as String);

  Map<String, dynamic> toJson() => {
    'type': type,
    'token': token,
  };
}
```

**Обновить AuthRequest** чтобы использовать Credentials.

**Результат:** Унифицированная система аутентификации.

---

### Шаг 9: Написать базовые тесты

**Создать:** `server_apps/aq_auth_service/test/auth_flow_test.dart`

```dart
import 'package:test/test.dart';
import 'package:aq_security/aq_security.dart';

void main() {
  group('Auth Flow', () {
    late AQSecurityService service;

    setUp(() async {
      service = await AQSecurityClient.init('http://localhost:8080');
    });

    test('health check', () async {
      expect(service, isNotNull);
    });

    // TODO: Добавить тесты для login, logout, refresh
  });
}
```

**Результат:** Базовое тестирование работает.

---

### Шаг 10: Документация

**Создать:** `deploys/aq_auth_stack/QUICKSTART.md`

```markdown
# Quick Start — AQ Auth Stack

## Запуск

```bash
cd deploys/aq_auth_stack
docker-compose up -d
```

## Проверка

```bash
# PostgreSQL
psql -h localhost -p 5433 -U aq -d aq_auth

# Auth Data Service
curl http://localhost:8090/health

# Auth Service
curl http://localhost:8080/auth/health
```

## Использование из Flutter

```dart
import 'package:aq_security/aq_security.dart';

void main() async {
  final service = await AQSecurityClient.init('http://localhost:8080');

  // Login with Google
  final auth = await service.loginWithGoogle(
    code: googleCode,
    redirectUri: redirectUri,
  );

  print('Logged in: ${auth.user.email}');
}
```

## Использование из Worker

```dart
import 'package:aq_security/aq_security.dart';

void main() async {
  final service = await AQSecurityClient.init(
    Platform.environment['AUTH_ENDPOINT']!,
    jwtSecret: Platform.environment['JWT_SECRET'],
  );

  // Login with API key
  await service.loginWithApiKey(Platform.environment['API_KEY']!);

  // Use access token
  final token = await service.accessToken;
}
```
```

**Результат:** Документация для быстрого старта.

---

## ✅ Критерии готовности

### Минимальный продукт (MVP)
- [x] aq_auth_data_service работает
- [x] aq_auth_service работает
- [x] Docker stack поднимается
- [x] Клиент может подключиться
- [x] Google OAuth работает
- [x] JWT токены выдаются
- [x] Sessions управляются

### Production-ready
- [ ] Все типы аутентификации работают
- [ ] API ключи полностью реализованы
- [ ] RBAC расширен (wildcards, иерархия)
- [ ] Тесты покрывают 80%+ кода
- [ ] Документация полная
- [ ] Security audit пройден

---

## 🎯 Итоговая последовательность

1. ✅ Проверить текущее состояние
2. ✅ Реализовать aq_auth_data_service (bin/main.dart + Dockerfile)
3. ✅ Проверить aq_auth_service (использует RemoteVaultStorage)
4. ✅ Обновить docker-compose.yml (3 сервиса)
5. ✅ Протестировать стек (docker-compose up)
6. ✅ Проверить клиент (AQSecurityClient.init)
7. ⚠️ Добавить недостающее (если нужно)
8. ⚠️ Credentials система (опционально)
9. ⚠️ Базовые тесты
10. ⚠️ Документация

**После шага 6 — система готова к использованию!**

Шаги 7-10 — улучшения для production.

---

**Готов начать с шага 1!** 🚀
