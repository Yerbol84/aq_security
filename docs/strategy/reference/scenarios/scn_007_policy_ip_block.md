# SCN-007: Policy Engine — IP-блокировка

**ID:** SCN-007  
**Тип:** Backend Flow  
**Субъект:** Пользователь с правами, но заблокированным IP  
**Покрывает:** `AccessControlEngine._evaluatePolicies`, `_evaluateIpAddressCondition`, `PolicyConditionType.ipAddress`

---

## Описание

Пользователь имеет роль `editor` и право `projects:write`. Но активна политика, блокирующая доступ с определённого IP. Несмотря на наличие прав — доступ запрещён.

---

## Предусловия

```dart
// Пользователь с ролью editor
userRoleRepo.seed(AqUserRole(
  userId: 'user-1',
  roleId: 'role-editor',
  tenantId: 'tenant-1',
  grantedAt: now,
));

// Политика: блокировать IP из blacklist
policyRepo.seed(AqAccessPolicy(
  id: 'policy-ip-block',
  name: 'Block suspicious IPs',
  priority: 100,
  enabled: true,
  statements: [
    PolicyStatement(
      effect: PolicyEffect.deny,
      conditions: [
        PolicyCondition(
          type: PolicyConditionType.ipAddress,
          operator: PolicyOperator.inList,
          value: ['1.2.3.4', '10.0.0.99'],
        ),
      ],
    ),
  ],
  createdAt: now,
));
```

---

## Шаги

```dart
// 1. Запрос с разрешённого IP — доступ есть
final allowedIp = AccessContext(
  userId: 'user-1',
  tenantId: 'tenant-1',
  ipAddress: '192.168.1.1',  // не в blacklist
  userRoles: ['editor'],
  userScopes: [],
  effectiveTimestamp: now,
);

final fromSafeIp = await engine.canAsync(
  'user-1', 'projects', 'write',
  context: allowedIp,
);
assert(fromSafeIp.allowed == true);

// 2. Запрос с заблокированного IP — доступ запрещён
final blockedIp = AccessContext(
  userId: 'user-1',
  tenantId: 'tenant-1',
  ipAddress: '1.2.3.4',  // в blacklist
  userRoles: ['editor'],
  userScopes: [],
  effectiveTimestamp: now,
);

final fromBlockedIp = await engine.canAsync(
  'user-1', 'projects', 'write',
  context: blockedIp,
);
assert(fromBlockedIp.allowed == false);
assert(fromBlockedIp.reason == 'Denied by policy: Block suspicious IPs');
assert(fromBlockedIp.appliedPolicies.contains('policy-ip-block'));
```

---

## Ожидаемый результат

| IP | Право `projects:write` | Причина |
|---|---|---|
| `192.168.1.1` | ✅ allow | IP не в blacklist, права есть |
| `1.2.3.4` | ❌ deny | IP в blacklist → политика DENY |

---

## Проверка

Policy Engine применяется **после** проверки прав. Даже если права есть — политика DENY имеет приоритет.  
`appliedPolicies` в `AccessDecision` содержит ID сработавшей политики.
