# Подсессия 1 — Фаза 0: Блокирующие исправления

**Источник:** AQ_SECURITY_ARCHITECTURE_REPORT.md → Часть 4, Приоритет 0 + Часть 5, Фаза 0

---

## Цель

Устранить критические проблемы, без которых система не работает вообще.
После этой подсессии `dart analyze` должен показывать 0 errors в обоих пакетах.

---

## Задачи

### ТЗ-0.1: Унификация формата permissions
**Проблема:** три места с разным форматом — `resource:action` vs `resource:action:scope`
**Файлы:**
- `aq_security/lib/src/rbac/access_control_engine.dart` — исправить `'$resource:$action:$scope'` → `'$resource:$action'`
- `aq_schema/lib/security/interfaces/i_role_management_service.dart` — добавить документацию формата
**Правило:** scope передаётся через `AccessContext.userScopes`, НЕ встраивается в permission key

### ТЗ-0.2: Убрать дублирование security domains
**Проблема:** два дескриптора на коллекцию `security_roles` в `AqSecurityDomains.all`
**Файлы:**
- `aq_schema/lib/security/storable/security_domains.dart` — убрать дубликат
- `aq_schema/lib/security/storable/security_storables.dart` — проверить `SecurityCollections.roles`

### ТЗ-3.2: UnknownCollectionException → graceful deny
**Проблема:** неизвестная коллекция бросает Exception вместо DENY
**Файл:** `aq_security/lib/src/client/aq_vault_security_protocol.dart`
**Решение:** `default: return AccessDecision.deny(reason: 'Unknown collection: $collection')`

### ТЗ-3.5: dynamic → типизировать AuthServerRepos.storage
**Проблема:** `final dynamic storage` в критической части инициализации сервера
**Файл:** `aq_security/lib/src/server/aq_auth_server.dart`
**Решение:** заменить `dynamic` на конкретный тип `VaultStorage`

---

## Критерий завершения

- [ ] `dart analyze` в `aq_schema` → 0 errors
- [ ] `dart analyze` в `aq_security` → 0 errors
- [ ] Все тесты проходят (если есть)
- [ ] Заполнен `report.md`
