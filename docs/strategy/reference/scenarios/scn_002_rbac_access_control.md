# SCN-002: RBAC — Проверка прав доступа к ресурсу

**ID:** SCN-002  
**Тип:** Backend Flow  
**Субъект:** Аутентифицированный пользователь  
**Покрывает:** `AccessControlEngine`, `RBACService`, `IRoleManagementService`, `IVaultSecurityProtocol`

---

## Описание

Пользователь с ролью `editor` пытается прочитать и удалить проект. Чтение разрешено, удаление — нет.

---

## Pipeline

```
[Клиент]                    [AccessControlEngine]           [In-Memory RBAC Storage]
    │                               │                                │
    │── canAsync(userId,            │                                │
    │     'projects','read') ──────►│                                │
    │                               │── UserRoleRepository           │
    │                               │   .getUserRoles(userId) ──────►│
    │                               │◄─ [AqUserRole(roleId='editor')]│
    │                               │── RoleRepository               │
    │                               │   .getRole('editor') ─────────►│
    │                               │◄─ AqRole(permissions:          │
    │                               │     ['projects:read',          │
    │                               │      'projects:write']) ───────│
    │                               │── _checkPermission(            │
    │                               │     'projects:read') ──────────│
    │                               │   → true                       │
    │                               │── PolicyRepository             │
    │                               │   .getEnabledPolicies() ──────►│
    │                               │◄─ [] (нет политик) ────────────│
    │◄─ AccessDecision.allow ───────│                                │
    │                               │                                │
    │── canAsync(userId,            │                                │
    │     'projects','delete') ────►│                                │
    │                               │── _checkPermission(            │
    │                               │     'projects:delete') ────────│
    │                               │   → false                      │
    │◄─ AccessDecision.deny ────────│                                │
    │     reason: 'Permission       │                                │
    │     denied: projects:delete'  │                                │
```

---

## Клиентский userflow

1. Пользователь вошёл, имеет роль `editor`
2. UI запрашивает список проектов → `service.hasPermission('projects:read')` → `true` → показать список
3. UI показывает кнопку "Удалить" → `service.hasPermission('projects:delete')` → `false` → скрыть кнопку
4. Если пользователь всё равно пытается удалить (прямой API вызов) → сервер возвращает 403

## Серверный workflow

1. `POST /rbac/check` с `{userId, resource: 'projects', action: 'read'}`
2. `RBACService.can(userId, 'projects', 'read', scope)` → `AccessControlEngine.canAsync()`
3. Проверка кэша (`AccessCache`) → miss
4. `UserRoleRepository.getUserRoles(userId)` → роли пользователя
5. `_getEffectivePermissions(userRoles)` → все права с учётом иерархии
6. `_checkPermission('projects:read', effectivePermissions)` → match
7. `PolicyRepository.getEnabledPolicies()` → применить политики
8. Кэшировать решение с TTL из `SecurityConfig.rbacCacheTtl`
9. Вернуть `AccessDecision`

---

## In-memory реализация

Использует `InMemoryRoleRepository`, `InMemoryUserRoleRepository`, `InMemoryPolicyRepository`.  
Роль `editor` с правами `['projects:read', 'projects:write']` создаётся при инициализации.
