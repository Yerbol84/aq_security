# AQ Security Auth Service

Полноценный authentication & authorization сервер с поддержкой множественных провайдеров, RBAC и token management.

## Возможности

### Auth Providers
- ✅ **Email/Password** — классическая аутентификация
- ✅ **Google OAuth** — OAuth 2.0 через Google
- ✅ **GitHub OAuth** — OAuth 2.0 через GitHub
- ✅ **API Keys** — для server-to-server коммуникации

### RBAC System
- ✅ **Roles** — именованные наборы прав
- ✅ **Permissions** — гранулярные права доступа (`resource:action:scope`)
- ✅ **Policies** — условные правила доступа
- ✅ **Role Inheritance** — иерархия ролей

### Token Management
- ✅ **JWT Access Tokens** — короткоживущие (1 час)
- ✅ **Refresh Tokens** — долгоживущие (30 дней)
- ✅ **Token Rotation** — автоматическая ротация при refresh
- ✅ **Token Blacklist** — отзыв токенов через Redis

### Security Features
- ✅ **Rate Limiting** — защита от brute-force
- ✅ **CORS** — настраиваемые allowed origins
- ✅ **Security Headers** — XSS, clickjacking protection
- ✅ **Audit Logging** — полный audit trail

## Архитектура

```
┌─────────────────────────────────────────────────────────────┐
│                      Auth Service                           │
│                                                             │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐     │
│  │   Auth       │  │    RBAC      │  │ Introspection│     │
│  │  /auth/*     │  │  /rbac/*     │  │ /api/introspect    │
│  └──────────────┘  └──────────────┘  └──────────────┘     │
│         │                 │                   │            │
│         └─────────────────┴───────────────────┘            │
│                           ▼                                │
│                   ┌──────────────┐                         │
│                   │  Data Layer  │                         │
│                   │   :8090      │                         │
│                   └──────────────┘                         │
└─────────────────────────────────────────────────────────────┘
```

## Endpoints

### Authentication

**Email/Password**:
- `POST /auth/login` — вход
- `POST /auth/register` — регистрация
- `POST /auth/logout` — выход

**OAuth**:
- `GET /auth/google` — Google OAuth redirect
- `GET /auth/google/callback` — Google OAuth callback
- `GET /auth/github` — GitHub OAuth redirect
- `GET /auth/github/callback` — GitHub OAuth callback

**Token Management**:
- `POST /auth/refresh` — обновить токены
- `POST /auth/revoke` — отозвать токен

**API Keys**:
- `POST /auth/api-key` — вход через API key

### RBAC

**Roles**:
- `GET /rbac/roles` — список ролей
- `POST /rbac/roles` — создать роль
- `GET /rbac/roles/:id` — получить роль
- `PUT /rbac/roles/:id` — обновить роль
- `DELETE /rbac/roles/:id` — удалить роль

**Permissions**:
- `GET /rbac/permissions` — проверить права
- `POST /rbac/permissions/check` — проверить конкретное право

**User Roles**:
- `GET /rbac/users/:userId/roles` — роли пользователя
- `POST /rbac/users/:userId/roles` — назначить роль
- `DELETE /rbac/users/:userId/roles/:roleId` — отозвать роль

### Introspection

**Token Introspection** (для resource servers):
- `POST /api/introspect` — проверить токен и права

### Health

- `GET /health` — health check

## Запуск локально

### Требования

- Dart SDK 3.3+
- Running Data Layer (server_data)
- Redis (для rate limiting)
- Переменные окружения

### Установка зависимостей

```bash
dart pub get
```

### Настройка переменных окружения

```bash
export AUTH_SERVICE_PORT=8080
export AUTH_DATA_SERVICE_URL=http://localhost:8090
export AUTH_JWT_SECRET=your_jwt_secret_minimum_32_characters
export REDIS_URL=redis://localhost:6379
export ALLOWED_ORIGINS=http://localhost:3000,http://localhost:8081
export ENV=development

# Google OAuth (optional)
export GOOGLE_CLIENT_ID=your_google_client_id
export GOOGLE_CLIENT_SECRET=your_google_client_secret
export GOOGLE_REDIRECT_URI=http://localhost:8080/auth/google/callback

# GitHub OAuth (optional)
export GITHUB_CLIENT_ID=your_github_client_id
export GITHUB_CLIENT_SECRET=your_github_client_secret
export GITHUB_REDIRECT_URI=http://localhost:8080/auth/github/callback
```

### Запуск

```bash
dart run bin/main.dart
```

## Запуск в Docker

См. `../stack/README.md` для запуска полного стека.

