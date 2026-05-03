# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Язык / Language

**ВАЖНО: Вся коммуникация с пользователем должна быть на русском языке.**

## Обзор пакета

`aq_security` — унифицированный пакет аутентификации и авторизации для AQ Studio. Предоставляет полный стек безопасности:

- **Клиентский режим**: SDK для подключения к auth-сервису (`AQSecurityClient`)
- **Серверный режим**: Полноценный auth-сервер (`AQAuthServer`) с JWT, OAuth, RBAC
- **Dual-mode**: Клиент может быть одновременно потребителем (consumer) и защищаемым ресурсом (resource server)

### Место в архитектуре платформы

Пакет следует архитектурной стратегии AQ Platform, описанной в документе:
**`../aq_schema/archive/AQ Platform — Архитектура корневого пакета и карта клиентов.md`**

Ключевые принципы из этой стратегии:

1. **Зависимость от aq_schema**: Все доменные модели безопасности (AQRole, AQPermission, AQTokenClaims, AQApiKeyClaims) живут в `aq_schema/security.dart`
2. **Типизированные клиенты**: Разные интерфейсы для разных потребителей (см. раздел 4.1 в архитектурном документе):
   - `IAQAuthUserClient` — для UI приложений (login, logout, refresh)
   - `IAQAuthResourceClient` — для воркеров и серверов (validateToken, API keys)
   - `IAQAuthAdminClient` — для администраторов (управление ролями, выдача ключей)
   - `IAQAuthEngineClient` — для движка (offline validation, без HTTP)
3. **Регистрация через AQPlatform**: Реализация регистрируется при старте через `AQPlatform.init(auth: ...)`
4. **Принцип наименьших привилегий**: Каждый клиент видит только тот API, который ему необходим

### Ключевые возможности

- **Auth провайдеры**: Google OAuth, GitHub OAuth, Email/Password, API Keys, Magic Links
- **Token management**: JWT с refresh token rotation, blacklist через Redis
- **RBAC**: Роли, права, политики, иерархия, временные роли
- **Resource protection**: Introspection endpoint для защиты ресурсов
- **Security hardening**: Rate limiting, DoS protection, security headers, CORS
- **Monitoring**: Метрики, логи доступа, алерты, аналитика

## Архитектура

### Два barrel-файла

```dart
// Клиентский barrel (безопасен для Flutter, workers, CLI)
import 'package:aq_security/aq_security.dart';

// Серверный barrel (только для server apps)
import 'package:aq_security/aq_security_server.dart';
```

**ПРАВИЛО**: Никогда не импортируйте `aq_security_server.dart` в клиентском коде (Flutter, workers).

### Слои

```
Client Layer (aq_security.dart)
  ├─ AQSecurityClient      # Инициализация SDK
  ├─ AQSecurityService     # Auth операции (login, logout, refresh)
  ├─ IntrospectionClient   # Проверка токенов (для Resource Server)
  └─ RBACClient            # Проверка прав

Server Layer (aq_security_server.dart)
  ├─ AQAuthServer          # Главный auth-сервер
  ├─ AuthRouter            # /auth/* endpoints
  ├─ RBACRouter            # /rbac/* endpoints
  ├─ IntrospectionRouter   # /api/introspect
  ├─ Services              # GoogleOAuthService, PasswordService, etc.
  └─ Middleware            # Auth, CORS, Rate limiting, Security headers

RBAC Engine
  ├─ AccessControlEngine   # Проверка прав с кэшированием
  ├─ RBACService           # Управление ролями и правами
  └─ PolicyEngine          # Условные политики (time, IP, MFA)
```

## Команды разработки

### Тестирование

```bash
# Все тесты
flutter test

# Unit тесты
flutter test test/unit/

# Integration тесты (требуют PostgreSQL и Redis)
flutter test test/integration/

# E2E тесты
flutter test test/e2e/

# Конкретный тест
flutter test test/unit/api_key_service_test.dart

# С покрытием
flutter test --coverage
```

### Линтинг и форматирование

