# AQ Security — Production Readiness Plan

> **Версия:** 1.0  
> **Дата:** 2026-04-09  
> **Основание:** Технический аудит пакетов `aq_security` и `aq_schema`  
> **Цель:** Полностью рабочий auth-стек в контейнерах с поддержкой Google OAuth, GitHub OAuth, Email/Password, API-ключей, системы ролей, защиты ресурсов и клиентской интеграции

---

## Содержание

1. [Архитектурная карта системы](#1-архитектурная-карта-системы)
2. [Модель клиента: ресурс и потребитель](#2-модель-клиента-ресурс-и-потребитель)
3. [Фазы выхода в production](#3-фазы-выхода-в-production)
4. [Фаза 0 — Блокеры и хотфиксы](#фаза-0--блокеры-и-хотфиксы-спринт-1-дни-1–3)
5. [Фаза 1 — Auth-провайдеры](#фаза-1--auth-провайдеры-спринт-1-дни-3–7)
6. [Фаза 2 — API Keys и Token Management](#фаза-2--api-keys-и-token-management-спринт-2)
7. [Фаза 3 — RBAC и защита ресурсов](#фаза-3--rbac-и-защита-ресурсов-спринт-2–3)
8. [Фаза 4 — Security Hardening](#фаза-4--security-hardening-спринт-3)
9. [Фаза 5 — Клиентская интеграция](#фаза-5--клиентская-интеграция-спринт-3–4)
10. [Фаза 6 — Инфраструктура и Docker-стек](#фаза-6--инфраструктура-и-docker-стек-спринт-4)
11. [Требования к тестированию](#требования-к-тестированию)
12. [Требования к документации](#требования-к-документации)
13. [Definition of Done](#definition-of-done)
14. [Сводный чеклист](#сводный-чеклист)

---

## 1. Архитектурная карта системы

```
┌─────────────────────────────────────────────────────────────────────┐
│                        CLIENT APPLICATIONS                          │
│                                                                     │
│   Flutter App         Dart Worker / Agent       External Service    │
│   (Human User)        (Machine Client)          (API Consumer)      │
│       │                      │                        │             │
│       └──────────────────────┼────────────────────────┘             │
│                              │                                      │
│                    AQSecurityClient.init()                          │
│                    AQSecurityService (SDK)                          │
└──────────────────────────────┼──────────────────────────────────────┘
                               │  HTTPS
                               ▼
┌─────────────────────────────────────────────────────────────────────┐
│                        AQ AUTH SERVICE  :8080                       │
│                                                                     │
│  /auth/login           /auth/refresh        /auth/validate          │
│  /auth/logout          /auth/me             /auth/sessions          │
│  /auth/api-keys        /rbac/*              /api/introspect         │
│                                                                     │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌───────────────────┐  │
│  │ Google   │  │ GitHub   │  │  Email/  │  │  ApiKeyService    │  │
│  │ OAuth2   │  │ OAuth2   │  │ Password │  │  TokenIssuer      │  │
│  └──────────┘  └──────────┘  └──────────┘  └───────────────────┘  │
│                                                                     │
│  ┌─────────────────────────────────────────────────────────────┐   │
│  │              AccessControlEngine (RBAC)                     │   │
│  │  Roles → Permissions → Wildcards → Policies → Cache        │   │
│  └─────────────────────────────────────────────────────────────┘   │
└──────────────────────────────┬──────────────────────────────────────┘
                               │  Internal network
                               ▼
┌─────────────────────────────────────────────────────────────────────┐
│                   AQ AUTH DATA SERVICE  :8090                       │
│                                                                     │
│   VaultRegistry → PostgresVaultStorage → PostgreSQL                │
│                                                                     │
│   Collections: users, tenants, sessions, api_keys, roles,          │
│                user_roles, rbac_roles, rbac_policies,               │
│                rbac_access_logs, profiles                           │
└──────────────────────────────┬──────────────────────────────────────┘
                               │
                               ▼
                        PostgreSQL :5432
                        Redis      :6379  (cache, rate limit)
```

### Принцип взаимодействия Resource Server

```
Resource Client (e.g. aq_studio_data_service)
        │
        │  GET /projects/123
        │  Authorization: Bearer <access_token>
        ▼
Resource Server Middleware
        │
        │  POST /api/introspect
        │  { token, resource: "projects", action: "read", resourceId: "123" }
        ▼
AQ Auth Service → IntrospectionRouter → AccessControlEngine
        │
        │  { active: true, allowed: true/false, userId, tenantId, scopes }
        ▼
Resource Server → allow or 403
```

---

## 2. Модель клиента: ресурс и потребитель

Система поддерживает две роли клиента одновременно. Понимание этого
критически важно для правильной настройки RBAC и защиты ресурсов.

### 2.1. Клиент как ПОТРЕБИТЕЛЬ (Consumer)

Клиент хочет получить доступ к чужому ресурсу или выполнить действие.

| Тип клиента | Механизм auth | Пример |
|---|---|---|
| Пользователь-человек | Google OAuth / GitHub OAuth / Email+Password | Flutter-приложение, веб-дашборд |
| Машинный клиент / агент | API Key (aq_live_...) | Worker, внешний сервис, CI/CD |
| Сервис платформы | Service Account + JWT | Воркер внутри платформы |

**Инициализация (потребитель):**
```dart
// Человек
final service = await AQSecurityClient.init('https://auth.example.com');
await service.loginWithGoogle(code: oauthCode, redirectUri: redirectUri);

// Машина
final service = await AQSecurityClient.init(
  Platform.environment['AUTH_URL']!,
  jwtSecret: Platform.environment['JWT_SECRET'],
);
await service.loginWithApiKey(Platform.environment['API_KEY']!);
```

### 2.2. Клиент как РЕСУРС (Resource Server)

Клиент защищает свои данные, делегируя проверку Auth Service через introspection.

**Схема реализации:**
```dart
// В Resource Server (например, aq_studio_data_service)
final introspect = IntrospectionClient(
  introspectionEndpoint: 'https://auth.example.com/api/introspect',
);

// Middleware на каждый запрос
Future<bool> checkAccess(String token, String resource, String action, String id) async {
  final result = await introspect.introspect(
    token: token,
    resource: resource,    // 'projects'
    action: action,        // 'read' | 'write' | 'delete'
    resourceId: id,
  );
  return result.active && result.allowed;
}
```

**Регистрация ресурса:**
```dart
// Ресурс декларирует себя в RBAC при старте
await rbacClient.registerResource(ResourceDefinition(
  type: 'projects',
  actions: ['read', 'write', 'delete', 'share'],
  scopes: ['own', 'tenant', 'public'],
));
```

---

## 3. Фазы выхода в production

| Фаза | Содержание | Дней | Блокирует |
|---|---|---|---|
| **0** | Хотфиксы безопасности (блокеры из аудита) | 1–3 | Всё |
| **1** | Auth-провайдеры: Google, GitHub, Email/Password | 4–7 | Фазы 2–5 |
| **2** | API Keys, Token lifecycle, Refresh flow | 5–8 | Фазы 3, 5 |
| **3** | RBAC: роли, права, политики, защита ресурсов | 6–9 | Фаза 5 |
| **4** | Security hardening: rate limit, headers, secrets | 3–5 | Production |
| **5** | Клиентская интеграция SDK | 4–6 | Production |
| **6** | Инфраструктура: Docker, CI/CD, мониторинг, backup | 4–6 | Production |

**Итого: ~27–44 рабочих дня до полного production**  
*(при работе 1 разработчика; параллельная работа 2–3 человек сокращает до ~15–20 дней)*

---

## Фаза 0 — Блокеры и хотфиксы (Спринт 1, Дни 1–3)

> ⛔ **Ни один коммит в main не проходит без выполнения этой фазы.**

### Задача 0.1 — Удалить backdoor `test_api_key`

**Файл:** `pkgs/aq_security/lib/src/server/api_key_service.dart`

**Что сделать:**
- Удалить блок `if (rawKey == 'test_api_key') { ... }` полностью
- Заменить на правильную тестовую инфраструктуру:

```dart
// ВМЕСТО ЭТОГО — использовать окружение
// В тестах: передавать InMemoryApiKeyRepository вместо реального
// Тестовые ключи генерировать через тот же ApiKeyService.create(isTest: true)
```

**Проверка выполнения:**
- `grep -r "test_api_key" lib/` возвращает 0 результатов
- unit-тест: попытка авторизации со строкой `test_api_key` возвращает `null`

**Документация:** Добавить в `SECURITY.md` раздел «Тестирование без backdoor»

---

### Задача 0.2 — Исправить CORS

**Файл:** `pkgs/aq_security/lib/src/server/aq_auth_server.dart`

**Что сделать:**
```dart
// БЫЛО:
static const _corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  ...
};

// СТАЛО:
Middleware _corsMiddleware(List<String> allowedOrigins) {
  return createMiddleware(
    requestHandler: (req) {
      final origin = req.headers['origin'] ?? '';
      if (req.method == 'OPTIONS') {
        return Response.ok('', headers: _buildCorsHeaders(origin, allowedOrigins));
      }
      return null;
    },
    responseHandler: (res) {
      final origin = res.request?.headers['origin'] ?? '';
      return res.change(headers: _buildCorsHeaders(origin, allowedOrigins));
    },
  );
}

Map<String, String> _buildCorsHeaders(String origin, List<String> allowed) {
  final isAllowed = allowed.contains(origin) || allowed.contains('*');
  return {
    'Access-Control-Allow-Origin': isAllowed ? origin : '',
    'Access-Control-Allow-Methods': 'GET, POST, DELETE, OPTIONS',
    'Access-Control-Allow-Headers': 'Authorization, Content-Type',
    'Access-Control-Allow-Credentials': 'true',
    'Vary': 'Origin',
  };
}
```

**Конфиг:**
```yaml
# docker-compose.yml
auth_service:
  environment:
    ALLOWED_ORIGINS: "https://app.example.com,https://admin.example.com"
```

```dart
// SecurityConfig
final allowedOrigins = Platform.environment['ALLOWED_ORIGINS']
    ?.split(',')
    .map((e) => e.trim())
    .toList() ?? [];
```

---

### Задача 0.3 — Заменить `_generateId()` на UUID

**Затронутые файлы:**
- `rbac_service.dart`
- `alert_generator.dart`
- `access_control_engine.dart`
- `vault_security_repositories.dart`

```dart
// БЫЛО:
String _generateId() =>
    DateTime.now().millisecondsSinceEpoch.toString()
    + '_' + (DateTime.now().microsecond % 1000).toString();

// СТАЛО:
import 'package:uuid/uuid.dart';
static const _uuid = Uuid();
String _generateId() => _uuid.v4();
```

**Проверка:** `grep -rn "_generateId" lib/` — каждое вхождение использует `uuid.v4()`

---

### Задача 0.4 — Починить `systemRoles` seeding

**Файл:** `pkgs/aq_security/lib/src/server/aq_auth_server.dart`

**Что сделать:**
1. Исправить `query` operation в `VaultRegistry` (конкретная ошибка задокументирована в `BRUTAL_AUDIT.md`)
2. Раскомментировать `await _userService.seedSystemRoles()`
3. Добавить идемпотентность: если роли уже существуют — пропустить

```dart
Future<void> seedSystemRoles() async {
  for (final role in SystemRoles.all) {
    final existing = await _roles.findByName(role.name, tenantId: null);
    if (existing != null) continue; // идемпотентно
    await _roles.save(role, actorId: 'system');
    print('[Seed] Created system role: ${role.name}');
  }
}
```

**Системные роли (минимальный набор):**
```dart
// pkgs/aq_schema/lib/security/rbac/system_roles.dart
class SystemRoles {
  static final all = [
    AqRole(name: 'superadmin',  permissions: ['*:*:*']),
    AqRole(name: 'admin',       permissions: ['users:*:tenant', 'roles:*:tenant', 'projects:*:tenant']),
    AqRole(name: 'member',      permissions: ['projects:read:tenant', 'projects:write:own']),
    AqRole(name: 'viewer',      permissions: ['projects:read:tenant']),
    AqRole(name: 'service',     permissions: ['introspect:call:*']),   // для Resource Server
    AqRole(name: 'api_consumer',permissions: ['projects:read:public']),
  ];
}
```

---

### Задача 0.5 — Унифицировать названия коллекций

**Проблема:** Код ищет роли в `rbac_roles`, данные лежат в `security_roles`

```dart
// pkgs/aq_schema/lib/security/storable/security_domains.dart
// Единственный источник истины — константы:
class SecurityCollections {
  static const users      = 'security_users';
  static const tenants    = 'security_tenants';
  static const sessions   = 'security_sessions';
  static const apiKeys    = 'security_api_keys';
  static const roles      = 'security_roles';       // ← везде одно значение
  static const userRoles  = 'security_user_roles';
  // RBAC
  static const rbacRoles    = 'rbac_roles';         // ← если отдельная коллекция
  static const rbacPolicies = 'rbac_policies';
  static const rbacLogs     = 'rbac_access_logs';
}
```

**Правило:** Нигде в коде не должно быть строковых литералов с именами коллекций. Только `SecurityCollections.xxx`.

---

### Задача 0.6 — Исправить суффикс LoggedStorable (`_log` vs `__log`)

**Проблема:** `rbac_access_logs__log` не существует, реальная таблица `rbac_access_logs_log`

```dart
// Найти конвенцию в dart_vault/LoggedStorable и строго следовать ей
// Зафиксировать в ARCHITECTURE.md: "LoggedStorable добавляет суффикс _log"
```

**Проверка:** тест Step 7 (RBAC access logs) проходит без ошибки 500.

---

### 📄 Документация Фазы 0

| Артефакт | Содержание |
|---|---|
| `SECURITY.md` | Политика безопасности: нет backdoor, нет хардкода секретов, обязательный code review |
| `CHANGELOG.md` | Запись о хотфиксах с указанием CVE-класса каждой проблемы |
| `ADR/001-no-wildcard-cors.md` | Архитектурное решение по CORS |
| `ADR/002-uuid-for-ids.md` | Обоснование перехода на UUID |

---

## Фаза 1 — Auth-провайдеры (Спринт 1, Дни 3–7)

### Задача 1.1 — Завершить Google OAuth

**Статус по аудиту:** Код существует, redirect URIs не настроены, нет error handling

**Что сделать:**

**a) Настроить Google Console:**
```
Authorized redirect URIs:
  https://auth.example.com/auth/oauth/google/callback
  http://localhost:8080/auth/oauth/google/callback  (dev)
```

**b) Добавить callback endpoint:**
```dart
// auth_router.dart
router.get('/oauth/google/callback', (Request req) async {
  final code = req.url.queryParameters['code'];
  final state = req.url.queryParameters['state']; // CSRF protection
  final error = req.url.queryParameters['error'];

  if (error != null) {
    // access_denied, invalid_scope, etc.
    return _redirectWithError(error);
  }

  // Валидация CSRF state
  if (!await _csrfStore.validate(state)) {
    return Response.forbidden('Invalid state parameter');
  }

  final response = await _handleLogin(GoogleOAuthCredentials(
    code: code!,
    redirectUri: '${config.baseUrl}/auth/oauth/google/callback',
  ));

  // Redirect обратно в приложение с токенами
  return Response.found('${config.appUrl}/auth/success?token=${response.tokens.accessToken}');
});
```

**c) PKCE для мобильных клиентов (обязательно для Flutter):**
```dart
// Клиент генерирует code_verifier → code_challenge (S256)
// Сервер проверяет code_verifier при обмене code → token
// Без PKCE мобильный OAuth уязвим к перехвату кода
```

**d) Обработать refresh token от Google:**
```dart
// Google выдаёт refresh_token только при первой авторизации
// Хранить в зашифрованном виде в profiles таблице
// Использовать для silent refresh Google-сессии
```

---

### Задача 1.2 — Добавить GitHub OAuth

**Что нового (GitHub vs Google):**
```dart
// pkgs/aq_security/lib/src/server/github_oauth_service.dart
class GitHubOAuthService {
  // GitHub использует другой endpoint для user info
  // GitHub не возвращает id_token (нет OpenID Connect)
  // Email может быть скрыт — нужен отдельный запрос /user/emails

  Future<GitHubUserInfo> getUserInfo(String accessToken) async {
    final user = await _get('https://api.github.com/user', accessToken);
    // Если email == null, запросить отдельно:
    final emails = await _get('https://api.github.com/user/emails', accessToken);
    final primary = emails.firstWhere((e) => e['primary'] == true);
    return GitHubUserInfo(
      id: user['id'].toString(),
      email: primary['email'],
      name: user['name'],
      avatarUrl: user['avatar_url'],
    );
  }
}
```

**Конфиг (env):**
```env
GITHUB_CLIENT_ID=...
GITHUB_CLIENT_SECRET=...
GITHUB_CALLBACK_URL=https://auth.example.com/auth/oauth/github/callback
```

**Обновить Credentials:**
```dart
// aq_schema/lib/security/models/credentials.dart
class GitHubOAuthCredentials extends Credentials {
  final String code;
  final String redirectUri;
  final String? state;
  String get type => 'github_oauth';
}
```

---

### Задача 1.3 — Email/Password Auth

> Несмотря на то что Google и GitHub являются основными провайдерами, Email/Password нужен для admin-аккаунтов, service accounts и сценариев без OAuth.

**a) Хэширование паролей — только Argon2id:**
```dart
// pubspec.yaml: argon2_ffi или pointycastle
// НЕ использовать: MD5, SHA-1, SHA-256 без соли, bcrypt (слабее Argon2)

class PasswordService {
  static const _argon2 = Argon2(
    iterations: 3,
    parallelism: 4,
    memorySize: 65536, // 64 MB — OWASP рекомендация
    hashLength: 32,
    saltLength: 16,
    type: Argon2Type.id,
  );

  Future<String> hash(String password) async {
    final salt = _generateSalt(16);
    final hash = await _argon2.hashPasswordString(password, salt: salt);
    return hash.encodedString; // хранить в encoded формате
  }

  Future<bool> verify(String password, String encodedHash) async {
    return await _argon2.verifyHashedPassword(
      encodedHash: encodedHash,
      password: password,
    );
  }
}
```

**b) Защита от timing attacks:**
```dart
// Всегда выполнять хэш, даже если пользователь не найден:
Future<AuthResponse?> loginWithEmail(String email, String password) async {
  final user = await _users.findByEmail(email);
  final dummyHash = _dummyHashForTimingProtection;

  final isValid = user != null
      ? await _passwords.verify(password, user.passwordHash!)
      : await _passwords.verify(password, dummyHash); // timing protection

  if (user == null || !isValid) {
    throw AuthException('Invalid credentials'); // одно сообщение для обоих случаев
  }
  return _buildAuthResponse(user);
}
```

**c) Email verification flow:**
```dart
// При регистрации:
// 1. Создать user с isEmailVerified: false
// 2. Отправить verification email с signed token (JWT, TTL 24h)
// 3. GET /auth/verify-email?token=... → верифицировать и активировать
// 4. Заблокировать login если !isEmailVerified (кроме resend verification)
```

**d) Password reset flow (обязательно):**
```dart
// POST /auth/forgot-password { email }
// → создать signed reset token (JWT, TTL 1h, одноразовый)
// → отправить email
// POST /auth/reset-password { token, newPassword }
// → валидировать token, хэшировать пароль, инвалидировать все сессии
```

---

### Задача 1.4 — Унифицированный AuthRouter

```dart
// Единая точка входа для всех провайдеров
// POST /auth/login
// Body: { "type": "google_oauth" | "github_oauth" | "email_password" | "api_key", ...credentials }

router.post('/login', (Request req) async {
  final body = await req.readAsJson();
  final credentials = Credentials.fromJson(body);

  return switch (credentials) {
    GoogleOAuthCredentials c  => _handleGoogle(c),
    GitHubOAuthCredentials c  => _handleGitHub(c),
    EmailPasswordCredentials c => _handleEmail(c),
    ApiKeyCredentials c       => _handleApiKey(c),
    _ => Response(400, body: '{"error":"unknown_credentials_type"}'),
  };
});
```

---

### 📄 Документация Фазы 1

| Артефакт | Содержание |
|---|---|
| `doc/AUTH_PROVIDERS.md` | Как добавить нового OAuth провайдера (паттерн) |
| `doc/EMAIL_AUTH.md` | Email verification, password reset, security policy |
| `doc/OAUTH_FLOWS.md` | Диаграммы sequence для каждого provider |
| `ADR/003-argon2id-passwords.md` | Обоснование выбора Argon2id |
| `ADR/004-pkce-mobile.md` | Обязательность PKCE для Flutter-клиентов |
| `openapi/auth.yaml` | OpenAPI 3.0 спецификация всех /auth/* endpoints |

---

## Фаза 2 — API Keys и Token Management (Спринт 2)

### Задача 2.1 — Полноценный жизненный цикл API-ключей

**Статус по аудиту:** Основа есть, `lastUsedAt` обновляется через TODO

**Что доделать:**

```dart
// a) Tracking lastUsedAt — убрать TODO, реализовать:
Future<AqApiKey?> validate(String rawKey) async {
  // ... существующая валидация ...
  // Обновить lastUsedAt атомарно:
  await repo.updateLastUsed(record.id, _now());
  return record;
}

// b) Expiry с grace period:
bool get isExpired {
  if (expiresAt == null) return false;
  // 5-минутный grace period для clock skew
  return _now() > expiresAt! + 300;
}

// c) Scoped API Keys — ключ создаётся с минимальным набором прав:
Future<({String rawKey, AqApiKey record})> create({
  required String userId,
  required String tenantId,
  required String name,
  required List<String> permissions, // минимально необходимые
  String? description,
  int? expiresAt,
  Map<String, String>? metadata,     // для аудита: назначение ключа
  bool isTest = false,
}) async { ... }
```

**d) Endpoint для просмотра и управления:**
```
POST   /auth/api-keys              создать
GET    /auth/api-keys              список (без keyHash!)
GET    /auth/api-keys/:id          детали
DELETE /auth/api-keys/:id          отозвать
POST   /auth/api-keys/:id/rotate   ротировать
GET    /auth/api-keys/:id/usage    статистика использования
```

---

### Задача 2.2 — Token lifecycle (Access + Refresh)

**a) Refresh Token Rotation (обязательно):**
```dart
// При каждом refresh:
// 1. Старый refresh token → инвалидировать немедленно
// 2. Выдать новую пару access + refresh
// 3. Если старый refresh token приходит повторно → признак компрометации
//    → инвалидировать ВСЕ refresh tokens пользователя
//    → уведомить пользователя по email

Future<TokenPair> refresh(String refreshToken) async {
  final session = await _sessions.findByRefreshToken(_hash(refreshToken));
  if (session == null || session.isRevoked) {
    // Возможная компрометация — инвалидировать всё
    if (session?.isRevoked == true) {
      await _sessions.revokeAllForUser(session.userId);
      await _alertGenerator.generateTokenReuseAlert(session.userId);
    }
    throw AuthException('Invalid refresh token');
  }
  // Rotation
  await _sessions.revoke(session.id);
  return await _issueNewPair(session.userId, session.tenantId);
}
```

**b) Token claims (обогащённые):**
```dart
// JWT payload должен содержать:
{
  "sub": "user_id",
  "tid": "tenant_id",           // tenant
  "sid": "session_id",          // для отзыва
  "perms": ["projects:read:*"], // эффективные права
  "roles": ["member"],          // роли (для информации)
  "iss": "https://auth.example.com",
  "aud": ["aq_studio"],
  "iat": 1700000000,
  "exp": 1700003600,
  "jti": "unique_token_id"      // для blacklist
}
```

**c) Token revocation (blacklist для access tokens):**
```dart
// Access tokens живут 1 час. Blacklist через Redis с TTL = оставшееся время токена.
// При logout: добавить jti в Redis SET revoked_tokens с TTL
// При validate: проверить Redis перед decode

class TokenBlacklist {
  Future<void> revoke(String jti, int expiresAt) async {
    final ttl = expiresAt - _now();
    if (ttl > 0) await _redis.setex('revoked:$jti', ttl, '1');
  }
  Future<bool> isRevoked(String jti) async {
    return await _redis.exists('revoked:$jti') > 0;
  }
}
```

---

### Задача 2.3 — JWT Security

```dart
// a) Алгоритм: RS256 вместо HS256 (рекомендуется для production)
// RS256: приватный ключ подписывает, публичный проверяет
// Публичный ключ можно раздавать всем Resource Servers без риска
// HS256 приемлем если JWT_SECRET не покидает auth service

// b) JWKS endpoint (для RS256):
// GET /auth/.well-known/jwks.json
// → публичные ключи для верификации Resource Servers

// c) Key rotation без downtime:
// Поддерживать 2 ключевые пары: current + previous
// kid (key ID) в JWT header указывает какой ключ использован
// Rotation: текущий → предыдущий, новый → текущий
```

---

### 📄 Документация Фазы 2

| Артефакт | Содержание |
|---|---|
| `doc/API_KEYS.md` | Как создавать, ротировать, отзывать. Best practices для workers |
| `doc/TOKEN_LIFECYCLE.md` | Схема жизненного цикла токенов, TTL, rotation, revocation |
| `doc/JWT_SECURITY.md` | Алгоритм, claims, JWKS, key rotation |
| `ADR/005-refresh-token-rotation.md` | Почему rotation обязателен |
| `ADR/006-redis-token-blacklist.md` | Обоснование Redis для blacklist |

---

## Фаза 3 — RBAC и защита ресурсов (Спринт 2–3)

### Задача 3.1 — Завершить RBAC систему

**Статус по аудиту:** Архитектура хорошая, но seeding сломан, метрики заглушки

**a) Модель прав (Permission format):**
```
resource:action:scope

resource = users | projects | workflows | agents | api_keys | roles | tenants | *
action   = read | write | delete | share | manage | * 
scope    = own | tenant | platform | *

Примеры:
  projects:read:tenant   — читать проекты в своём тенанте
  users:manage:platform  — управлять пользователями на уровне платформы
  *:*:*                  — superadmin
  projects:*:own         — всё со своими проектами
```

**b) Иерархия ролей (обеспечить работу inheritsFrom):**
```
superadmin
    └── admin
         ├── member
         │    └── viewer
         └── service
              └── api_consumer
```

**c) Временные роли (уже есть в модели, нужна очистка):**
```dart
// Фоновый job для очистки истёкших временных ролей
// Запускать каждые 15 минут через Timer.periodic
Future<void> _purgeExpiredRoles() async {
  final expired = await _userRoles.findExpired(
    before: DateTime.now().millisecondsSinceEpoch,
  );
  for (final role in expired) {
    await _userRoles.revoke(role.userId, role.roleId);
    await _engine.invalidateUserCache(role.userId);
    print('[RBAC] Purged expired role: ${role.roleId} for user ${role.userId}');
  }
}
```

**d) Context-based policies (расширение существующих):**
```dart
// Добавить условие tenant_owner:
// Доступ только если userId == tenant.ownerId
case 'tenant_owner':
  final tenant = await _tenants.findById(context.tenantId!);
  return tenant?.ownerId == context.userId;

// Добавить условие resource_owner:
// Доступ только к своим ресурсам
case 'resource_owner':
  final resource = await _resources.findById(context.resourceId!);
  return resource?.ownerId == context.userId;
```

---

### Задача 3.2 — Resource Server Integration

**a) Middleware для любого Resource Server:**
```dart
// pkgs/aq_security/lib/src/server/middleware/resource_auth_middleware.dart
Middleware resourceAuthMiddleware({
  required IntrospectionClient introspect,
  required ResourceConfig config, // какие маршруты как проверять
}) {
  return (Handler inner) {
    return (Request request) async {
      final token = _extractBearer(request);
      if (token == null) return Response.unauthorized('...');

      // Определить resource + action из маршрута
      final check = config.resolve(request.method, request.url.path);
      if (check == null) return inner(request); // публичный маршрут

      final result = await introspect.introspect(
        token: token,
        resource: check.resource,
        action: check.action,
        resourceId: check.extractId(request),
      );

      if (!result.active) return Response.unauthorized('Token expired');
      if (!result.allowed) return Response.forbidden('Insufficient permissions');

      // Добавить user context в request для handler'ов
      return inner(request.change(context: {
        'userId': result.userId,
        'tenantId': result.tenantId,
        'scopes': result.scopes,
      }));
    };
  };
}
```

**b) ResourceConfig — декларативное описание защиты:**
```dart
final config = ResourceConfig([
  ResourceRoute('GET',    '/projects',      'projects', 'read'),
  ResourceRoute('POST',   '/projects',      'projects', 'write'),
  ResourceRoute('GET',    '/projects/:id',  'projects', 'read',  idParam: 'id'),
  ResourceRoute('PUT',    '/projects/:id',  'projects', 'write', idParam: 'id'),
  ResourceRoute('DELETE', '/projects/:id',  'projects', 'delete',idParam: 'id'),
  ResourceRoute('GET',    '/health',        null, null), // публичный
]);
```

---

### Задача 3.3 — Реализовать метрики RBAC

**Статус по аудиту:** `_getMetrics()` в `rbac_router.dart` — пустая заглушка

```dart
// GET /rbac/metrics
Future<Response> _getMetrics(Request req) async {
  final metrics = await _metricsAggregator.aggregate(
    from: DateTime.now().subtract(Duration(hours: 1)),
    to: DateTime.now(),
  );
  return Response.ok(jsonEncode({
    'period': '1h',
    'total_checks': metrics.totalChecks,
    'allowed': metrics.allowed,
    'denied': metrics.denied,
    'cache_hit_rate': metrics.cacheHitRate,
    'avg_latency_ms': metrics.avgLatencyMs,
    'p99_latency_ms': metrics.p99LatencyMs,
    'top_denied_resources': metrics.topDenied,
    'active_users': metrics.activeUsers,
  }));
}
```

---

### 📄 Документация Фазы 3

| Артефакт | Содержание |
|---|---|
| `doc/RBAC_GUIDE.md` | Полное руководство по RBAC: роли, права, политики, примеры |
| `doc/RESOURCE_SERVER.md` | Как подключить Resource Server за 15 минут |
| `doc/PERMISSION_REFERENCE.md` | Полный справочник permissions по ресурсам |
| `doc/RBAC_POLICIES.md` | Как создавать context-based политики |
| `openapi/rbac.yaml` | OpenAPI спецификация /rbac/* endpoints |
| `openapi/introspect.yaml` | OpenAPI спецификация /api/introspect |

---

## Фаза 4 — Security Hardening (Спринт 3)

### Задача 4.1 — Rate Limiting

```dart
// pkgs/aq_security/lib/src/server/middleware/rate_limit_middleware.dart

// Использовать Redis (sliding window algorithm)
class RateLimiter {
  // Лимиты по эндпоинту:
  static const limits = {
    '/auth/login':          RateLimit(requests: 10,  window: Duration(minutes: 1)),
    '/auth/refresh':        RateLimit(requests: 30,  window: Duration(minutes: 1)),
    '/auth/forgot-password':RateLimit(requests: 3,   window: Duration(minutes: 15)),
    '/auth/register':       RateLimit(requests: 5,   window: Duration(minutes: 1)),
    '/auth/api-keys':       RateLimit(requests: 10,  window: Duration(minutes: 1)),
    '/rbac/*':              RateLimit(requests: 100, window: Duration(minutes: 1)),
    'default':              RateLimit(requests: 200, window: Duration(minutes: 1)),
  };

  // Ключ: IP + endpoint (для неавторизованных)
  //       userId + endpoint (для авторизованных — строже)
}

// Ответ при превышении:
// HTTP 429 Too Many Requests
// Headers: Retry-After: 60, X-RateLimit-Limit: 10, X-RateLimit-Remaining: 0
```

---

### Задача 4.2 — Security Headers

```dart
// pkgs/aq_security/lib/src/server/middleware/security_headers_middleware.dart
Middleware securityHeadersMiddleware() {
  return createMiddleware(responseHandler: (res) => res.change(headers: {
    'Strict-Transport-Security': 'max-age=63072000; includeSubDomains; preload',
    'X-Content-Type-Options': 'nosniff',
    'X-Frame-Options': 'DENY',
    'X-XSS-Protection': '1; mode=block',
    'Referrer-Policy': 'strict-origin-when-cross-origin',
    'Content-Security-Policy': "default-src 'self'",
    'Permissions-Policy': 'geolocation=(), microphone=()',
    'Cache-Control': 'no-store', // для auth endpoints
  }));
}
```

---

### Задача 4.3 — Secrets Management

**Запрещено** хранить в `.env` (передаётся в git history):
- `JWT_SECRET`
- `GOOGLE_CLIENT_SECRET`
- `GITHUB_CLIENT_SECRET`
- `POSTGRES_PASSWORD`
- Любые private keys

**Правильная схема:**
```bash
# Для dev: .env в .gitignore, никогда в репо
# Для staging/prod: внешний Secrets Manager

# Вариант 1: HashiCorp Vault (self-hosted)
vault kv put secret/aq-auth JWT_SECRET=... GOOGLE_CLIENT_SECRET=...

# Вариант 2: Infisical (open-source, проще)
infisical secrets --env=prod

# Вариант 3: AWS/GCP Secrets Manager
# Вариант 4: Docker Swarm Secrets / Kubernetes Secrets (зашифрованные)
```

```dart
// При старте сервиса — читать секреты:
final jwtSecret = await SecretsManager.get('JWT_SECRET');
// НЕ из Platform.environment напрямую в production
```

---

### Задача 4.4 — Database Security

```sql
-- a) Foreign Keys (добавить через миграцию):
ALTER TABLE security_user_roles
  ADD CONSTRAINT fk_ur_user
  FOREIGN KEY (user_id) REFERENCES security_users(id) ON DELETE CASCADE;

ALTER TABLE security_user_roles
  ADD CONSTRAINT fk_ur_role
  FOREIGN KEY (role_id) REFERENCES security_roles(id) ON DELETE RESTRICT;

ALTER TABLE security_sessions
  ADD CONSTRAINT fk_sess_user
  FOREIGN KEY (user_id) REFERENCES security_users(id) ON DELETE CASCADE;

-- b) Row-level security (PostgreSQL RLS) для multi-tenancy:
ALTER TABLE security_users ENABLE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation ON security_users
  USING (tenant_id = current_setting('app.tenant_id')::text);

-- c) Отдельный DB-пользователь с минимальными правами:
CREATE USER aq_auth_app WITH PASSWORD '...';
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO aq_auth_app;
REVOKE ALL ON SCHEMA public FROM PUBLIC;
```

---

### Задача 4.5 — Input Validation

```dart
// Добавить валидацию для всех входящих данных:
class AuthRequestValidator {
  static ValidationResult validateEmail(String email) {
    if (!RegExp(r'^[^@]+@[^@]+\.[^@]+$').hasMatch(email)) {
      return ValidationResult.error('Invalid email format');
    }
    if (email.length > 254) return ValidationResult.error('Email too long');
    return ValidationResult.ok();
  }

  static ValidationResult validatePassword(String password) {
    if (password.length < 8) return ValidationResult.error('Password too short');
    if (password.length > 128) return ValidationResult.error('Password too long');
    return ValidationResult.ok();
  }

  static ValidationResult validatePermission(String perm) {
    // resource:action:scope format
    final parts = perm.split(':');
    if (parts.length != 3) return ValidationResult.error('Invalid permission format');
    return ValidationResult.ok();
  }
}
```

---

### 📄 Документация Фазы 4

| Артефакт | Содержание |
|---|---|
| `doc/SECURITY_RUNBOOK.md` | Что делать при инциденте безопасности |
| `doc/SECRETS_MANAGEMENT.md` | Как управлять секретами в dev/staging/prod |
| `doc/DB_SECURITY.md` | FK, RLS, users, backup |
| `SECURITY.md` (обновить) | Добавить rate limits, headers, disclosure policy |
| `ADR/007-rls-multitenancy.md` | PostgreSQL RLS для изоляции тенантов |

---

## Фаза 5 — Клиентская интеграция (Спринт 3–4)

### Задача 5.1 — SDK: `AQSecurityClient` как полноценный инструментарий

При `init()` клиент должен получать готовые инструменты и для
**потребления** ресурсов и для **защиты** своих данных.

```dart
// НОВЫЙ публичный интерфейс SDK:
final client = await AQSecurityClient.init(
  authUrl: 'https://auth.example.com',
  options: SecurityClientOptions(
    jwtSecret: '...',          // для offline validation (workers)
    resourceType: 'projects',  // если клиент — Resource Server
    introspectionUrl: 'https://auth.example.com/api/introspect',
    autoRefresh: true,
    sessionPersistence: FlutterSecureStorageSessionStore(), // для Flutter
  ),
);

// Что получает клиент:
client.service          // AQSecurityService — auth, login, logout
client.rbac             // RBACClient — проверка прав текущего пользователя
client.apiKeys          // ApiKeyClient — управление своими ключами
client.sessions         // SessionClient — просмотр и отзыв сессий
client.resourceGuard    // ResourceGuard — защита ресурсов (если Resource Server)
```

---

### Задача 5.2 — RBACClient (клиентская проверка прав)

```dart
// Синхронная проверка (из JWT claims, без запроса):
final canRead = client.rbac.can('projects:read:tenant'); // bool

// Асинхронная проверка (через introspection, с политиками):
final decision = await client.rbac.canAsync(
  resource: 'projects',
  action: 'write',
  scope: 'tenant',
  resourceId: 'proj_123',
);
if (decision.allowed) { ... }

// Batch-проверка:
final permissions = await client.rbac.canBatch([
  'projects:read:tenant',
  'projects:write:own',
  'users:manage:tenant',
]);
// Map<String, bool>
```

---

### Задача 5.3 — ResourceGuard (клиент как Resource Server)

```dart
// Клиент защищает свои данные:
final guard = client.resourceGuard;

// В Shelf middleware:
final handler = const Pipeline()
    .addMiddleware(guard.middleware(config: ResourceConfig([
      ResourceRoute('GET',  '/projects',     'projects', 'read'),
      ResourceRoute('POST', '/projects',     'projects', 'write'),
      ResourceRoute('GET',  '/projects/:id', 'projects', 'read', idParam: 'id'),
    ])))
    .addHandler(myRouter);

// В любом другом контексте (Flutter, CLI):
final allowed = await guard.check(
  token: incomingToken,
  resource: 'documents',
  action: 'read',
  resourceId: 'doc_123',
);
```

---

### Задача 5.4 — Flutter Deep Link для OAuth

```dart
// Flutter: обработка OAuth callback через deep link
// Android: intent-filter в AndroidManifest.xml
// iOS: URL scheme в Info.plist

// lib/auth/oauth_deep_link_handler.dart
class OAuthDeepLinkHandler {
  static Stream<Uri> get stream => _linkStream;

  static Future<AuthResponse> handleGoogleSignIn() async {
    final state = _generateState();   // CSRF
    final codeVerifier = _generateCodeVerifier();  // PKCE
    final codeChallenge = _sha256(codeVerifier);

    // Открыть браузер
    final url = Uri.parse('https://auth.example.com/auth/oauth/google/start'
        '?state=$state&code_challenge=$codeChallenge');
    await launchUrl(url, mode: LaunchMode.externalApplication);

    // Дождаться callback
    final callbackUri = await stream.firstWhere(
        (uri) => uri.host == 'auth-callback' && uri.queryParameters['state'] == state);

    return await client.service.loginWithGoogle(
      code: callbackUri.queryParameters['code']!,
      redirectUri: 'aqstudio://auth-callback',
      codeVerifier: codeVerifier,
    );
  }
}
```

---

### Задача 5.5 — Secure Storage для Flutter

```dart
// Заменить LocalSessionStore на FlutterSecureStorageSessionStore:
class FlutterSecureStorageSessionStore implements ISessionStore {
  final _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );

  @override
  Future<TokenPair?> getStoredTokens() async {
    final data = await _storage.read(key: 'aq_session');
    if (data == null) return null;
    return TokenPair.fromJson(jsonDecode(data));
  }

  @override
  Future<void> saveTokens(TokenPair tokens) async {
    await _storage.write(key: 'aq_session', value: jsonEncode(tokens.toJson()));
  }

  @override
  Future<void> clear() async {
    await _storage.delete(key: 'aq_session');
  }
}
```

---

### 📄 Документация Фазы 5

| Артефакт | Содержание |
|---|---|
| `doc/CLIENT_INTEGRATION.md` | Quickstart для подключения SDK (Flutter, Dart CLI, Server) |
| `doc/RESOURCE_SERVER_QUICKSTART.md` | Защита своих данных за 15 минут |
| `doc/FLUTTER_OAUTH.md` | Deep links, PKCE, secure storage |
| `doc/WORKER_AUTH.md` | Аутентификация воркеров и агентов через API keys |
| `examples/flutter_app/` | Полноценный пример Flutter-приложения с auth |
| `examples/dart_worker/` | Пример воркера с API key auth |
| `examples/resource_server/` | Пример Resource Server на Shelf |
| `MIGRATION.md` | Как мигрировать с v0 на v1 API |

---

## Фаза 6 — Инфраструктура и Docker-стек (Спринт 4)

### Задача 6.1 — Production Docker Compose

```yaml
# docker-compose.prod.yml
version: '3.9'

services:

  postgres:
    image: postgres:16-alpine
    container_name: aq_postgres
    restart: unless-stopped
    environment:
      POSTGRES_DB: ${POSTGRES_DB:-aq_auth}
      POSTGRES_USER: ${POSTGRES_USER:-aq}
      POSTGRES_PASSWORD_FILE: /run/secrets/pg_password
    volumes:
      - pg_data:/var/lib/postgresql/data
      - ./scripts/init.sql:/docker-entrypoint-initdb.d/init.sql
    secrets:
      - pg_password
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U ${POSTGRES_USER:-aq}"]
      interval: 10s
      timeout: 5s
      retries: 5
    networks:
      - auth_internal

  redis:
    image: redis:7-alpine
    container_name: aq_redis
    restart: unless-stopped
    command: redis-server --requirepass ${REDIS_PASSWORD} --maxmemory 256mb --maxmemory-policy allkeys-lru
    volumes:
      - redis_data:/data
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 10s
    networks:
      - auth_internal

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
      PG_PASSWORD_FILE: /run/secrets/pg_password
      PORT: 8090
    secrets:
      - pg_password
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8090/health"]
      interval: 15s
      timeout: 5s
      retries: 3
    networks:
      - auth_internal

  auth_service:
    build:
      context: ../..
      dockerfile: server_apps/aq_auth_service/Dockerfile
    container_name: aq_auth_service
    restart: unless-stopped
    depends_on:
      auth_data_service:
        condition: service_healthy
      redis:
        condition: service_healthy
    environment:
      AUTH_DATA_SERVICE_URL: http://auth_data_service:8090
      AUTH_BASE_URL: ${AUTH_BASE_URL:-https://auth.example.com}
      REDIS_URL: redis://:${REDIS_PASSWORD}@redis:6379
      ALLOWED_ORIGINS: ${ALLOWED_ORIGINS}
      PORT: 8080
      # Секреты — из файлов, не из env:
      JWT_SECRET_FILE: /run/secrets/jwt_secret
      GOOGLE_CLIENT_SECRET_FILE: /run/secrets/google_secret
      GITHUB_CLIENT_SECRET_FILE: /run/secrets/github_secret
    secrets:
      - jwt_secret
      - google_secret
      - github_secret
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8080/auth/health"]
      interval: 10s
      timeout: 3s
      retries: 3
      start_period: 15s
    networks:
      - auth_internal
      - auth_external
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.auth.rule=Host(`auth.example.com`)"
      - "traefik.http.routers.auth.tls.certresolver=letsencrypt"

  nginx:
    image: nginx:1.25-alpine
    container_name: aq_nginx
    restart: unless-stopped
    ports:
      - "443:443"
      - "80:80"
    volumes:
      - ./nginx/nginx.conf:/etc/nginx/nginx.conf:ro
      - ./nginx/ssl:/etc/nginx/ssl:ro
    depends_on:
      - auth_service
    networks:
      - auth_external

  # Monitoring
  prometheus:
    image: prom/prometheus:latest
    container_name: aq_prometheus
    volumes:
      - ./monitoring/prometheus.yml:/etc/prometheus/prometheus.yml
    networks:
      - auth_internal

  grafana:
    image: grafana/grafana:latest
    container_name: aq_grafana
    volumes:
      - grafana_data:/var/lib/grafana
      - ./monitoring/grafana/dashboards:/etc/grafana/provisioning/dashboards
    networks:
      - auth_internal
      - auth_external

volumes:
  pg_data:
  redis_data:
  grafana_data:

secrets:
  pg_password:
    file: ./secrets/pg_password.txt
  jwt_secret:
    file: ./secrets/jwt_secret.txt
  google_secret:
    file: ./secrets/google_secret.txt
  github_secret:
    file: ./secrets/github_secret.txt

networks:
  auth_internal:
    internal: true
  auth_external:
```

---

### Задача 6.2 — Nginx Rate Limiting + TLS

```nginx
# nginx/nginx.conf

# Rate limit zones
limit_req_zone $binary_remote_addr zone=auth_login:10m rate=10r/m;
limit_req_zone $binary_remote_addr zone=auth_refresh:10m rate=30r/m;
limit_req_zone $binary_remote_addr zone=auth_general:10m rate=200r/m;

server {
    listen 443 ssl http2;
    server_name auth.example.com;

    # TLS
    ssl_certificate /etc/nginx/ssl/fullchain.pem;
    ssl_certificate_key /etc/nginx/ssl/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256;
    ssl_prefer_server_ciphers off;
    ssl_session_cache shared:SSL:10m;

    # Security headers
    add_header Strict-Transport-Security "max-age=63072000; includeSubDomains" always;
    add_header X-Frame-Options DENY always;
    add_header X-Content-Type-Options nosniff always;

    # Rate limiting per endpoint
    location /auth/login {
        limit_req zone=auth_login burst=5 nodelay;
        limit_req_status 429;
        proxy_pass http://auth_service:8080;
    }

    location /auth/refresh {
        limit_req zone=auth_refresh burst=10 nodelay;
        proxy_pass http://auth_service:8080;
    }

    location / {
        limit_req zone=auth_general burst=50;
        proxy_pass http://auth_service:8080;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}

# Redirect HTTP → HTTPS
server {
    listen 80;
    return 301 https://$host$request_uri;
}
```

---

### Задача 6.3 — Backup PostgreSQL

```bash
#!/bin/bash
# scripts/backup.sh — запускать через cron каждые 6 часов

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="aq_auth_backup_${TIMESTAMP}.sql.gz"
S3_BUCKET="s3://your-bucket/backups/postgres/"

# Дамп
docker exec aq_postgres pg_dump -U $POSTGRES_USER $POSTGRES_DB \
    | gzip > /tmp/$BACKUP_FILE

# Загрузить в S3 (или любое объектное хранилище)
aws s3 cp /tmp/$BACKUP_FILE $S3_BUCKET

# Удалить локальный файл
rm /tmp/$BACKUP_FILE

# Удалить бэкапы старше 30 дней
aws s3 ls $S3_BUCKET | awk '{print $4}' | while read f; do
    created=$(aws s3 ls $S3_BUCKET$f | awk '{print $1}')
    # ... логика удаления старых файлов
done

echo "[Backup] Done: $BACKUP_FILE"
```

```yaml
# cron: каждые 6 часов
# 0 */6 * * * /app/scripts/backup.sh >> /var/log/backup.log 2>&1
```

---

### Задача 6.4 — CI/CD Pipeline

```yaml
# .github/workflows/ci.yml
name: CI

on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest
    services:
      postgres:
        image: postgres:16
        env:
          POSTGRES_PASSWORD: test_password
          POSTGRES_DB: aq_auth_test
        ports: ['5432:5432']
      redis:
        image: redis:7
        ports: ['6379:6379']

    steps:
      - uses: actions/checkout@v4
      - uses: dart-lang/setup-dart@v1

      - name: Install dependencies
        run: dart pub get

      - name: Analyze
        run: dart analyze --fatal-infos

      - name: Format check
        run: dart format --output=none --set-exit-if-changed .

      - name: Unit tests
        run: dart test test/unit/ --coverage=coverage

      - name: Integration tests
        run: dart test test/integration/
        env:
          PG_HOST: localhost
          PG_DB: aq_auth_test
          PG_PASSWORD: test_password
          REDIS_URL: redis://localhost:6379

      - name: Coverage report
        run: |
          dart pub global activate coverage
          dart pub global run coverage:format_coverage \
            --lcov --in=coverage --out=coverage/lcov.info
          # Fail if coverage < 80%
          genhtml coverage/lcov.info -o coverage/html
          COVERAGE=$(lcov --summary coverage/lcov.info | grep lines | awk '{print $2}' | tr -d '%')
          if (( $(echo "$COVERAGE < 80" | bc -l) )); then
            echo "Coverage $COVERAGE% is below 80%"
            exit 1
          fi

      - name: Security scan
        run: |
          # Проверить на hardcoded secrets
          grep -r "test_api_key\|password123\|secret123" lib/ && exit 1 || true
          # OWASP dependency check
          # dart pub outdated --json | check for known CVEs

  build:
    needs: test
    if: github.ref == 'refs/heads/main'
    runs-on: ubuntu-latest
    steps:
      - name: Build Docker images
        run: docker compose -f docker-compose.prod.yml build

      - name: Push to registry
        run: docker compose -f docker-compose.prod.yml push
```

---

### 📄 Документация Фазы 6

| Артефакт | Содержание |
|---|---|
| `doc/DEPLOYMENT.md` | Полное руководство по деплою: dev → staging → prod |
| `doc/INFRASTRUCTURE.md` | Описание всех сервисов, портов, сетей |
| `doc/BACKUP_RESTORE.md` | Процедура резервного копирования и восстановления |
| `doc/MONITORING.md` | Grafana dashboards, Prometheus metrics, alerts |
| `doc/RUNBOOK.md` | Операционный runbook: что делать при каждом типе инцидента |
| `doc/SCALING.md` | Как масштабировать: Redis cluster, PG read replicas, LB |
| `.env.example` | Шаблон env-файла со всеми переменными и комментариями |
| `CONTRIBUTING.md` | Правила работы с репозиторием, code review checklist |

---

## Требования к тестированию

> **Принцип:** Ни одна задача не считается выполненной без соответствующих тестов.
> Тесты пишутся в процессе реализации (TDD/BDD), а не после.

### Unit-тесты

**Охват: не менее 80% строк кода. Критические компоненты — 100%.**

#### Обязательные unit-тесты (по компоненту):

```
test/unit/
├── security/
│   ├── api_key_service_test.dart
│   │   ├── ✓ generate key format (aq_live_/aq_test_ prefix)
│   │   ├── ✓ hash is SHA-256 of raw key
│   │   ├── ✓ raw key not stored
│   │   ├── ✓ validate returns null for invalid key
│   │   ├── ✓ validate returns null for expired key
│   │   ├── ✓ validate returns null for revoked key
│   │   ├── ✓ validate updates lastUsedAt
│   │   ├── ✓ rotate creates new key, revokes old
│   │   └── ✓ test_api_key returns null (backdoor removed)
│   │
│   ├── token_issuer_test.dart
│   │   ├── ✓ access token contains required claims (sub, tid, sid, perms)
│   │   ├── ✓ access token expires in 1 hour
│   │   ├── ✓ refresh token expires in 30 days
│   │   ├── ✓ token signature validates with correct secret
│   │   ├── ✓ token signature fails with wrong secret
│   │   └── ✓ expired token validation returns invalid
│   │
│   ├── password_service_test.dart
│   │   ├── ✓ hash is not reversible
│   │   ├── ✓ same password produces different hashes (salt)
│   │   ├── ✓ verify returns true for correct password
│   │   ├── ✓ verify returns false for wrong password
│   │   └── ✓ timing: verify runs same time for wrong password (anti-timing)
│   │
│   └── session_service_test.dart
│       ├── ✓ create session returns valid session
│       ├── ✓ revoke marks session as revoked
│       ├── ✓ expired sessions are purged
│       └── ✓ findByRefreshToken returns null for revoked
│
├── rbac/
│   ├── access_control_engine_test.dart
│   │   ├── ✓ user with no roles → deny
│   │   ├── ✓ exact permission match → allow
│   │   ├── ✓ wildcard resource:*:* → allow all actions
│   │   ├── ✓ wildcard *:read:tenant → allow all resources
│   │   ├── ✓ *:*:* → allow everything
│   │   ├── ✓ role hierarchy: child inherits parent permissions
│   │   ├── ✓ role hierarchy depth > 5 → no infinite loop
│   │   ├── ✓ circular role inheritance → no infinite loop
│   │   ├── ✓ expired user_role → treated as no role
│   │   ├── ✓ cache hit returns same decision
│   │   ├── ✓ invalidate cache → next check goes to DB
│   │   ├── ✓ batch check loads roles once (not N times)
│   │   └── ✓ policy deny overrides permission allow
│   │
│   ├── rbac_service_test.dart
│   │   ├── ✓ create role → accessible by getAllRoles
│   │   ├── ✓ assign role → user has permissions
│   │   ├── ✓ revoke role → user loses permissions
│   │   ├── ✓ assign temporary role with expiry
│   │   ├── ✓ adding inheritance detects cycles
│   │   └── ✓ delete role → all assignments cleaned
│   │
│   └── policy_engine_test.dart
│       ├── ✓ time policy: blocks access outside hours
│       ├── ✓ ip whitelist: allows only listed IPs
│       ├── ✓ ip blacklist: blocks listed IPs
│       ├── ✓ mfa policy: blocks if mfa not verified
│       ├── ✓ priority: higher priority policy evaluated first
│       └── ✓ deny effect overrides allow from roles
│
├── client/
│   ├── aq_security_service_test.dart
│   │   ├── ✓ loginWithGoogle → state = Authenticated
│   │   ├── ✓ loginWithApiKey → state = Authenticated
│   │   ├── ✓ logout → state = Unauthenticated, tokens cleared
│   │   ├── ✓ restoreSession → valid token → Authenticated
│   │   ├── ✓ restoreSession → expired → attempts refresh
│   │   ├── ✓ restoreSession → refresh fails → Unauthenticated
│   │   ├── ✓ accessToken → auto-refresh 60s before expiry
│   │   └── ✓ stream emits state changes in order
│   │
│   └── http_auth_transport_test.dart
│       ├── ✓ login sends correct body format
│       ├── ✓ non-200 response throws SecurityTransportException
│       ├── ✓ bearer token added to Authorization header
│       └── ✓ refresh sends refreshToken in body
│
└── validators/
    ├── ✓ email validation accepts valid formats
    ├── ✓ email validation rejects invalid formats
    ├── ✓ password min length 8
    └── ✓ permission format resource:action:scope
```

### Integration-тесты

**Запускаются против реального PostgreSQL и Redis в Docker.**

```
test/integration/
├── auth_flow_test.dart
│   ├── ✓ Full email/password flow: register → verify email → login → get me → logout
│   ├── ✓ Refresh token flow: login → refresh → use new token
│   ├── ✓ Refresh token rotation: reuse old refresh token → all tokens revoked
│   ├── ✓ Logout revokes access token (blacklist)
│   ├── ✓ Login with invalid password → 401
│   └── ✓ Login with unverified email → 403 with correct error code
│
├── api_key_flow_test.dart
│   ├── ✓ Create API key → raw key shown once
│   ├── ✓ Use API key → authenticated → can call API
│   ├── ✓ Revoke API key → next request → 401
│   ├── ✓ Rotate API key → old revoked → new works
│   └── ✓ Expired API key → 401
│
├── rbac_flow_test.dart
│   ├── ✓ Assign role → introspect returns correct permissions
│   ├── ✓ Revoke role → introspect returns denied
│   ├── ✓ Role hierarchy: member inherits viewer permissions
│   ├── ✓ Temporary role: works before expiry, denied after
│   ├── ✓ RBAC access logs written to DB (Step 7 fix)
│   └── ✓ Batch permission check returns correct map
│
├── introspection_test.dart
│   ├── ✓ Valid token + allowed permission → { active: true, allowed: true }
│   ├── ✓ Valid token + denied permission → { active: true, allowed: false }
│   ├── ✓ Expired token → { active: false }
│   ├── ✓ Revoked token → { active: false }
│   └── ✓ Response time < 10ms (performance baseline)
│
├── rate_limit_test.dart
│   ├── ✓ 10 rapid login attempts → 11th returns 429
│   ├── ✓ After 1 minute window → requests allowed again
│   └── ✓ Rate limit headers present in response
│
└── security_test.dart
    ├── ✓ CORS: request from allowed origin → correct headers
    ├── ✓ CORS: request from unknown origin → no ACAO header
    ├── ✓ Security headers present on all responses
    ├── ✓ SQL injection attempt in email field → 400, no DB error
    ├── ✓ XSS attempt in name field → sanitized or rejected
    └── ✓ Oversized request body → 413
```

### E2E-тесты (сценарии)

```
test/e2e/
├── human_user_scenario_test.dart
│   Сценарий: Пользователь регистрируется, подтверждает email,
│   логинится через Google, создаёт проект, приглашает коллегу,
│   коллега принимает, оба работают с проектом в своих ролях.
│
├── worker_agent_scenario_test.dart
│   Сценарий: Воркер создаёт API-ключ, использует его для
│   получения доступа к ресурсам, ключ ротируется, старый
│   перестаёт работать, новый работает.
│
└── resource_server_scenario_test.dart
    Сценарий: Data Service регистрируется как Resource Server,
    принимает запросы с токенами от нескольких пользователей
    с разными правами, каждый получает ровно то, что разрешено.
```

### Нагрузочные тесты (обязательны до production)

```dart
// Минимальные показатели для Production:
// Introspection endpoint: > 1000 RPS @ p99 < 10ms
// Login endpoint:         > 100 RPS @ p99 < 500ms
// Token validation:       > 2000 RPS @ p99 < 5ms (с кэшем)

// Инструменты: k6, wrk, dart:test с concurrent isolates
```

---

## Требования к документации

> **Принцип «Документация — это код»:**
> - Документация обновляется в том же PR, что и код
> - PR без обновления документации не принимается в review
> - Итоговая документация генерируется из кода (dartdoc) + дополняется вручную

### Документация в процессе работы (обязательно в каждом PR)

| Тип | Требование |
|---|---|
| **Dartdoc** | Все публичные классы, методы, поля — с описанием, `@param`, `@returns`, `@throws`, примером использования |
| **ADR** (Architecture Decision Record) | Любое нетривиальное архитектурное решение — в `doc/adr/NNN-title.md`. Формат: контекст → решение → обоснование → последствия |
| **CHANGELOG** | Каждый PR обновляет `CHANGELOG.md` в формате Keep a Changelog |
| **OpenAPI** | Любой новый или изменённый endpoint обновляет `openapi/*.yaml` |
| **Inline комментарии** | Сложная логика — обязательный комментарий «почему», не «что» |

### Финальная документация (до выхода в production)

```
docs/
├── README.md                       — Обзор системы, quick start
├── ARCHITECTURE.md                 — Высокоуровневая архитектура с диаграммами
├── SECURITY.md                     — Политика безопасности и disclosure
├── CONTRIBUTING.md                 — Как работать с репозиторием
├── CHANGELOG.md                    — История версий
│
├── guides/
│   ├── QUICKSTART.md               — Запустить за 5 минут (dev)
│   ├── CLIENT_INTEGRATION.md       — Подключение SDK в своё приложение
│   ├── RESOURCE_SERVER.md          — Защита своих ресурсов
│   ├── FLUTTER_OAUTH.md            — Deep links, PKCE, secure storage
│   ├── WORKER_AUTH.md              — API keys для workers/agents
│   └── MIGRATION.md                — Переход с предыдущих версий
│
├── reference/
│   ├── AUTH_PROVIDERS.md           — Google, GitHub, Email/Password
│   ├── API_KEYS.md                 — Управление ключами
│   ├── TOKEN_LIFECYCLE.md          — Жизненный цикл токенов
│   ├── RBAC_GUIDE.md               — Роли, права, политики
│   ├── PERMISSION_REFERENCE.md     — Все permissions и их смысл
│   └── ERROR_CODES.md              — Все коды ошибок API
│
├── operations/
│   ├── DEPLOYMENT.md               — Деплой в prod
│   ├── BACKUP_RESTORE.md           — Бэкап и восстановление
│   ├── MONITORING.md               — Метрики, дашборды, алерты
│   ├── RUNBOOK.md                  — Операционные процедуры
│   ├── SECRETS_MANAGEMENT.md       — Управление секретами
│   └── SCALING.md                  — Горизонтальное масштабирование
│
├── adr/
│   ├── 001-no-wildcard-cors.md
│   ├── 002-uuid-for-ids.md
│   ├── 003-argon2id-passwords.md
│   ├── 004-pkce-mobile.md
│   ├── 005-refresh-token-rotation.md
│   ├── 006-redis-token-blacklist.md
│   └── 007-rls-multitenancy.md
│
└── openapi/
    ├── auth.yaml                   — /auth/* endpoints
    ├── rbac.yaml                   — /rbac/* endpoints
    └── introspect.yaml             — /api/introspect
```

### Стандарт dartdoc

```dart
/// Проверяет, имеет ли пользователь заданное право доступа.
///
/// Выполняет полную проверку включая:
/// - загрузку ролей пользователя из репозитория
/// - рекурсивное разворачивание иерархии ролей (max depth: 5)
/// - сопоставление с учётом wildcards (resource:action:scope)
/// - применение контекстуальных политик (если [context] передан)
/// - кэширование результата на [AccessCache.ttl]
///
/// Пример:
/// ```dart
/// final decision = await engine.canAsync(
///   userId,
///   'projects',
///   'read',
///   'tenant',
///   context: AccessContext(ip: '10.0.0.1', mfaVerified: true),
/// );
/// if (decision.allowed) {
///   // proceed
/// }
/// ```
///
/// [userId] — идентификатор пользователя из JWT `sub` claim
/// [resource] — тип ресурса: `projects`, `users`, `workflows`, и т.д.
/// [action] — действие: `read`, `write`, `delete`, `manage`, `*`
/// [scope] — область: `own`, `tenant`, `platform`, `*`
/// [context] — опционально: IP, MFA-статус, состояние ресурса
///
/// Возвращает [AccessDecision] с полями `allowed`, `reason` и
/// `effectivePermissions` для отладки.
///
/// Выбрасывает [RBACException] при ошибке репозитория.
Future<AccessDecision> canAsync(
  String userId,
  String resource,
  String action,
  String scope, {
  AccessContext? context,
}) async { ... }
```

---

## Definition of Done

Задача считается **завершённой** только при выполнении всех пунктов:

### Код
- [ ] Код написан и прошёл code review минимум одного другого разработчика
- [ ] `dart analyze` — 0 ошибок, 0 предупреждений
- [ ] `dart format` — код отформатирован
- [ ] Нет `TODO`, `FIXME`, `HACK` без тикета в трекере
- [ ] Нет хардкода: строк-идентификаторов коллекций, секретов, test-backdoor'ов

### Тесты
- [ ] Unit-тесты написаны и проходят
- [ ] Покрытие строк: не ниже 80% для нового кода, 100% для security-компонентов
- [ ] Integration-тесты проходят против реальной БД
- [ ] Регрессионный тест написан для каждого исправленного бага

### Документация
- [ ] Dartdoc обновлён для всех публичных API
- [ ] `CHANGELOG.md` обновлён
- [ ] Соответствующий `doc/*.md` обновлён или создан
- [ ] `openapi/*.yaml` обновлён при изменении HTTP API
- [ ] ADR создан при архитектурном решении

### Безопасность
- [ ] Нет `Access-Control-Allow-Origin: *` для auth endpoints
- [ ] Все новые endpoints имеют rate limiting
- [ ] Входные данные валидируются
- [ ] Новые секреты идут через Secrets Manager, не в `.env`

---

## Сводный чеклист

### Фаза 0 — Блокеры (Дни 1–3)
- [ ] 0.1 Удалить backdoor `test_api_key`
- [ ] 0.2 Исправить CORS wildcard → конфигурируемый вайтлист
- [ ] 0.3 Заменить `_generateId()` на `Uuid().v4()` везде
- [ ] 0.4 Починить `systemRoles` seeding
- [ ] 0.5 Унифицировать имена коллекций через `SecurityCollections`
- [ ] 0.6 Исправить суффикс LoggedStorable (тест Step 7)

### Фаза 1 — Auth провайдеры (Дни 3–7)
- [ ] 1.1 Google OAuth: redirect URI, callback, PKCE, error handling, Google refresh token
- [ ] 1.2 GitHub OAuth: новый сервис, credentials, `/user/emails`
- [ ] 1.3 Email/Password: Argon2id, timing protection, email verify, password reset
- [ ] 1.4 Унифицированный `AuthRouter` (switch на type)

### Фаза 2 — Tokens & API Keys (Дни 8–15)
- [ ] 2.1 `lastUsedAt` tracking, scoped keys, usage endpoint
- [ ] 2.2 Refresh token rotation с детектированием компрометации
- [ ] 2.3 Обогащённые JWT claims + `jti`
- [ ] 2.4 Token blacklist через Redis
- [ ] 2.5 (Опц.) Переход на RS256 + JWKS endpoint

### Фаза 3 — RBAC & Resources (Дни 10–18)
- [ ] 3.1 Системные роли и иерархия
- [ ] 3.2 Фоновая очистка истёкших временных ролей
- [ ] 3.3 `ResourceAuthMiddleware` + `ResourceConfig`
- [ ] 3.4 Реализовать `/rbac/metrics` endpoint
- [ ] 3.5 Context policies: `tenant_owner`, `resource_owner`

### Фаза 4 — Security Hardening (Дни 16–20)
- [ ] 4.1 Rate limiting (Redis sliding window) + Nginx upstream
- [ ] 4.2 Security headers middleware
- [ ] 4.3 Secrets Manager интеграция
- [ ] 4.4 PostgreSQL: FK, RLS, отдельный DB user
- [ ] 4.5 Input validation для всех endpoints

### Фаза 5 — Client SDK (Дни 18–24)
- [ ] 5.1 Обновить `AQSecurityClient.init()` — богатые options
- [ ] 5.2 `RBACClient` — синхронная и асинхронная проверка прав
- [ ] 5.3 `ResourceGuard` — middleware + прямая проверка
- [ ] 5.4 Flutter deep link handler + PKCE
- [ ] 5.5 `FlutterSecureStorageSessionStore`

### Фаза 6 — Инфраструктура (Дни 22–28)
- [ ] 6.1 `docker-compose.prod.yml` с секретами, healthchecks, labels
- [ ] 6.2 Nginx: rate limit, TLS 1.3, security headers
- [ ] 6.3 Backup скрипт + cron
- [ ] 6.4 CI/CD pipeline (GitHub Actions)
- [ ] 6.5 Prometheus + Grafana dashboards

### Тестирование
- [ ] Unit coverage ≥ 80% (security компоненты — 100%)
- [ ] Integration: full auth flow, API keys, RBAC, introspection, rate limit, security
- [ ] E2E: human user, worker/agent, resource server scenarios
- [ ] Load test: introspection > 1000 RPS @ p99 < 10ms

### Документация
- [ ] Все публичные API задокументированы dartdoc
- [ ] `ARCHITECTURE.md`, `SECURITY.md`, `CONTRIBUTING.md`
- [ ] Все guides: CLIENT_INTEGRATION, RESOURCE_SERVER, FLUTTER_OAUTH, WORKER_AUTH
- [ ] Все operations: DEPLOYMENT, BACKUP_RESTORE, MONITORING, RUNBOOK
- [ ] Все ADR (001–007+)
- [ ] OpenAPI specs: auth.yaml, rbac.yaml, introspect.yaml
- [ ] `CHANGELOG.md` актуален

---

*План составлен на основании технического аудита `aq_security` и `aq_schema` от 09.04.2026.*  
*При любом отклонении от плана — создать ADR с обоснованием.*