## Тестовые данные

В режиме `ENV=development` автоматически создаются:

**Tenant**:
- Slug: `test-company`
- Name: Test Company

**Users**:
| Email | Password | Role |
|-------|----------|------|
| admin@test.com | admin123 | Admin (full access) |
| developer@test.com | dev123 | Developer (read all, write own) |
| viewer@test.com | view123 | Viewer (read-only) |

**API Key**:
- Key: `aq_test_1234567890abcdef`
- User: admin@test.com

## Примеры использования

### Email/Password Login

```bash
curl -X POST http://localhost:8080/auth/login \
  -H "Content-Type: application/json" \
  -d '{
    "email": "admin@test.com",
    "password": "admin123"
  }'
```

Response:
```json
{
  "accessToken": "eyJhbGc...",
  "refreshToken": "eyJhbGc...",
  "user": {
    "id": "user_admin",
    "email": "admin@test.com",
    "tenantId": "tenant_test"
  }
}
```

### Refresh Token

```bash
curl -X POST http://localhost:8080/auth/refresh \
  -H "Content-Type: application/json" \
  -d '{
    "refreshToken": "eyJhbGc..."
  }'
```

### Check Permission

```bash
curl -X POST http://localhost:8080/rbac/permissions/check \
  -H "Authorization: Bearer eyJhbGc..." \
  -H "Content-Type: application/json" \
  -d '{
    "permission": "projects:write",
    "resourceId": "project_123"
  }'
```

### Token Introspection (для resource servers)

```bash
curl -X POST http://localhost:8080/api/introspect \
  -H "Content-Type: application/json" \
  -d '{
    "token": "eyJhbGc...",
    "resource": "projects",
    "action": "read"
  }'
```

Response:
```json
{
  "active": true,
  "allowed": true,
  "userId": "user_admin",
  "tenantId": "tenant_test",
  "permissions": ["*:*:*"]
}
```

## OAuth Setup

### Google OAuth

1. Перейти в [Google Cloud Console](https://console.cloud.google.com/apis/credentials)
2. Создать OAuth 2.0 Client ID
3. Добавить redirect URI: `http://localhost:8080/auth/google/callback`
4. Скопировать Client ID и Client Secret в `.env`

### GitHub OAuth

1. Перейти в [GitHub Developer Settings](https://github.com/settings/developers)
2. Создать OAuth App
3. Добавить callback URL: `http://localhost:8080/auth/github/callback`
4. Скопировать Client ID и Client Secret в `.env`

## Мониторинг

### Логи

Все запросы логируются в stdout:

```
2026-04-22T15:30:00.000Z INFO POST /auth/login 200 45ms
2026-04-22T15:30:05.000Z INFO GET /rbac/roles 200 12ms
```

### Health Check

```bash
curl http://localhost:8080/health
```

### Metrics (TODO)

Prometheus metrics endpoint: `/metrics`

## Troubleshooting

### Проблема: Не может подключиться к Data Layer

**Симптомы**: `Failed to connect to data service`

**Решение**:
```bash
# Проверить, что data layer запущен
curl http://localhost:8090/health

# Проверить переменную окружения
echo $AUTH_DATA_SERVICE_URL
```

### Проблема: JWT Secret слишком короткий

**Симптомы**: `AUTH_JWT_SECRET must be at least 32 characters`

**Решение**:
```bash
# Сгенерировать случайный секрет
openssl rand -base64 32

# Установить в .env
export AUTH_JWT_SECRET=<generated_secret>
```

### Проблема: OAuth не работает

**Симптомы**: `OAuth provider not configured`

**Решение**:
1. Проверить, что все переменные установлены
2. Проверить redirect URI в OAuth провайдере
3. Проверить, что callback URL доступен

## Production Deployment

### Важные изменения

1. **Секреты**:
   - Использовать сильный JWT_SECRET (минимум 32 символа)
   - Хранить в secure vault
   - Ротировать регулярно

2. **CORS**:
   - Указать конкретные allowed origins
   - Не использовать wildcard `*`

3. **Rate Limiting**:
   - Настроить под нагрузку
   - Использовать Redis cluster

4. **SSL/TLS**:
   - Использовать HTTPS
   - Настроить SSL certificates

5. **Мониторинг**:
   - Prometheus metrics
   - Алерты на ошибки
   - Centralized logging

## Связанные компоненты

- **Data Layer**: `../server_data/` — хранилище данных
- **Docker Stack**: `../stack/` — оркестрация
- **Клиенты**: `../client_*/` — примеры использования

## Лицензия

См. корневой README пакета `aq_security`.
