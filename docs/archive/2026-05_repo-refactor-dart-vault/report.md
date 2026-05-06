# Report: Рефакторинг репозиториев — удаление зависимости от dart_vault

**Дата:** 2026-05-05  
**Статус:** ✅ Завершено

---

## Результат

### aq_schema

- Добавлены методы в `IRoleRepository`: `findById`, `getAllRoles`, `saveRole`, `deleteRole`
- Добавлен `IUserRoleRepository`
- Добавлены методы в `IPolicyRepository`: `getEnabledPolicies`, `getAllPolicies`, `savePolicy`, `deletePolicy`, `findById`, `create`, `update`, `delete`, `findByTenant`, `findActive`
- Добавлены `StorableAccessAlert` и `StorableRBACMetrics` в `storable_rbac.dart`

### aq_security

| Файл | Изменение |
|---|---|
| `vault_security_repositories.dart` | Удалены 3 импорта `dart_vault`. Конструкторы принимают `DirectRepository<T>` / `LoggedRepository<T>` |
| `rbac_repositories.dart` | `dynamic vault` → `DirectRepository<StorableAqUserRole>`, `DirectRepository<StorableAqPolicy>`, `LoggedRepository<StorableAqAccessLog>`, `DirectRepository<StorableAccessAlert>`, `DirectRepository<StorableRBACMetrics>` |
| `access_control_engine.dart` | Удалены локальные `RoleRepository`, `UserRoleRepository`, `PolicyRepository`. Переключён на интерфейсы aq_schema |
| `rbac_service.dart` | Переключён на `IRoleRepository`, `IUserRoleRepository`, `IPolicyRepository`. `getRole` → `findById`, `getPolicy` → `findById` |
| `aq_auth_server.dart` | `AuthServerRepos.storage: dynamic` удалён. Добавлены `userRoles`, `policies`, `accessLogs` |
| `in_memory_repositories.dart` | `InMemoryRbacRoleRepository` удалён. Методы добавлены в `InMemoryRoleRepository`. `InMemoryUserRoleRepository` и `InMemoryPolicyRepository` переключены на новые интерфейсы |

## Проверка

- `dart analyze lib/` в `aq_schema` — **0 errors**
- `dart analyze lib/` в `aq_security` — **0 errors**
- `grep -r "dart_vault" lib/` в `aq_security` — только комментарии, нет импортов

## Tech debt закрыт

TECH_DEBT.md пункт "Дублирование репозиториев ролей" — **закрыт**.
