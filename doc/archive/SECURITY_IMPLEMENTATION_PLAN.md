# План реализации системы безопасности AQ Studio

**Дата:** 2026-04-07
**Версия:** 1.0
**Статус:** Планирование

---

## 🎯 Цели и принципы

### Главная цель
Создать полноценную систему безопасности для AQ Studio с поддержкой:
- Аутентификации (JWT, OAuth2, API ключи)
- Авторизации (RBAC с гранулярными правами)
- Управления сессиями
- Multi-tenancy изоляции
- Audit logging

### Ключевые принципы

1. **Тонкий клиент** — клиент не содержит бизнес-логики безопасности
2. **Единое окно** — `AQSecure.instance.*` для всех операций
3. **Два режима** — client/server в одном пакете с раздельными exports
4. **Интеграция с dart_vault** — все данные через тонкий клиент
5. **Production-ready** — полное тестирование и документация

---

## 📊 Текущее состояние (Audit)

### ✅ Что уже реализовано

#### Модели (aq_schema/security)
- ✅ `AqUser` — пользователи (человек/сервис)
- ✅ `AqSession` — сессии с lifecycle
- ✅ `AqTokenClaims` — JWT payload
- ✅ `AqRole` — роли с permissions
- ✅ `AqUserRole` — назначение ролей
- ✅ `AqApiKey` — API ключи с hash
- ✅ `AqTenant` — тенанты (проверить наличие)
- ✅ `AqProfile` — профили пользователей (проверить наличие)

#### Storable обертки (aq_schema/security/storable)
- ✅ `StorableUser` (DirectStorable)
- ✅ `StorableTenant` (DirectStorable)
- ✅ `StorableProfile` (DirectStorable)
- ✅ `StorableRole` (DirectStorable)
- ✅ `StorableUserRole` (DirectStorable)
- ✅ `StorableSession` (LoggedStorable)
- ✅ `StorableApiKey` (LoggedStorable)

#### Домены (aq_schema/security/storable)
- ✅ `AqSecurityDomains.all` — список всех доменов
- ✅ `SecurityCollections` — имена коллекций
- ✅ Индексы для всех таблиц

#### Клиент (aq_security/src/client)
- ✅ `AQSecurityClient.init()` — инициализация
- ✅ `AQSecurityService` — основной сервис
- ✅ `SecurityState` — состояния (authenticated/unauthenticated/loading/error)
- ✅ `LocalSessionStore` — локальное хранение токенов
- ✅ `HttpAuthTransport` — HTTP клиент
- ✅ Методы: loginWithGoogle, loginWithApiKey, logout, restoreSession
- ✅ Автоматический refresh токенов
- ✅ Stream<SecurityState> для реактивности

#### Сервер (aq_security/src/server)
- ✅ `AQAuthServer` — основной сервер
- ✅ `TokenIssuer` — генерация JWT
- ✅ `TokenCodec` — кодирование/декодирование JWT
- ✅ `TokenValidator` — валидация JWT
- ✅ `SessionService` — управление сессиями
- ✅ `UserService` — управление пользователями
- ✅ `ApiKeyService` — управление API ключами
- ✅ `GoogleOAuthService` — Google OAuth2
- ✅ `AuthRouter` — HTTP роуты
- ✅ `AuthMiddleware` — защита роутов

#### Инфраструктура
- ✅ `server_apps/aq_auth_service` — готовое приложение
- ✅ `server_apps/aq_auth_data_service` — data service для auth
- ✅ `deploys/aq_auth_stack` — Docker Compose стек (частично)

### ⚠️ Что требует доработки

#### 1. Модели
- ⚠️ Проверить наличие `AqTenant` и `AqProfile`
- ❌ Отсутствует система `Credentials` (полиморфные учетные данные)
- ❌ Отсутствует модель `Permission` для гранулярных прав
- ❌ Отсутствует модель `Resource` для управления доступом к ресурсам
- ❌ Нет поддержки иерархии ролей (platform/tenant/project)

#### 2. API ключи
- ⚠️ Базовая реализация есть, но нужно:
  - Генерация с префиксами (aq_live_, aq_test_)
  - Показ raw ключа только при создании
  - Ротация ключей
  - Tracking lastUsedAt при каждом использовании

#### 3. RBAC
- ⚠️ Базовая система есть, но нужно:
  - Wildcard permissions (projects:*, admin:*)
  - Иерархия ролей (наследование)
  - Временные роли (expires_at)
  - Делегирование прав

#### 4. Data Service интеграция
- ❌ `aq_auth_data_service` не подключен к dart_vault
- ❌ Нет регистрации security доменов в VaultRegistry
- ❌ Нет Dockerfile для aq_auth_data_service

