# Отчёт — Подсессия 1 (sub_1)

**Дата:** 2026-05-03  
**Фаза:** 0 — Блокирующие исправления  
**Статус:** ✅ Завершено

---

## Что сделано

### ТЗ-0.1: Унификация формата permissions
**Файл:** `aq_security/lib/src/rbac/access_control_engine.dart`

- `canAsync` — ключ кэша изменён с `'$resource:$action:$scope'` → `'$resource:$action'`, параметр `scope` стал опциональным (`String scope = ''`)
- `canSync` — убрано обращение к `split(':')[2]`
- `CachedDecision.isExpired` — убран хардкод `Duration(minutes: 5)`, добавлено поле `final Duration ttl`; `AccessCache.set` передаёт `ttl` при создании записи

### ТЗ-0.2: Убрать дублирование security domains
**Файл:** `aq_schema/lib/security/storable/security_domains.dart`

Удалён второй `DomainDescriptor` для `AqRole.kCollection = 'security_roles'`.  
Остался один — через `SecurityCollections.roles`. Значения идентичны.

### ТЗ-3.2: UnknownCollectionException → graceful deny
**Файл:** `aq_security/lib/src/client/aq_vault_security_protocol.dart`

- `_mapCollectionToResourceType` возвращает `ResourceType?` (null вместо throw)
- `_checkAccess` проверяет null → `AccessDecision.deny(reason: 'Unknown collection: $collection')`
- Класс `UnknownCollectionException` удалён

### ТЗ-3.5: dynamic → VaultStorage
**Файл:** `aq_security/lib/src/server/aq_auth_server.dart`

- Добавлен `import 'package:dart_vault/dart_vault.dart'`
- `final dynamic storage` → `final VaultStorage storage`

---

## dart analyze

| Пакет | Результат |
|-------|-----------|
| `aq_schema` | ✅ 0 errors |
| `aq_security` | ✅ 0 errors в изменённых файлах. `dart_vault` path отсутствует локально — pre-existing проблема окружения |

---

## Изменённые файлы

- `aq_security/lib/src/rbac/access_control_engine.dart`
- `aq_schema/lib/security/storable/security_domains.dart`
- `aq_security/lib/src/client/aq_vault_security_protocol.dart`
- `aq_security/lib/src/server/aq_auth_server.dart`
