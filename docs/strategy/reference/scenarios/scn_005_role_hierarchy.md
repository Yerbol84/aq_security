# SCN-005: Иерархия ролей — Editor наследует права Viewer

**ID:** SCN-005  
**Тип:** Backend Flow  
**Субъект:** Аутентифицированный пользователь с ролью `editor`  
**Покрывает:** `AccessControlEngine._collectPermissionsRecursive`, `InMemoryRbacRoleRepository`

---

## Описание

Роль `editor` наследует от `viewer`. Пользователь с ролью `editor` должен автоматически получить права `viewer` без явного назначения.

---

## Предусловия

```dart
// Роли в InMemoryRbacRoleRepository:
final viewer = AqRole(
  id: 'role-viewer',
  name: 'viewer',
  permissions: ['projects:read', 'graphs:read'],
  isSystem: true,
  createdAt: now,
);

final editor = AqRole(
  id: 'role-editor',
  name: 'editor',
  permissions: ['projects:write', 'graphs:write'],
  inheritsFrom: ['role-viewer'],  // ← наследует от viewer
  isSystem: true,
  createdAt: now,
);

// Пользователь имеет только роль editor:
userRoleRepo.seed(AqUserRole(
  userId: 'user-1',
  roleId: 'role-editor',
  tenantId: 'tenant-1',
  grantedAt: now,
));
```

---

## Шаги

```dart
final engine = AccessControlEngine(
  roleRepository: roleRepo,
  userRoleRepository: userRoleRepo,
  policyRepository: policyRepo,
);

// 1. Проверить право из editor (прямое)
final canWrite = await engine.canAsync('user-1', 'projects', 'write');
assert(canWrite.allowed == true);
assert(canWrite.reason == 'Access granted');

// 2. Проверить право из viewer (унаследованное)
final canRead = await engine.canAsync('user-1', 'projects', 'read');
assert(canRead.allowed == true);  // ← должно быть true через наследование

// 3. Проверить право которого нет ни у editor ни у viewer
final canDelete = await engine.canAsync('user-1', 'projects', 'delete');
assert(canDelete.allowed == false);
assert(canDelete.reason!.contains('Permission denied'));

// 4. Проверить эффективные права (должны включать оба набора)
final effective = await engine.getEffectivePermissions('user-1');
assert(effective.contains('projects:read'));   // от viewer
assert(effective.contains('graphs:read'));     // от viewer
assert(effective.contains('projects:write'));  // от editor
assert(effective.contains('graphs:write'));    // от editor
```

---

## Ожидаемый результат

| Право | Результат | Источник |
|---|---|---|
| `projects:write` | ✅ allow | editor (прямое) |
| `projects:read` | ✅ allow | viewer (унаследованное) |
| `graphs:read` | ✅ allow | viewer (унаследованное) |
| `projects:delete` | ❌ deny | нет ни у кого |

---

## Проверка

`_collectPermissionsRecursive` должен обойти `editor` → `viewer` и собрать все 4 права.  
Защита от циклов: `processedRoles` предотвращает бесконечную рекурсию.