```bash
# Анализ кода
flutter analyze

# Форматирование
dart format .

# Проверка форматирования
dart format --output=none --set-exit-if-changed .
```

### Запуск auth-сервера локально

```bash
# Требуется PostgreSQL и Redis
# См. server_apps/aq_auth_service/README.md

cd ../../server_apps/aq_auth_service
dart run bin/main.dart
```

## Ключевые концепции

### 1. Dual-mode клиент

Клиент может быть одновременно:

**Consumer (потребитель)** — получает доступ к чужим ресурсам:
```dart
final client = await AQSecurityClient.init('https://auth.example.com');
await client.service.loginWithGoogle(code: oauthCode);
```

**Resource Server (защищаемый ресурс)** — защищает свои данные:
```dart
final introspect = IntrospectionClient(
  introspectionEndpoint: 'https://auth.example.com/api/introspect',
);

final result = await introspect.introspect(
  token: incomingToken,
  resource: 'projects',
  action: 'read',
  resourceId: 'proj_123',
);

if (!result.active || !result.allowed) {
  return Response.forbidden('Access denied');
}
```

### 2. RBAC формат прав

```
<resource>:<action>:<scope>

Примеры:
  projects:read:*              # Чтение всех проектов
  projects:write:own           # Запись только своих проектов
  projects:delete:tenant       # Удаление проектов в своём tenant
  *:*:*                        # Полный доступ (superadmin)
  projects:*:own               # Все действия со своими проектами
```

### 3. Token lifecycle

- **Access token**: JWT, живёт 1 час, содержит claims (userId, tenantId, permissions)
- **Refresh token**: Живёт 30 дней, используется для получения новой пары токенов
- **Refresh token rotation**: При каждом refresh старый токен инвалидируется, выдаётся новая пара
- **Blacklist**: Отозванные access tokens хранятся в Redis с TTL

### 4. API Keys

- Префиксы: `aq_live_` (production), `aq_test_` (development)
- Raw ключ показывается только один раз при создании
- В БД хранится только SHA-256 hash
- Поддержка ротации, expiration, permissions

## Важные правила

### Безопасность

1. **Никогда не коммитить секреты**: JWT_SECRET, OAuth client secrets, API keys
2. **Никогда не использовать `Access-Control-Allow-Origin: *`** для auth endpoints
3. **Всегда валидировать входные данные** перед обработкой
4. **Использовать Argon2id** для хэширования паролей (не bcrypt, не SHA-256)
5. **Никогда не хранить raw API keys** в БД (только hash)

### Тестирование

1. **Каждая фича требует тестов**: unit + integration
2. **Покрытие**: минимум 80% для нового кода, 100% для security-компонентов
3. **Регрессионные тесты**: для каждого исправленного бага
4. **Не использовать backdoor**: `test_api_key` удалён, использовать правильные тестовые репозитории

### Архитектура

1. **Зависимости**: Пакет зависит только от `aq_schema` и `dart_vault_package` (см. "Правило одной проверки" в архитектурном документе)
2. **Репозитории**: Все данные через Vault repositories, никогда напрямую к БД
3. **Immutability**: Все модели immutable с `copyWith` методами
4. **Storage classification**: Каждая сущность реализует DirectStorable, VersionedStorable или LoggedStorable
5. **Экспорт через наборы**: Следует стратегии тематических barrel-файлов (`aq_security.dart` для клиентов, `aq_security_server.dart` для серверов)

## Структура тестов

```
test/
├── unit/                    # Unit тесты (изолированные, быстрые)
│   ├── api_key_service_test.dart
│   ├── password_service_test.dart
│   ├── token_introspection_test.dart
│   ├── oauth_flow_test.dart
│   └── rate_limiter_test.dart
│
├── integration/             # Integration тесты (с PostgreSQL/Redis)
│   ├── auth_stack_test.dart
│   └── resource_server_integration_test.dart
│
├── e2e/                     # E2E тесты (полные сценарии)
│   └── full_registration_test.dart
│
└── server/                  # Серверные тесты
```

