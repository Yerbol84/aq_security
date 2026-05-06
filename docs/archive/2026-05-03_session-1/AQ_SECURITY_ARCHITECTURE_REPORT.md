# AQ Security Layer — Полный архитектурный отчёт

**Дата:** 2026-05-03  
**Пакеты:** `aq_schema` (root) + `aq_security` (реализация)  
**Стек:** Dart / Flutter / HTTP  
**Статус:** Pre-refactor analysis + Target Architecture + TZ для агента

---

## ЧАСТЬ 1 — МНОГОРОЛЕВОЙ АНАЛИЗ

Каждая роль смотрит на систему со своей точки зрения. Беспристрастно.

---

### 🧑‍💼 РОЛЬ 1: Клиент (Flutter-разработчик, строит UI на aq_schema)

**Что я ожидаю от слоя безопасности:**  
Вызвал `ISecurityService.instance.roleManagement.getRoles()` — получил роли.  
Вызвал `hasPermission('projects:write')` — получил `true` или `false`.  
Всё остальное меня не интересует.

**Что я реально получаю:**

```
ISecurityService.roleManagement → UnimplementedError 🔴
ISecurityService.policies       → UnimplementedError 🔴
ISecurityService.audit          → UnimplementedError 🔴
ISecurityService.register()     → UnimplementedError 🔴
ISecurityService.createApiKey() → UnimplementedError 🔴
ISecurityService.switchTenant() → UnimplementedError 🔴
ISecurityService.updateProfile()→ UnimplementedError 🔴
```

**Вердикт клиента:** Интерфейс продуман отлично. Реализация — половина методов бросает `UnimplementedError`. Я не могу построить реальный UI поверх этого. Декорация без стен.

**Что хорошо:** `SecurityState` sealed class + Stream — правильный паттерн. `loginWithEmail`, `loginWithGoogle`, `restoreSession`, `logout` — работают. Базовый auth flow закрыт.

---

### 🏗️ РОЛЬ 2: Backend-разработчик (пишет реализацию aq_security)

**Что я вижу в коде:**

**Хорошее:**
- `AQAuthServer` — собран правильно, Shelf pipeline с middleware
- `AccessControlEngine` — полноценный RBAC движок с кэшем, wildcards, иерархией ролей, policy evaluation
- `RBACService` — управление ролями, временные роли, инвалидация кэша
- `TokenIssuer` + `TokenValidator` — JWT lifecycle
- `SessionService` с purge timer — правильно
- DoS protection, Rate limiting, Security headers — есть и работают
- `AqVaultSecurityProtocol` — правильная идея bridging data layer

**Критические проблемы:**

1. **`AQSecurityService` (клиентский) не подключён к `RBACService` (серверному)**  
   Это два разных мира. Клиентский `AQSecurityService` умеет только login/logout/tokens. Весь RBAC (`RBACService`, `AccessControlEngine`) живёт только на сервере в `AQAuthServer`. Клиент к нему обращается через HTTP, но `roleManagement`, `policies`, `audit` геттеры в `AQSecurityService` выбрасывают `UnimplementedError`. Мост не построен.

2. **`_NoOpResourcePermissionService` везде**  
   `AqVaultSecurityProtocol.resourcePermissions` → `_NoOpResourcePermissionService`. RLAC (Resource-Level Access Control) полностью не работает. Grant/revoke на ресурсы — NoOp.

3. **`logOperation` — TODO/пусто**  
   Аудит из data layer не пишется. Архитектурно декларировано, фактически мертво.

4. **Permission format несоответствие:**  
   - В `ISecurityService.hasPermission()` — формат `resource:action`  
   - В `AccessControlEngine.canAsync()` — формат `resource:action:scope`  
   - В `AqRole.hasPermission()` — формат `resource:action`  
   - В RBAC стратегии — формат `resource:action:scope`  
   Три разных формата в одном пакете. Запросы будут падать в рантайме.

5. **`TokenCodec.decodeUnverified` в клиенте (data layer)**  
   В `AqVaultSecurityProtocol.extractClaims()` токен декодируется **без верификации подписи**. Потом вызывается introspection, который верифицирует. Но если introspection упадёт — решение принимается по не-верифицированным claims. Риск.

