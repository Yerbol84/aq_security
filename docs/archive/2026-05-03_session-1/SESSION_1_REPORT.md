# AQ Security Layer — Итоговый отчёт Session 1

**Дата:** 2026-05-03  
**Пакеты:** `aq_schema` + `aq_security`  
**Стек:** Dart / Flutter / HTTP (Shelf)  
**Основание:** AQ_SECURITY_ARCHITECTURE_REPORT.md  
**Статус:** ✅ Все 5 подсессий завершены

---

## Контекст

До начала работы security layer находился в состоянии "скелет без органов": архитектура была правильно спроектирована, но критические части либо не работали (`UnimplementedError`), либо работали неправильно (несовместимые форматы, NoOp-заглушки, ложные защиты). Согласно отчёту, функциональность была закрыта примерно на 30%.

Работа была разбита на 4 фазы (0–3) и выполнена в 5 подсессиях.

---

## Фаза 0 — Блокирующие исправления (sub_1)

Эти проблемы делали систему нерабочей независимо от остального кода.

### Permission format (ТЗ-0.1)
**Проблема:** В одном пакете сосуществовали три несовместимых формата:
- `AqRole.hasPermission()` ожидал `resource:action`
- `AccessControlEngine.canAsync()` строил ключ как `resource:action:scope`
- `canSync` читал `split(':')[2]` (несуществующий третий сегмент)

Это означало, что RBAC-проверки в runtime давали неверные результаты: ключ кэша не совпадал с ключом проверки, и доступ мог быть как ложно разрешён, так и ложно запрещён.

**Решение:** Зафиксирован единственный формат `resource:action`. Scope выведен в `AccessContext.userScopes` — отдельный механизм, не часть ключа. Параметр `scope` в `canAsync` стал опциональным с дефолтом `''` для обратной совместимости.

Попутно исправлен `CachedDecision.isExpired` — убран хардкод `Duration(minutes: 5)`, TTL теперь хранится в самой записи и передаётся из `AccessCache`.

### Дублирование security domains (ТЗ-0.2)
**Проблема:** В `AqSecurityDomains.all` было два `DomainDescriptor` на коллекцию `security_roles` — через `SecurityCollections.roles` и через `AqRole.kCollection`. При развёртывании `VaultRegistry` это вызвало бы конфликт при создании таблиц.

**Решение:** Удалён второй дескриптор. Оставлен один — через `SecurityCollections.roles`.

### Graceful deny для неизвестных коллекций (ТЗ-3.2)
**Проблема:** `_mapCollectionToResourceType` бросал `UnknownCollectionException` для любой коллекции вне switch. Добавление новой коллекции в data layer без обновления security layer роняло production с необработанным исключением.

**Решение:** Метод возвращает `ResourceType?`. Значение `null` в `_checkAccess` → `AccessDecision.deny`. Принцип наименьших привилегий: неизвестное = запрещено, не исключение.

### Типизация storage (ТЗ-3.5)
**Проблема:** `AuthServerRepos.storage: dynamic` — критическая часть инициализации сервера безопасности принимала любой тип. Ошибки типов проходили через анализатор и падали в runtime.

**Решение:** `final dynamic storage` → `final VaultStorage storage`. Импорт `dart_vault` уже был в зависимостях пакета.

---

## Фаза 1 — Критический функционал (sub_2, sub_3)

### HTTP клиенты для RBAC/Policy/Audit (sub_2, ТЗ-1.1, ТЗ-1.2)
**Проблема:** Геттеры `roleManagement`, `policies`, `audit` в `AQSecurityService` бросали `UnimplementedError`. Весь RBAC жил только на сервере в `AQAuthServer`. Клиент не мог управлять ролями, политиками или читать аудит.

**Решение:** Созданы три HTTP-клиента:

- `HttpRoleManagementService` — 10 методов, покрывает полный CRUD ролей и назначений
- `HttpPolicyService` — CRUD политик + evaluate/test
- `HttpAuditService` — запись и чтение логов

Все три интегрированы в `AQSecurityService` через конструктор. `create()` factory создаёт их автоматически с `tokenProvider` из `LocalSessionStore`.

Важное решение по `HttpAuditService`: методы `logAccess()` и `logAudit()` реализованы как **fire-and-forget** через `unawaited()` с `.catchError()`. Аудит не должен блокировать основной поток и не должен ронять операцию при сбое сети.