#### 5. Docker Stack
- ⚠️ Частично готов, нужно:
  - Добавить aq_auth_service в docker-compose
  - Настроить сеть между сервисами
  - Добавить health checks
  - Обновить .env и README

#### 6. Интеграция с Data Layer
- ❌ Нет middleware для проверки токенов в dart_vault
- ❌ Нет автоматической фильтрации по tenantId из токена
- ❌ Нет audit logging для критичных операций

#### 7. Тесты
- ❌ Нет unit тестов для моделей
- ❌ Нет интеграционных тестов auth service
- ❌ Нет E2E тестов полного flow

#### 8. Документация
- ❌ Нет архитектурной документации
- ❌ Нет руководства по использованию
- ❌ Нет примеров для разных сценариев

---

## 🗺️ Roadmap реализации

### Фаза 1: Аудит и планирование ✅ (Текущая)
**Срок:** 1 день
**Статус:** Завершена

- [x] Изучить документацию dart_vault
- [x] Изучить текущую реализацию aq_security
- [x] Изучить модели в aq_schema/security
- [x] Оценить готовность к production
- [x] Создать план реализации

### Фаза 2: Дополнение моделей
**Срок:** 2-3 дня
**Приоритет:** Высокий

**Задачи:**
1. Проверить наличие AqTenant и AqProfile
2. Создать систему Credentials (полиморфные учетные данные)
3. Добавить модель Permission
4. Добавить модель Resource
5. Расширить AqRole для иерархии
6. Обновить Storable обертки

**Результат:** Полный набор моделей для production

### Фаза 3: Расширение RBAC
**Срок:** 2-3 дня
**Приоритет:** Высокий

**Задачи:**
1. Реализовать wildcard permissions
2. Добавить иерархию ролей
3. Реализовать временные роли
4. Добавить делегирование прав
5. Обновить UserService для новой логики
6. Обновить TokenIssuer для включения permissions в JWT

**Результат:** Гибкая система управления правами

### Фаза 4: Улучшение API ключей
**Срок:** 1-2 дня
**Приоритет:** Средний

**Задачи:**
1. Генерация с префиксами
2. Показ raw ключа только при создании
3. Ротация ключей
4. Tracking lastUsedAt
5. Обновить ApiKeyService

**Результат:** Production-ready управление API ключами

### Фаза 5: Интеграция Data Service
**Срок:** 2-3 дня
**Приоритет:** Критический

**Задачи:**
1. Создать Dockerfile для aq_auth_data_service
2. Зарегистрировать security домены в VaultRegistry
3. Настроить PostgresSchemaDeployer
4. Проверить индексы
5. Обновить bin/main.dart для подключения к PostgreSQL

**Результат:** Работающий data service для auth

### Фаза 6: Docker Stack
**Срок:** 1-2 дня
**Приоритет:** Высокий

**Задачи:**
1. Добавить aq_auth_service в docker-compose
2. Настроить сеть между сервисами
3. Добавить health checks
4. Обновить .env
5. Обновить README с инструкциями
6. Протестировать полный стек

**Результат:** Готовый к развертыванию стек

### Фаза 7: Интеграция с Data Layer
**Срок:** 2-3 дня
**Приоритет:** Критический

**Задачи:**
1. Создать AuthMiddleware для dart_vault
2. Интеграция с aq_auth_service для валидации
3. Автоматическая фильтрация по tenantId
4. Проверка permissions перед операциями
5. Audit logging
6. Обновить aq_studio_data_service

**Результат:** Защищенный data layer

### Фаза 8: Тестирование
**Срок:** 3-4 дня
**Приоритет:** Критический

**Задачи:**
1. Unit тесты для моделей
2. Интеграционные тесты auth service
3. Тесты JWT lifecycle
4. Тесты session management
5. Тесты API key management
6. Тесты RBAC
7. Тесты multi-tenancy
8. E2E тесты

**Результат:** Полное покрытие тестами

### Фаза 9: Документация
**Срок:** 2-3 дня
**Приоритет:** Высокий

**Задачи:**
1. SECURITY_ARCHITECTURE.md
2. SECURITY_GUIDE.md
3. API_REFERENCE.md
4. DEPLOYMENT.md
5. BEST_PRACTICES.md
6. Примеры использования

**Результат:** Полная документация

### Фаза 10: Production Readiness
**Срок:** 2-3 дня
**Приоритет:** Критический

**Задачи:**
1. Security audit
2. Performance testing
3. Load testing
4. Monitoring setup
5. Logging setup
6. Backup strategy
7. Disaster recovery plan

