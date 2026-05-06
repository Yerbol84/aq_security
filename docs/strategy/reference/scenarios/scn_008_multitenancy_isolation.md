# SCN-008: Мультитенантность — изоляция данных между tenant'ами

**ID:** SCN-008  
**Тип:** Backend Flow  
**Субъект:** Два пользователя из разных tenant'ов  
**Покрывает:** `AqTokenClaims.tid`, `InMemoryVaultSecurityProtocol.canRead`, `AqUserRole.tenantId`

---

## Описание

Пользователь из `tenant-A` не должен получить доступ к данным `tenant-B`, даже если у него есть роль `admin` в своём tenant'е.

---

## Предусловия

```dart
// Пользователь A — admin в tenant-A
final claimsA = AqTokenClaims(
  sub: 'user-a',
  tid: 'tenant-a',
  email: 'alice@a.com',
  type: TokenType.access,
  iat: now,
  exp: now + 900,
  jti: 'jti-a',
  sid: 'sid-a',
  roles: ['admin'],
);

// Пользователь B — viewer в tenant-b
final claimsB = AqTokenClaims(
  sub: 'user-b',
  tid: 'tenant-b',
  email: 'bob@b.com',
  type: TokenType.access,
  iat: now,
  exp: now + 900,
  jti: 'jti-b',
  sid: 'sid-b',
  roles: ['viewer'],
);

// Роли назначены только в рамках своего tenant
userRoleRepo.seed(AqUserRole(
  userId: 'user-a',
  roleId: 'role-admin',
  tenantId: 'tenant-a',  // ← только для tenant-a
  grantedAt: now,
));
```

---

## Шаги

```dart
final protocol = InMemoryVaultSecurityProtocol.withDefaults();

// 1. user-a читает данные своего tenant — разрешено
final readOwn = await protocol.canRead(
  claims: claimsA,
  collection: 'projects',
  entityId: 'proj-tenant-a-1',
);
assert(readOwn.allowed == true);

// 2. user-a пытается читать данные tenant-b
// В реальной системе: data layer передаёт claims из токена,
// claims.tid = 'tenant-a' — не совпадает с коллекцией tenant-b
// Проверка через RBAC: роль user-a назначена только в tenant-a
final readForeign = await engine.canAsync(
  'user-a',
  'projects',
  'read',
  context: AccessContext(
    userId: 'user-a',
    tenantId: 'tenant-b',  // ← чужой tenant
    userRoles: [],          // ← нет ролей в tenant-b
    userScopes: [],
    effectiveTimestamp: now,
  ),
);
assert(readForeign.allowed == false);
assert(readForeign.reason == 'User has no roles');

// 3. user-b читает свои данные — разрешено (viewer)
final readB = await protocol.canRead(
  claims: claimsB,
  collection: 'projects',
);
assert(readB.allowed == true);
```

---

## Ожидаемый результат

| Пользователь | Tenant запроса | Результат | Причина |
|---|---|---|---|
| user-a (admin) | tenant-a | ✅ allow | роль admin в tenant-a |
| user-a (admin) | tenant-b | ❌ deny | нет ролей в tenant-b |
| user-b (viewer) | tenant-b | ✅ allow | роль viewer в tenant-b |

---

## Проверка

Изоляция обеспечивается через `AqUserRole.tenantId` — роли назначаются в контексте конкретного tenant'а.  
`claims.tid` из JWT токена определяет tenant пользователя и не может быть подменён клиентом.