### ResourcePermissionService + logOperation (sub_3, ТЗ-1.3, ТЗ-1.4)
**Проблема:** RLAC (Resource-Level Access Control) был полностью мёртв — `resourcePermissions` геттер возвращал `_NoOpResourcePermissionService` (~70 строк заглушки). `logOperation` содержал пустой TODO.

**Решение для RLAC:** `IResourcePermissionService?` принимается через конструктор `AqVaultSecurityProtocol`. Геттер бросает `StateError` если сервис не передан — явная ошибка лучше тихого NoOp. `_NoOpResourcePermissionService` удалён полностью.

**Решение для logOperation:** Реализован через `unawaited(http.post(...).catchError(...))` к `auditEndpoint`. Если `claims == null` или endpoint не задан — silent return. Аудит не блокирует data layer операцию ни при каких условиях.

---

## Фаза 2 — Архитектурные улучшения (sub_4)

### SecurityMode enum (ТЗ-2.1)
**Проблема:** Два режима работы security layer (embedded/distributed) нигде не были задекларированы явно. Это создавало неопределённость при интеграции.

**Решение:** Создан `enum SecurityMode { embedded, distributed }` в `aq_schema/lib/security/models/security_mode.dart`, экспортирован из `security.dart`. Каждый режим задокументирован.

### SessionKind в AqSession (ТЗ-2.3)
**Проблема:** Сессии пользователей, сервисных аккаунтов, графов и воркеров хранились без различия типа субъекта. Это затрудняло применение разных политик к разным типам сессий.

**Решение:** Добавлен `enum SessionKind { human, service, workflow, worker }` и поле `kind` в `AqSession` (default = `human`). Backward compatible: `fromJson` использует `orElse: () => SessionKind.human`. `toJson` сериализует `kind.name`.

### rbacCacheTtl в SecurityConfig (ТЗ-2.4)
**Проблема:** TTL кэша RBAC-решений был захардкожен в `AccessCache` как 5 минут. При отзыве роли пользователь ещё 5 минут сохранял доступ. Значение нельзя было изменить без правки кода.

**Решение:** Добавлено поле `rbacCacheTtl` в `SecurityConfig` (default: 1 минута — более безопасный дефолт). `AQAuthServer` передаёт `config.rbacCacheTtl` в `AccessCache`.

### AqSecurity facade (ТЗ-2.2)
**Проблема:** Три синглтона (`ISecurityService`, `IAuthContext`, `IVaultSecurityProtocol`) инициализировались разрозненно. Нигде не было задокументировано что их нужно инициализировать вместе и в правильном порядке. Риск частичной инициализации.

**Решение:** Создан `AqSecurity.init()` — единственная точка входа. Внутри последовательно:
1. `setSecurityServiceInstance(service)`
2. `IAuthContext.initialize(_AqAuthContextImpl(service))`
3. `IVaultSecurityProtocol.initialize(...)` — только если передан `encryptionKey`

`_AqAuthContextImpl` — приватная реализация `IAuthContext` поверх `AQSecurityService`, не требует отдельного класса снаружи.

---

## Фаза 3 — Качество и безопасность (sub_5)

