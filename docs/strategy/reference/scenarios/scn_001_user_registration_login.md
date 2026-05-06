# SCN-001: Регистрация и вход пользователя

**ID:** SCN-001  
**Тип:** User Flow (клиентский + серверный)  
**Субъект:** Человек-пользователь (`SessionKind.human`)  
**Покрывает:** `ISecurityService`, `IUserRepository`, `ISessionRepository`, `AqSecurity.init()`

---

## Описание

Новый пользователь регистрируется в системе, получает JWT-токены, выполняет защищённый запрос, затем выходит.

---

## Pipeline

```
[Клиент]                          [Auth Server]                    [In-Memory Storage]
    │                                   │                                  │
    │── AqSecurity.init(config) ───────►│                                  │
    │◄─ AQSecurityService ─────────────│                                  │
    │                                   │                                  │
    │── service.register(email,pwd) ───►│                                  │
    │                                   │── IUserRepository.findByEmail ──►│
    │                                   │◄─ null (не существует) ──────────│
    │                                   │── PasswordService.hash(pwd) ─────│
    │                                   │── IUserRepository.create(user) ──►│
    │                                   │── ISessionRepository.create ─────►│
    │                                   │── TokenIssuer.issue(user,session)─│
    │◄─ AuthResponse(tokens, user) ────│                                  │
    │                                   │                                  │
    │── service.hasPermission(perm) ───►│ (local check via claims)         │
    │◄─ true/false ────────────────────│                                  │
    │                                   │                                  │
    │── service.logout() ──────────────►│                                  │
    │                                   │── ISessionRepository.revoke ─────►│
    │◄─ void ──────────────────────────│                                  │
```

---

## Клиентский userflow

1. Приложение стартует → `AqSecurity.init(config)` инициализирует все три синглтона
2. Пользователь заполняет форму регистрации
3. `service.register(email, password, displayName)` → `AuthResponse`
4. Токены сохраняются в `LocalSessionStore`
5. `service.currentUser` → `AqUser` (доступен без сети)
6. `service.hasPermission('projects:read')` → `true/false`
7. Пользователь нажимает "Выйти" → `service.logout()`
8. Состояние → `SecurityStateUnauthenticated`

## Серверный workflow

1. `POST /auth/register` → `AuthRouter._register()`
2. Валидация email + пароля
3. `IUserRepository.findByEmail` → проверка уникальности
4. `PasswordService.hash(password)` → bcrypt hash
5. `IUserRepository.create(AqUser)` → сохранить
6. `ISessionRepository.create(AqSession)` → создать сессию
7. `TokenIssuer.issue(user, session)` → JWT access + refresh
8. Вернуть `AuthResponse`

---

## Состояния

| Состояние | Тип |
|-----------|-----|
| Начало | `SecurityStateUnauthenticated` |
| Загрузка | `SecurityStateLoading` |
| Успех | `SecurityStateAuthenticated(user, tenant, claims)` |
| Ошибка | `SecurityStateError(message)` |
| После logout | `SecurityStateUnauthenticated` |

---

## In-memory реализация

Использует `InMemoryUserRepository`, `InMemorySessionRepository`.  
Токены верифицируются локально через `TokenValidator` с тестовым секретом.
