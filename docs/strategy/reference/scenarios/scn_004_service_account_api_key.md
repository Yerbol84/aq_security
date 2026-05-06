# SCN-004: Сервисный аккаунт — Авторизация через API Key

**ID:** SCN-004  
**Тип:** Backend Flow  
**Субъект:** Service Account (`SessionKind.service`)  
**Покрывает:** `IApiKeyRepository`, `ApiKeyService`, `AQSecurityService.loginWithApiKey()`

---

## Описание

Worker или backend-сервис авторизуется через API Key, получает токен с ограниченными правами, выполняет операции от имени сервисного аккаунта.

---

## Pipeline

```
[Worker/Service]                [Auth Server]                  [In-Memory Storage]
    │                               │                                │
    │── service.loginWithApiKey     │                                │
    │     (apiKey) ────────────────►│                                │
    │                               │── ApiKeyService                │
    │                               │   .validateKey(apiKey) ───────►│
    │                               │   (hash → lookup) ─────────────│
    │                               │◄─ AqApiKey(userId,             │
    │                               │     permissions,isActive) ─────│
    │                               │── isActive check               │
    │                               │── IUserRepository.findById ───►│
    │                               │◄─ AqUser(serviceAccount) ──────│
    │                               │── ISessionRepository.create    │
    │                               │   (kind=SessionKind.service) ──►│
    │                               │── TokenIssuer.issue(           │
    │                               │     scopes=apiKey.permissions) │
    │◄─ AuthResponse(tokens) ───────│                                │
    │                               │                                │
    │── [использует токен для       │                                │
    │    запросов к data layer] ────│                                │
    │                               │                                │
    │── IApiKeyRepository           │                                │
    │   .updateLastUsed(id, now) ───►│                               │
```

---

## Клиентский userflow (worker)

1. Worker стартует → читает `API_KEY` из env
2. `AqSecurity.init(config)` → инициализация
3. `service.loginWithApiKey(apiKey)` → `AuthResponse`
4. Токен используется для всех последующих запросов
5. При истечении токена — повторный `loginWithApiKey` (нет refresh для service accounts)

## Серверный workflow

1. `POST /auth/login` с `{credentials: {type: 'api_key', apiKey: '...'}}`
2. `ApiKeyService.validateKey(apiKey)` → hash → lookup в `IApiKeyRepository`
3. Проверка `isActive == true`
4. `IApiKeyRepository.updateLastUsed(id, timestamp)`
5. `IUserRepository.findById(apiKey.userId)` → `AqUser`
6. `ISessionRepository.create(session с kind=service)`
7. `TokenIssuer.issue(user, session, scopes: apiKey.permissions)`
8. Вернуть `AuthResponse`

---

## In-memory реализация

Использует `InMemoryApiKeyRepository`.  
Тестовый API Key создаётся при инициализации с правами `['projects:read', 'graphs:read']`.