6. **Дублирование доменов в `AqSecurityDomains`:**  
   `SecurityCollections.roles` (StorableRole) И `AqRole.kCollection = 'security_roles'` (StorableRole) — два дескриптора на одну коллекцию. При развёртывании будет конфликт.

7. **`IAuthContext` как третий синглтон безопасности**  
   Уже есть `ISecurityService._instance` и `IVaultSecurityProtocol._instance`. Теперь ещё `IAuthContext._instance`. Три синглтона надо инициализировать в правильном порядке. Нигде не задокументировано.

8. **`AuthServerRepos.storage: dynamic`**  
   ```dart
   final dynamic storage; // VaultStorage для RBAC репозиториев
   ```
   `dynamic` в критической части инициализации сервера безопасности. Это пройдёт через анализатор, упадёт в рантайме.

**Вердикт backend-разработчика:** Скелет хорош, органы не подключены. Нужно соединить клиентский `AQSecurityService` с серверным RBAC через HTTP transport, реализовать `IResourcePermissionService`, починить permission format, убрать `dynamic`.

---

### 🔒 РОЛЬ 3: Security Engineer (оцениваю с точки зрения реальной безопасности)

**Что меня беспокоит:**

**Критично:**

1. **SQL Injection protection — ложная безопасность**  
   ```dart
   // AqVaultSecurityProtocol._containsSqlInjection
   RegExp(r"('|(--)|;|...)")  // regex на строку
   ```
   Это не защита от SQL injection. Это эвристика которая:  
   (а) Ломает легитимные данные (апостроф в имени O'Brien)  
   (б) Пропускает injection через unicode, encoding, hex  
   Защита от SQLi — это параметризованные запросы, не regex. Этот код создаёт **ложное ощущение безопасности**.

2. **Access Cache TTL хардкодирован**  
   ```dart
   class AccessCache {
     AccessCache({this.ttl = const Duration(minutes: 5)})
   ```
   TTL кэша решений RBAC — 5 минут. Если роль отозвана у пользователя, он ещё 5 минут имеет доступ. Для production это слишком долго. Должно быть в SecurityConfig.

3. **CORS — пустая строка при запрещённом origin**  
   ```dart
   'Access-Control-Allow-Origin': isAllowed ? origin : '',
   ```
   При не-разрешённом origin возвращается пустая строка вместо отсутствия заголовка. Браузеры обрабатывают это по-разному. Правильно — не добавлять заголовок вообще.

4. **Нет rate limiting на auth endpoints на уровне IP**  
   `RateLimiter` использует `user:userId` или `ip:unknown` как ключ. При анонимном bruteforce на `/auth/login` IP не всегда доступен — ключ становится `ip:unknown` для всех анонимных запросов. Один слот для всех.

5. **Нет явной защиты refresh token rotation**  
   Refresh token при use не инвалидируется немедленно. Нет проверки на reuse detection (RFC 6749 best practice).

6. **`SecurityConfig.jwtSecret` хранится в памяти как String**  
   Должно быть `Uint8List` или `SecureString` — не копируется GC, может быть очищен явно.

**Среднее:**

7. Нет MFA в текущих интерфейсах (есть `mfaVerified` в PolicyContext, но нет auth flow)
8. Нет throttling на email verification/password reset endpoints
9. `ISessionStore` хранит токены — нужен флаг encrypted at rest

**Что хорошо:**
- JWT access token TTL 15 минут — правильно
- `TokenValidator` с local validation — правильно (не каждый раз на сервер)
- Revoked tokens через `AqRevokedToken` model — есть
- Introspection endpoint (RFC 7662) — правильная архитектура для resource servers
- DoS middleware, IP blacklist — есть

---

### 📊 РОЛЬ 4: Data Layer (dart_vault смотрит на security layer как на своего защитника)

**Что я хочу от security:**  
Один вопрос: "Можно мне это сделать?"  
Один ответ: AccessAllowed / AccessDenied / AccessRestricted

**Что я реально получаю:**

Протокол `IVaultSecurityProtocol` спроектирован отлично:
```dart
canRead({claims, collection, entityId})  // ✅ чистый контракт
canWrite({claims, collection, data})     // ✅
canDelete({claims, collection, entityId})// ✅
checkRateLimit({claims, operation, ip})  // ✅
validateData({collection, data})         // ✅ (но SQLi regex — см. выше)
encryptSensitiveFields(...)              // ✅
logOperation(...)                        // 🔴 TODO, пусто
resourcePermissions.grant(...)           // 🔴 NoOp
```

**Проблема 1: Неизвестные коллекции = Exception**  
```dart
default:
  throw UnknownCollectionException('Unknown collection: $collection')
```
Если data layer добавит новую коллекцию и не обновит switch в `_mapCollectionToResourceType` — упадёт в production. Нет graceful degradation.

**Проблема 2: IAuthContext не интегрирован**  
`IAuthContext` предназначен для data layer (decoupling от auth), но в `AqVaultSecurityProtocol` он не используется. Данные берутся из HTTP headers. Два механизма передачи auth-контекста одновременно.

**Проблема 3: Два режима работы не задокументированы явно**  
Упомянуто "2 режима" у security layer. Предположительно:
- Режим A: Data layer + Security layer на одном процессе/machine (через singleton)
- Режим B: Data layer и Security layer как отдельные сервисы (через HTTP introspection)

Нигде это не задекларировано как явная архитектурная концепция.

---

### 📈 РОЛЬ 5: DevOps / Admin (смотрю на операционную сторону)

**Хорошее:**
- Prometheus metrics (grafana dashboards есть)
- Kubernetes deployments, docker-compose
- Rate limiting, DoS protection
- Session purge timer
- Health endpoint
- Structured logging
- Redis в stack для sessions

**Проблемы:**

1. **Нет явного session storage backend**  
   `ISessionStore` (local, в памяти Flutter) vs `ISessionRepository` (server, Postgres) — два хранилища сессий, нет четкого разграничения. При горизонтальном масштабировании сервера `LocalSessionStore` в памяти не работает — нужен Redis.

2. **Нет стратегии key rotation для JWT secret**  
   `SecurityConfig.jwtSecret` — один секрет. При компрометации нет механизма graceful rotation.

3. **Нет multi-instance cache invalidation**  
   `AccessCache` — in-memory. При нескольких инстансах auth сервера кэш не синхронизируется.

---

## ЧАСТЬ 2 — СВОДНЫЙ АНАЛИЗ

### Матрица проблем

| # | Проблема | Критичность | Тип |
|---|----------|-------------|-----|
| 1 | roleManagement/policies/audit — UnimplementedError | 🔴 CRITICAL | Функционал |
| 2 | _NoOpResourcePermissionService (RLAC мёртв) | 🔴 CRITICAL | Функционал |
| 3 | Permission format несоответствие (resource:action vs resource:action:scope) | 🔴 CRITICAL | Архитектура |
| 4 | logOperation — TODO пусто | 🔴 CRITICAL | Безопасность |
| 5 | Дублирование security domains | 🟠 HIGH | Архитектура |
| 6 | AuthServerRepos.storage: dynamic | 🟠 HIGH | Надёжность |
| 7 | Три синглтона без задокументированного порядка инициализации | 🟠 HIGH | Архитектура |
| 8 | SQL injection "защита" через regex | 🟠 HIGH | Безопасность |
| 9 | UnknownCollectionException без fallback | 🟠 HIGH | Надёжность |
| 10 | Два режима безопасности не задекларированы | 🟠 HIGH | Архитектура |
| 11 | AccessCache TTL хардкодирован (5 мин) | 🟡 MEDIUM | Конфиг |
| 12 | CORS: пустая строка вместо отсутствия заголовка | 🟡 MEDIUM | Безопасность |
| 13 | IAuthContext не используется в VaultSecurityProtocol | 🟡 MEDIUM | Архитектура |
| 14 | Нет refresh token rotation/reuse detection | 🟡 MEDIUM | Безопасность |
| 15 | Нет MFA auth flow | 🟡 MEDIUM | Функционал |
| 16 | In-memory AccessCache не масштабируется | 🟡 MEDIUM | Масштабируемость |
| 17 | Опечатка в имени файла (i_data_layer_as_clietn_secure_protocol.dart) | 🟢 LOW | Качество |
| 18 | IUserRepository в файле i_session_repository.dart | 🟢 LOW | Организация |

---

## ЧАСТЬ 3 — ЦЕЛЕВАЯ АРХИТЕКТУРА (без привязки к реализации)

### Принцип: Security Layer как универсальный контракт безопасности

Security layer — это **единый привратник** для всей платформы. Он знает кто такой субъект и что ему можно.  
Все остальные слои — его **клиенты**. Они не знают про JWT, RBAC, политики. Они задают один вопрос.

```
                    ┌─────────────────────────────────────────┐
                    │           SECURITY LAYER                 │
                    │                                          │
                    │  ┌──────────┐  ┌──────────┐            │
                    │  │  AuthN   │  │  AuthZ   │            │
                    │  │ (кто ты) │  │ (что можно)│          │
                    │  └──────────┘  └──────────┘            │
                    │       │              │                   │
                    │  ┌────▼──────────────▼────────────────┐ │
                    │  │       Session Store                 │ │
                    │  │  (user + graph + service sessions)  │ │
                    │  └─────────────────────────────────────┘ │
                    │                                          │
                    │  ┌─────────────────────────────────────┐ │
                    │  │          Audit Log                  │ │
                    │  └─────────────────────────────────────┘ │
                    └──────────────┬──────────────────────────┘
                                   │ serves
              ┌────────────────────┼────────────────────┐
              │                    │                    │
       ┌──────▼──────┐    ┌────────▼───────┐   ┌───────▼───────┐
       │   Flutter   │    │   Data Layer   │   │  Graph Engine │
       │   UI/App    │    │  (dart_vault)  │   │   Sessions    │
       └─────────────┘    └────────────────┘   └───────────────┘
```

---

### Роли субъектов в системе (как security их видит)

| Субъект | Роль для security layer | Тип доступа |
|---------|------------------------|-------------|
| **Человек-пользователь** | `HumanPrincipal` | Интерактивная сессия (JWT + refresh) |
| **Тенант** | `TenantContext` | Scope изоляции, не субъект напрямую |
| **Service Account** | `ServicePrincipal` | API Key, нет refresh |
| **Graph Run Session** | `WorkflowPrincipal` | Временная сессия на время выполнения, ограниченные права |
| **Worker** | `WorkerPrincipal` | Зарегистрированный worker, API Key |
| **Data Layer** | `ResourceServer` | Доверенный клиент (на уровне network), проверяет через introspection |

---

### Два режима security layer (задекларировать явно)

**Mode A: Embedded (single process)**
```
App Process
├── Security Layer (singleton, in-process)
└── Data Layer (обращается к Security через IVaultSecurityProtocol)
     └── Security.canRead() → in-process call, < 1ms
```

**Mode B: Distributed (separate services)**
```
Auth Service (отдельный процесс)
    ↕ HTTP
Data Service (отдельный процесс)
    └── на каждый запрос вызывает introspection endpoint
         POST /api/introspect {token, resource, action}
         → {active, allowed, ...}
```

Mode выбирается при инициализации и фиксируется в конфиге.  
Переключение режима — без изменения кода data layer.

---

### Стек сессий (единый Session Service)

Текущая проблема: сессии пользователя, сессии графов, сессии воркеров — разные хранилища без единого контракта.

**Целевая модель:**

```dart
// Единый тип сессии с дискриминантом
enum SessionKind {
  human,    // Пользователь вошёл через UI
  service,  // API Key auth
  workflow, // Выполняется граф
  worker,   // Зарегистрированный worker
}

class AqSession {
  final SessionKind kind;
  final String subjectId;   // userId / workflowRunId / workerId
  final String tenantId;
  final List<String> scopes; // что разрешено в этой сессии
  final int expiresAt;
  // ...
}
```

Session Service — **единое хранилище** (Redis для distributed mode). Один интерфейс для всех типов.

---

### Уровни авторизации (три уровня, комбинируются)

```
Запрос: "Пользователь X хочет удалить проект Y"
                          │
              ┌───────────▼───────────┐
              │  Level 1: RBAC        │  роли → права
              │  Есть ли право        │  "project:delete"?
              │  project:delete?      │
              └───────────┬───────────┘
                          │ YES
              ┌───────────▼───────────┐
              │  Level 2: RLAC        │  ресурс-уровень
              │  X - owner/admin      │  resource_permissions
              │  проекта Y?           │  table
              └───────────┬───────────┘
                          │ YES
              ┌───────────▼───────────┐
              │  Level 3: PBAC        │  политики + контекст
              │  Нет политики         │  (время, IP, атрибуты)
              │  запрещающей?         │
              └───────────┬───────────┘
                          │ YES → AccessAllowed
```

**Правило:** все три уровня должны дать YES. Любой NO → AccessDenied.  
В текущей реализации только Level 1 работает. Level 2 — NoOp. Level 3 — только на сервере.

---

### Единая точка входа для клиентов (упрощение инициализации)

```dart
// Было: 3 синглтона отдельно
ISecurityService.initialize(...)
IVaultSecurityProtocol.initialize(...)
IAuthContext.initialize(...)

// Стало: 1 инициализация
final security = await AqSecurity.init(
  mode: SecurityMode.distributed, // или .embedded
  config: SecurityConfig(...),
);
// Остальные синглтоны устанавливаются автоматически внутри
```

---

## ЧАСТЬ 4 — ТЕХНИЧЕСКОЕ ЗАДАНИЕ (ТЗ для агента)

### Приоритет 0 — Блокирующие исправления (без этого ничего не работает)

---

#### ТЗ-0.1: Унификация формата permissions

**Проблема:** `resource:action` vs `resource:action:scope` — три места с разным форматом.

**Решение:** Зафиксировать единый формат `resource:action` с опциональным scope как отдельным полем. Scope — отдельный механизм (JWT scope claim), не часть permission key.

**Файлы для изменения:**
- `aq_schema/lib/security/models/aq_role.dart` — `hasPermission()` уже правильный (`resource:action`)
- `aq_security/lib/src/rbac/access_control_engine.dart` — `canAsync()` использует `'$resource:$action:$scope'` → изменить на `'$resource:$action'`
- `aq_schema/lib/security/interfaces/i_role_management_service.dart` — документация формата permissions

**Принятое решение:** формат — `resource:action` (двойной двоеточие). Scope передаётся отдельно в `AccessContext.userScopes`.

---

#### ТЗ-0.2: Удалить дублирование security domains

**Проблема:** В `AqSecurityDomains.all` есть два дескриптора на коллекцию `security_roles`:
- `DomainDescriptor.direct(collection: SecurityCollections.roles, fromMap: StorableRole.fromMap)`
- `DomainDescriptor.direct(collection: AqRole.kCollection, fromMap: StorableRole.fromMap)`

**Решение:** Удалить один из двух. `AqRole.kCollection = 'security_roles'` и `SecurityCollections.roles` должны быть одинаковым значением. Оставить один дескриптор.

**Файлы:**
- `aq_schema/lib/security/storable/security_domains.dart` — убрать дубликат
- `aq_schema/lib/security/storable/security_storables.dart` — проверить `SecurityCollections.roles`

---

### Приоритет 1 — Критический функционал

---

#### ТЗ-1.1: Реализовать roleManagement в AQSecurityService

**Цель:** `ISecurityService.roleManagement` должен работать, не бросать `UnimplementedError`.

**Подход:** Создать `HttpRoleManagementService` — клиент, который вызывает RBAC endpoints auth сервера.

**Файл создать:** `aq_security/lib/src/client/http_role_management_service.dart`

```dart
final class HttpRoleManagementService implements IRoleManagementService {
  HttpRoleManagementService({
    required String baseUrl,
    required Future<String?> Function() tokenProvider,
  });

  @override
  Future<List<AqRole>> getRoles() async {
    final token = await tokenProvider();
    final response = await http.get(
      Uri.parse('$baseUrl/rbac/roles'),
      headers: {'Authorization': 'Bearer $token'},
    );
    // parse and return
  }
  // ... остальные методы через HTTP к /rbac/* endpoints
}
```

**Интегрировать в:** `AQSecurityService` — добавить поле `_roleManagement` и вернуть его из геттера.

**Endpoints на сервере (уже есть в `RBACRouter`):**
- `GET /rbac/roles` → `getRoles()`
- `POST /rbac/roles` → `createRole()`
- `PUT /rbac/roles/:id` → `updateRole()`
- `DELETE /rbac/roles/:id` → `deleteRole()`
- `POST /rbac/roles/:id/assign` → `assignRole()`
- `DELETE /rbac/roles/:id/revoke` → `revokeRole()`
- `GET /rbac/users/:id/roles` → `getUserRoles()`

---

#### ТЗ-1.2: Реализовать IPolicyService и IAuditService аналогично

По той же схеме что ТЗ-1.1.

**Файлы создать:**
- `aq_security/lib/src/client/http_policy_service.dart`
- `aq_security/lib/src/client/http_audit_service.dart`

**Endpoints:**
- Policies: `GET/POST/PUT/DELETE /rbac/policies`
- Audit: `GET /rbac/audit/access-logs`, `GET /rbac/audit/trail`

---

#### ТЗ-1.3: Реализовать ResourcePermissionService (убрать NoOp)

**Цель:** `IVaultSecurityProtocol.resourcePermissions` должен реально работать.

**Файл:** `aq_security/lib/src/server/resource_permission_service.dart` — уже существует (`ResourcePermissionService`), надо подключить к `AqVaultSecurityProtocol`.

**Изменить в `AqVaultSecurityProtocol`:**
```dart
// Было:
_resourcePermissionService ??= _NoOpResourcePermissionService();

// Стало:
// принять через конструктор или создать через endpoint:
final class AqVaultSecurityProtocol implements IVaultSecurityProtocol {
  AqVaultSecurityProtocol({
    required String introspectionEndpoint,
    required String encryptionKey,
    IResourcePermissionService? resourcePermissions, // параметр
  });
}
```

---

#### ТЗ-1.4: Реализовать logOperation (аудит из data layer)

**Файл:** `aq_security/lib/src/client/aq_vault_security_protocol.dart`

```dart
@override
Future<void> logOperation({
  required AqTokenClaims? claims,
  required String operation,
  required String collection,
  String? entityId,
  required bool success,
  String? errorMessage,
}) async {
  if (claims == null) return;
  // POST к /rbac/audit/access-logs или fire-and-forget через queue
  unawaited(_auditClient.logOperation(...));
}
```

**Требование:** fire-and-forget, не блокирует data layer.

---

### Приоритет 2 — Архитектурные улучшения

---

#### ТЗ-2.1: Задекларировать два режима security (Mode A / Mode B)

**Создать:** `aq_schema/lib/security/models/security_mode.dart`

```dart
enum SecurityMode {
  /// Embedded: security и data layer в одном процессе.
  /// IVaultSecurityProtocol проверяет права in-process.
  embedded,

  /// Distributed: security как отдельный HTTP сервис.
  /// Data layer вызывает introspection endpoint для каждого запроса.
  distributed,
}
```

**Использовать в:** `SecurityConfig`, документация инициализации.

---

#### ТЗ-2.2: Единая инициализация (AqSecurity facade)

**Создать:** `aq_security/lib/src/client/aq_security.dart`

```dart
final class AqSecurity {
  static Future<AQSecurityService> init({
    required SecurityClientConfig config,
  }) async {
    final transport = HttpAuthTransport(baseUrl: config.authEndpoint);
    final store = LocalSessionStore();
    // ... создать всё
    final service = AQSecurityService.create(...);
    
    // Установить все три синглтона
    setSecurityServiceInstance(service);
    IAuthContext.initialize(AqAuthContext(service));
    IVaultSecurityProtocol.initialize(
      AqVaultSecurityProtocol(introspectionEndpoint: '${config.authEndpoint}/api/introspect', ...)
    );
    
    return service;
  }
}
```

---

#### ТЗ-2.3: Унифицировать Session model

**Добавить в** `aq_schema/lib/security/models/aq_session.dart`:

```dart
enum SessionKind {
  human,    // пользователь
  service,  // API key / service account
  workflow, // graph run
  worker,   // worker process
}
```

**Добавить поле** `SessionKind kind` в `AqSession`.

---

#### ТЗ-2.4: AccessCache TTL в конфиг

**Изменить** `SecurityConfig`:
```dart
final class SecurityConfig {
  // ... existing fields
  final Duration rbacCacheTtl;  // добавить, default: Duration(minutes: 1)
}
```

**Изменить** `AQAuthServer` — передавать `config.rbacCacheTtl` в `AccessCache`.

---

### Приоритет 3 — Безопасность и качество

---

#### ТЗ-3.1: Убрать ложную SQL injection защиту

**Файл:** `aq_security/lib/src/client/aq_vault_security_protocol.dart`

**Действие:** Удалить метод `_containsSqlInjection()` и убрать его вызов из `validateData()`. Заменить на документацию: "SQL injection prevention — ответственность ORM/query builder, не security layer".

---

#### ТЗ-3.2: Исправить UnknownCollectionException

**Файл:** `aq_vault_security_protocol.dart` → `_mapCollectionToResourceType()`

```dart
// Было: throw UnknownCollectionException

// Стало:
default:
  // Unknown collection — deny by default (principle of least privilege)
  return ResourceType.unknown; // добавить в enum
```

В `canRead/canWrite/canDelete` — для `ResourceType.unknown` → `AccessDenied('Unknown collection: $collection')`.

---

#### ТЗ-3.3: Исправить CORS header

**Файл:** `aq_security/lib/src/server/aq_auth_server.dart`

```dart
// Было:
'Access-Control-Allow-Origin': isAllowed ? origin : '',

// Стало:
if (isAllowed) headers['Access-Control-Allow-Origin'] = origin;
// не добавлять заголовок если origin не разрешён
```

---

#### ТЗ-3.4: Перенести IUserRepository и IProfileRepository

**Файл источник:** `aq_schema/lib/security/interfaces/i_session_repository.dart`  
**Создать файл:** `aq_schema/lib/security/interfaces/i_user_repository.dart`  
Перенести `IUserRepository` туда. `IProfileRepository` — туда же или в отдельный `i_profile_repository.dart`.

---

#### ТЗ-3.5: AuthServerRepos.storage: dynamic → типизировать

**Файл:** `aq_security/lib/src/server/aq_auth_server.dart`

```dart
// Было:
final dynamic storage;

// Стало: добавить импорт VaultStorage и типизировать
final VaultStorage storage;
```

---

## ЧАСТЬ 5 — ПЛАН РЕАЛИЗАЦИИ

### Фаза 0: Основа (выполнить первым, ничего не работает без этого)

```
Sprint 0 (2-3 дня):
  [ ] ТЗ-0.1: Унификация permission format (resource:action)
  [ ] ТЗ-0.2: Убрать дублирование security domains
  [ ] ТЗ-3.2: UnknownCollectionException → graceful deny
  [ ] ТЗ-3.5: dynamic → VaultStorage в AuthServerRepos
```

### Фаза 1: Функционал (основные фичи)

```
Sprint 1 (3-5 дней):
  [ ] ТЗ-1.1: HttpRoleManagementService + интеграция в AQSecurityService
  [ ] ТЗ-1.2: HttpPolicyService + HttpAuditService
  [ ] ТЗ-1.3: ResourcePermissionService подключить (убрать NoOp)
  [ ] ТЗ-1.4: logOperation реализовать (fire-and-forget)
```

### Фаза 2: Архитектура (сделать правильно)

```
Sprint 2 (2-3 дня):
  [ ] ТЗ-2.1: SecurityMode enum + документация двух режимов
  [ ] ТЗ-2.2: AqSecurity facade (единая инициализация)
  [ ] ТЗ-2.3: SessionKind в AqSession
  [ ] ТЗ-2.4: rbacCacheTtl в SecurityConfig
```

### Фаза 3: Качество (финальная полировка)

```
Sprint 3 (1-2 дня):
  [ ] ТЗ-3.1: Убрать SQLi regex (ложная защита)
  [ ] ТЗ-3.3: CORS header fix
  [ ] ТЗ-3.4: Переместить IUserRepository/IProfileRepository
  [ ] Переименовать i_data_layer_as_clietn_secure_protocol.dart → i_vault_security_protocol.dart
  [ ] Добавить register() в HttpAuthTransport
```

---

## ИТОГ

**Текущее состояние:** Архитектурно правильная система с незакрытыми критическими пробелами.  
Skeleton → 70%. Organs connected → 30%.

**После реализации ТЗ:** Полноценный security layer с:
- Тремя уровнями авторизации (RBAC + RLAC + PBAC)
- Единым Session Service для всех типов субъектов
- Двумя чёткими режимами работы (embedded/distributed)
- Полным аудитом всех операций
- Единой точкой инициализации