### Удаление ложной SQLi защиты (ТЗ-3.1)
**Проблема:** `_containsSqlInjection()` в `validateData()` использовал regex для обнаружения SQL injection. Это создавало два риска: (а) ложные срабатывания на легитимных данных (апостроф в имени O'Brien), (б) ложное ощущение безопасности — реальный SQLi через unicode/encoding проходил.

**Решение:** Метод удалён полностью. Добавлен комментарий с обоснованием: SQL injection предотвращается параметризованными запросами в data layer, не regex в security layer.

### CORS header (ТЗ-3.3)
**Проблема:** При неразрешённом origin сервер возвращал `'Access-Control-Allow-Origin': ''`. Браузеры обрабатывают пустую строку непредсказуемо — некоторые трактуют её как разрешение.

**Решение:** Заголовок не добавляется вовсе если origin не разрешён (`if (isAllowed) 'Access-Control-Allow-Origin': origin`).

### Переименование файла (ТЗ-3.4 + rename)
`i_data_layer_as_clietn_secure_protocol.dart` (опечатка в названии) переименован в `i_vault_security_protocol.dart`. Старый файл заменён на re-export для обратной совместимости. Обновлены все 3 импорта в проекте.

`IUserRepository` и `IProfileRepository` уже находились в отдельном `i_user_repository.dart` — задача была выполнена ранее.

### register() в HttpAuthTransport (ТЗ-3.5)
`IAuthTransport` объявлял `register()`, но `HttpAuthTransport` его не реализовывал. `AQSecurityService.register()` бросал `UnimplementedError`. Добавлен `POST /auth/register` в транспорт, сервис подключён.

---

## Итоговая матрица изменений

| # | Проблема из отчёта | Критичность | Статус |
|---|-------------------|-------------|--------|
| 1 | roleManagement/policies/audit — UnimplementedError | 🔴 CRITICAL | ✅ Исправлено |
| 2 | _NoOpResourcePermissionService (RLAC мёртв) | 🔴 CRITICAL | ✅ Исправлено |
| 3 | Permission format несоответствие | 🔴 CRITICAL | ✅ Исправлено |
| 4 | logOperation — TODO пусто | 🔴 CRITICAL | ✅ Исправлено |
| 5 | Дублирование security domains | 🟠 HIGH | ✅ Исправлено |
| 6 | AuthServerRepos.storage: dynamic | 🟠 HIGH | ✅ Исправлено |
| 7 | Три синглтона без порядка инициализации | 🟠 HIGH | ✅ Исправлено |
| 8 | SQL injection "защита" через regex | 🟠 HIGH | ✅ Исправлено |
| 9 | UnknownCollectionException без fallback | 🟠 HIGH | ✅ Исправлено |
| 10 | Два режима безопасности не задекларированы | 🟠 HIGH | ✅ Исправлено |
| 11 | AccessCache TTL хардкодирован | 🟡 MEDIUM | ✅ Исправлено |
| 12 | CORS: пустая строка вместо отсутствия заголовка | 🟡 MEDIUM | ✅ Исправлено |
| 17 | Опечатка в имени файла | 🟢 LOW | ✅ Исправлено |
| 18 | IUserRepository в неправильном файле | 🟢 LOW | ✅ Уже было исправлено |

**Не затронуто в этой сессии (требуют отдельной работы):**

| # | Проблема | Критичность | Причина |
|---|----------|-------------|---------|
| 13 | IAuthContext не используется в VaultSecurityProtocol | 🟡 MEDIUM | Архитектурное решение — два механизма (headers vs context) требуют отдельного анализа |
| 14 | Нет refresh token rotation/reuse detection | 🟡 MEDIUM | Требует изменений в TokenIssuer + SessionService |
| 15 | Нет MFA auth flow | 🟡 MEDIUM | Новая функциональность, отдельная сессия |
| 16 | In-memory AccessCache не масштабируется | 🟡 MEDIUM | Требует Redis интеграции |

---

## Состояние dart analyze

Во всех пакетах присутствуют pre-existing ошибки разрешения зависимостей (`dart_vault` path dependency указывает на `../dart_vault_package` которого нет в текущем окружении). Это проблема окружения, не кода — подтверждено тем, что оригинальные файлы до наших изменений имели те же ошибки.

Все файлы, созданные или изменённые в этой сессии, синтаксически корректны и проходят анализ в изолированном режиме.

---

## Изменённые файлы (полный список)

**aq_schema:**
- `lib/security/storable/security_domains.dart` — удалён дубликат domain
- `lib/security/models/security_mode.dart` — создан (новый)
- `lib/security/models/aq_session.dart` — SessionKind добавлен
- `lib/security/security.dart` — обновлены экспорты
- `lib/security/interfaces/clients_protocols/i_vault_security_protocol.dart` — создан (переименование)
- `lib/security/interfaces/clients_protocols/i_data_layer_as_clietn_secure_protocol.dart` — re-export

**aq_security:**
- `lib/src/rbac/access_control_engine.dart` — permission format, TTL
- `lib/src/client/aq_vault_security_protocol.dart` — graceful deny, resourcePermissions, logOperation, SQLi удалён
- `lib/src/client/aq_security_service.dart` — три сервиса интегрированы, register() реализован
- `lib/src/client/aq_security.dart` — создан (facade, новый)
- `lib/src/client/http_role_management_service.dart` — создан (новый)
- `lib/src/client/http_policy_service.dart` — создан (новый)
- `lib/src/client/http_audit_service.dart` — создан (новый)
- `lib/src/client/http_auth_transport.dart` — register() добавлен
- `lib/src/server/aq_auth_server.dart` — VaultStorage, CORS fix, rbacCacheTtl
- `lib/src/shared/security_config.dart` — rbacCacheTtl добавлен
- `example/vault_security_protocol_example.dart` — обновлён импорт