## Документация

Ключевые документы в `doc/`:

- **`AQ Security — Production Readiness Plan.md`**: Полный план выхода в production (фазы 0-6)
- **`RBAC_STRATEGY.md`**: Архитектура RBAC системы
- **`API_KEYS.md`**: Управление API ключами
- **`RBAC_business_logic.md`**: Бизнес-логика RBAC

## Типичные задачи

### Добавление нового OAuth провайдера

1. Создать `XxxOAuthService` в `lib/src/server/`
2. Добавить `XxxOAuthConfig` в `SecurityConfig`
3. Добавить `XxxOAuthCredentials` в `aq_schema/lib/security/models/credentials.dart`
4. Обновить `AuthRouter` для обработки нового типа
5. Добавить unit тесты в `test/unit/xxx_oauth_test.dart`
6. Обновить документацию

### Добавление нового типа ресурса в RBAC

1. Зарегистрировать в `ResourceType` enum (если нужно)
2. Определить actions для ресурса
3. Создать системные роли с правами для ресурса
4. Обновить `AccessControlEngine` если нужна специальная логика
5. Добавить тесты в `test/unit/rbac/`

### Добавление новой политики

1. Создать `XxxCondition` extends `PolicyCondition` в `lib/src/server/policy_engine.dart`
2. Реализовать метод `evaluate(AccessContext context)`
3. Зарегистрировать в `PolicyEngine`
4. Добавить тесты в `test/unit/policy_engine_test.dart`

## Переменные окружения

```bash
# Auth service
AUTH_SERVICE_URL=http://localhost:8080
AUTH_JWT_SECRET=your_jwt_secret_here

# OAuth
GOOGLE_CLIENT_ID=...
GOOGLE_CLIENT_SECRET=...
GITHUB_CLIENT_ID=...
GITHUB_CLIENT_SECRET=...

# Database (через aq_auth_data_service)
AUTH_DATA_SERVICE_URL=http://localhost:8090

# Redis (для rate limiting и token blacklist)
REDIS_URL=redis://localhost:6379

# CORS
ALLOWED_ORIGINS=https://app.example.com,https://admin.example.com
```

## Известные проблемы и ограничения

1. **Фаза 0 блокеры**: См. "AQ Security — Production Readiness Plan.md", Фаза 0
2. **CORS**: Настроен через `allowedOrigins` в конфиге (не wildcard)
3. **ID generation**: Используется `uuid.v4()` (не timestamp-based)
4. **LoggedStorable suffix**: Использует `_log` (не `__log`)

## Production checklist

Перед деплоем в production проверить:

- [ ] Все тесты проходят (unit + integration + e2e)
- [ ] Покрытие тестами ≥ 80%
- [ ] Нет хардкода секретов в коде
- [ ] CORS настроен правильно (не wildcard)
- [ ] Rate limiting включён
- [ ] Security headers настроены
- [ ] PostgreSQL: FK, RLS, отдельный DB user
- [ ] Redis настроен для production
- [ ] Backup скрипт настроен
- [ ] Мониторинг и алерты настроены
- [ ] Документация актуальна

## Полезные ссылки

### Архитектура и стратегия

- **Архитектура платформы и карта клиентов**: `../aq_schema/archive/AQ Platform — Архитектура корневого пакета и карта клиентов.md`
  - Раздел 4.1: Типизированные клиенты для сервиса безопасности
  - Раздел 6: Порядок инициализации (auth первым)
  - Философия: общий язык в aq_schema, реализации в пакетах

### Документация проекта

- Основная документация проекта: `../../CLAUDE.md`
- Архитектурные принципы: `../../ARCHITECTURE_PRINCIPLES.md`
- Data layer правила: `../../doc/data_layer_rules.md`
- Server apps: `../../server_apps/aq_auth_service/`

### Локальная документация

- Production Readiness Plan: `doc/AQ Security — Production Readiness Plan.md`
- RBAC стратегия: `doc/RBAC_STRATEGY.md`
- API Keys: `doc/API_KEYS.md`