**Результат:** Готовность к production

---

## 🏗️ Архитектура (целевая)

### Компоненты системы

```
┌─────────────────────────────────────────────────────────────────┐
│                     Flutter/Dart Client                         │
│                                                                 │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │              AQSecurityClient.init()                     │  │
│  │  • Единая точка входа                                    │  │
│  │  • Автоматический refresh                                │  │
│  │  • Локальное хранение сессии                            │  │
│  └────────────────────┬─────────────────────────────────────┘  │
│                       │                                         │
│  ┌────────────────────▼─────────────────────────────────────┐  │
│  │              AQSecurityService                           │  │
│  │  • login(Credentials)                                    │  │
│  │  • logout()                                              │  │
│  │  • validateToken()                                       │  │
│  │  • listSessions()                                        │  │
│  │  • Stream<SecurityState>                                 │  │
│  └──────────────────────────────────────────────────────────┘  │
└─────────────────────────┼───────────────────────────────────────┘
                          │ HTTPS
                          │
┌─────────────────────────▼───────────────────────────────────────┐
│                    AQ Auth Service                              │
│                                                                 │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │                  AQAuthServer                            │  │
│  │  • JWT issuer (access + refresh)                        │  │
│  │  • Session management                                    │  │
│  │  • OAuth2 integration                                    │  │
│  │  • API key validation                                    │  │
│  │  • RBAC enforcement                                      │  │
│  └────────────────────┬─────────────────────────────────────┘  │
│                       │                                         │
│                       │ RemoteVaultStorage                      │
│                       │                                         │
└───────────────────────┼─────────────────────────────────────────┘
                        │
┌───────────────────────▼─────────────────────────────────────────┐
│              AQ Auth Data Service                               │
│                                                                 │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │                  VaultRegistry                           │  │
│  │  • Security domains registration                         │  │
│  │  • RPC dispatch                                          │  │
│  └────────────────────┬─────────────────────────────────────┘  │
│                       │                                         │
│  ┌────────────────────▼─────────────────────────────────────┐  │
│  │            PostgresVaultStorage                          │  │
│  │  • users, sessions, roles, api_keys                     │  │
│  │  • Multi-tenancy isolation                               │  │
│  └────────────────────┬─────────────────────────────────────┘  │
└───────────────────────┼─────────────────────────────────────────┘
                        │
┌───────────────────────▼─────────────────────────────────────────┐
│                    PostgreSQL                                   │
│  • security_users                                               │
│  • security_sessions (+ _log)                                   │
│  • security_roles                                               │
│  • security_api_keys (+ _log)                                   │
│  • security_tenants                                             │
│  • security_profiles                                            │
└─────────────────────────────────────────────────────────────────┘
```

### Типы пользователей

```
AqUser
├── UserType.endUser (человек - обычный пользователь)
├── UserType.developer (человек - разработчик)
├── UserType.platformAdmin (человек - администратор платформы)
└── UserType.service (нечеловек - сервисный аккаунт)
    ├── Worker (создается через человека/предприятие)
    ├── AI Agent (создается через человека/предприятие)
    └── Enterprise (юридическое лицо)
```

### Система Credentials (полиморфная)

```dart
abstract class Credentials {
  String get type; // discriminator
}

class EmailPasswordCredentials extends Credentials {
  final String email;
  final String password;
  String get type => 'email_password';
}

class GoogleOAuthCredentials extends Credentials {
  final String code;
  final String redirectUri;
  String get type => 'google_oauth';
}

class ApiKeyCredentials extends Credentials {
  final String apiKey;
  String get type => 'api_key';
}

class TokenCredentials extends Credentials {
  final String token; // токен владельца для service accounts
  String get type => 'token';
}
```

### RBAC архитектура

```
Platform Level (tenantId = null)
├── Role: platform_admin
│   └── Permissions: ['*'] (все права)
└── Role: platform_developer
    └── Permissions: ['tenants:create', 'tenants:read']

Tenant Level (tenantId = 'tenant-123')
├── Role: tenant_owner
│   └── Permissions: ['tenant:*', 'projects:*', 'users:*']
├── Role: tenant_admin
│   └── Permissions: ['projects:*', 'users:read', 'users:invite']
└── Role: tenant_member
    └── Permissions: ['projects:read', 'projects:create']

Project Level (resourceId = 'project-456')
├── Role: project_owner
│   └── Permissions: ['project:*']
├── Role: project_editor
│   └── Permissions: ['project:read', 'project:write']
└── Role: project_viewer
    └── Permissions: ['project:read']
```

### Permission паттерн

