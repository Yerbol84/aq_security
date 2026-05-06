# SCN-006: Временная роль — истекает, доступ блокируется

**ID:** SCN-006  
**Тип:** Backend Flow  
**Субъект:** Пользователь с временной ролью  
**Покрывает:** `AqUserRole.isExpired`, `RBACService.assignTemporaryRole`, `AccessControlEngine._getEffectivePermissions`

---

## Описание

Пользователю выдаётся временная роль `admin` на короткий срок. После истечения срока доступ автоматически блокируется без явного отзыва.

---

## Предусловия

```dart
// Пользователь без ролей
userRoleRepo.seed(AqUserRole(
  userId: 'user-1',
  roleId: 'role-viewer',
  tenantId: 'tenant-1',
  grantedAt: now,
  // expiresAt не задан — постоянная роль
));

// Роль admin с широкими правами
roleRepo.seed(AqRole(
  id: 'role-admin',
  name: 'admin',
  permissions: ['*:*'],
  isSystem: true,
  createdAt: now,
));
```

---

## Шаги

```dart
final rbacService = RBACService(
  engine: engine,
  userRoleRepository: userRoleRepo,
  roleRepository: roleRepo,
);

// 1. До выдачи временной роли — нет admin прав
final before = await engine.canAsync('user-1', 'users', 'delete');
assert(before.allowed == false);

// 2. Выдать временную роль на 1 секунду
await rbacService.assignTemporaryRole(
  userId: 'user-1',
  roleId: 'role-admin',
  tenantId: 'tenant-1',
  duration: const Duration(seconds: 1),
  reason: 'Emergency access',
);

// 3. Сразу после выдачи — доступ есть
final during = await engine.canAsync('user-1', 'users', 'delete');
assert(during.allowed == true);

// 4. Подождать истечения
await Future.delayed(const Duration(seconds: 2));

// 5. После истечения — доступ заблокирован
// AqUserRole.isExpired возвращает true → роль пропускается в _getEffectivePermissions
final after = await engine.canAsync('user-1', 'users', 'delete');
assert(after.allowed == false);
assert(after.reason!.contains('Permission denied'));
```

---

## Ожидаемый результат

| Момент | Право `users:delete` | Причина |
|---|---|---|
| До выдачи | ❌ deny | нет роли admin |
| Сразу после выдачи | ✅ allow | временная роль активна |
| После истечения | ❌ deny | `AqUserRole.isExpired == true` |

---

## Проверка

`_getEffectivePermissions` фильтрует роли через `if (userRole.isExpired) continue`.  
Никакого явного отзыва не требуется — истечение автоматическое.