```
resource:action[:scope]

Примеры:
- projects:read          # читать проекты
- projects:write         # писать проекты
- projects:*             # все операции с проектами
- admin:*                # все админские операции
- users:invite:tenant    # приглашать пользователей в тенант
- agents:run:project     # запускать агентов в проекте
```

---

## 🔐 Безопасность

### JWT токены

**Access Token:**
- Срок жизни: 15 минут
- Содержит: userId, tenantId, roles, permissions, userType
- Используется для всех API запросов

**Refresh Token:**
- Срок жизни: 30 дней
- Содержит: userId, sessionId
- Используется только для обновления access token

### API ключи

**Формат:**
```
aq_live_1234567890abcdef1234567890abcdef  # production
aq_test_1234567890abcdef1234567890abcdef  # testing
```

**Хранение:**
- Raw ключ показывается только при создании
- В БД хранится только SHA-256 hash
- Prefix (первые 8 символов) для идентификации в UI

### Сессии

**Lifecycle:**
```
active → expired (по времени)
active → revoked (вручную)
```

**Tracking:**
- createdAt, expiresAt, lastSeenAt
- ipAddress, userAgent, deviceHint
- revokedAt, revokedReason (если отозвана)

---

## 📈 Метрики успеха

### Функциональные
- ✅ Все типы аутентификации работают
- ✅ RBAC корректно проверяет права
- ✅ Multi-tenancy изолирует данные
- ✅ API ключи работают для service accounts
- ✅ Сессии корректно управляются

### Производительность
- ✅ Валидация токена < 10ms
- ✅ Login < 500ms
- ✅ Token refresh < 100ms
- ✅ Permission check < 5ms

### Надежность
- ✅ 100% покрытие тестами критичных путей
- ✅ Нет SQL injection уязвимостей
- ✅ Нет XSS уязвимостей
- ✅ Корректная обработка ошибок

### Документация
- ✅ Архитектурная документация
- ✅ API reference
- ✅ Deployment guide
- ✅ Примеры для всех сценариев

---

## 🚀 Следующие шаги

1. **Немедленно:**
   - Проверить наличие AqTenant и AqProfile
   - Начать реализацию системы Credentials

2. **На этой неделе:**
   - Завершить модели безопасности
   - Расширить RBAC
   - Интегрировать aq_auth_data_service

3. **На следующей неделе:**
   - Завершить Docker stack
   - Интегрировать с Data Layer
   - Начать тестирование

4. **Через 2 недели:**
   - Завершить тестирование
   - Написать документацию
   - Production readiness audit

---

## 📝 Заметки

### Лучшие практики из мирового опыта

1. **Auth0 / Okta паттерн:**
   - Разделение auth service и data service
   - JWT с короткими access tokens
   - Refresh tokens для длительных сессий

2. **AWS IAM паттерн:**
   - Resource-based permissions
   - Wildcard support
   - Иерархия ролей

3. **Stripe API keys паттерн:**
   - Префиксы для идентификации (live/test)
   - Показ raw ключа только при создании
   - Хранение только hash

4. **Google Cloud IAM паттерн:**
   - Service accounts для machine-to-machine
   - Временные роли
   - Audit logging

### Риски и митигация

**Риск 1:** Сложность интеграции с существующим кодом
- **Митигация:** Постепенная миграция, обратная совместимость

**Риск 2:** Производительность при большом количестве permissions
- **Митигация:** Кэширование, оптимизация запросов, индексы

**Риск 3:** Безопасность JWT токенов
- **Митигация:** Короткие access tokens, refresh rotation, revocation list

**Риск 4:** Сложность тестирования
- **Митигация:** Моки, тестовые fixtures, изолированные тесты

---

## ✅ Чеклист готовности к production

### Функциональность
- [ ] Все типы аутентификации реализованы
- [ ] RBAC полностью работает
- [ ] API ключи управляются
- [ ] Сессии управляются
- [ ] Multi-tenancy изолирует данные

### Безопасность
- [ ] Security audit пройден
- [ ] Нет известных уязвимостей
- [ ] Secrets не в коде
- [ ] HTTPS обязателен
- [ ] Rate limiting настроен

### Производительность
- [ ] Load testing пройден
- [ ] Метрики в норме
- [ ] Индексы оптимизированы
- [ ] Кэширование настроено

### Надежность
- [ ] Тесты покрывают 80%+ кода
- [ ] E2E тесты проходят
- [ ] Мониторинг настроен
- [ ] Логирование настроено
- [ ] Backup strategy готова

### Документация
- [ ] Архитектура документирована
- [ ] API reference готов
- [ ] Deployment guide готов
- [ ] Примеры работают
- [ ] Best practices описаны

---

**Конец документа**
