# SCN-003: Data Layer — Защита операций через IVaultSecurityProtocol

**ID:** SCN-003  
**Тип:** Backend Flow (data layer integration)  
**Субъект:** Data layer (dart_vault) как клиент security layer  
**Покрывает:** `IVaultSecurityProtocol`, `InMemoryVaultSecurityProtocol`, `AqVaultSecurityProtocol`

---

## Описание

Data layer перед каждой операцией спрашивает security layer: "Можно?".  
Security layer отвечает: Allow / Deny / Restricted.  
Data layer не знает о JWT, ролях, политиках — только о решении.

---

## Pipeline

```
[Data Layer]                    [IVaultSecurityProtocol]         [Security Engine]
    │                                   │                               │
    │── extractClaims(headers) ────────►│                               │
    │◄─ AqTokenClaims? ────────────────│                               │
    │                                   │                               │
    │── canRead(claims,                 │                               │
    │     collection:'projects',        │                               │
    │     entityId:'proj-1') ──────────►│                               │
    │                                   │── introspect(token,           │
    │                                   │     resource:'project',       │
    │                                   │     action:'read') ──────────►│
    │                                   │◄─ {active:true, allowed:true}─│
    │◄─ AccessDecision.allow ──────────│                               │
    │                                   │                               │
    │── [выполнить чтение из БД] ───────│                               │
    │                                   │                               │
    │── logOperation(claims,            │                               │
    │     operation:'read',             │                               │
    │     collection:'projects',        │                               │
    │     success:true) ───────────────►│ (fire-and-forget)             │
    │                                   │── unawaited(POST /audit) ────►│
    │                                   │                               │
    │── canWrite(claims,                │                               │
    │     collection:'admin_settings',  │                               │
    │     data:{...}) ─────────────────►│                               │
    │                                   │── _mapCollection → null       │
    │◄─ AccessDecision.deny ───────────│  (unknown collection)         │
    │     reason: 'Unknown collection'  │                               │
```

---

## Клиентский userflow

Клиент (Flutter/worker) не взаимодействует с протоколом напрямую.  
Протокол прозрачен — data layer вызывает его автоматически перед каждой операцией.

## Серверный workflow

1. HTTP запрос приходит в data layer с `Authorization: Bearer <token>`
2. `IVaultSecurityProtocol.instance.extractClaims(headers)` → `AqTokenClaims?`
3. Если `claims == null` → `AccessDecision.deny('Anonymous access not allowed')`
4. `canRead/canWrite/canDelete(claims, collection, entityId)` → `AccessDecision`
5. Если `deny` → вернуть 403, не выполнять операцию
6. Если `allow` → выполнить операцию
7. `logOperation(...)` → fire-and-forget аудит

## In-memory режим (embedded)

`InMemoryVaultSecurityProtocol` — реализация для тестов и разработки:
- `extractClaims` — декодирует токен без HTTP (локально)
- `canRead/canWrite/canDelete` — проверяет права через in-memory RBAC
- `logOperation` — пишет в список в памяти
- `validateData` — только размер, без сети
- Нет зависимости на HTTP, нет introspection endpoint

---

## Два режима

| Режим | Реализация | Когда |
|-------|-----------|-------|
| `embedded` | `InMemoryVaultSecurityProtocol` | Тесты, разработка, примеры |
| `distributed` | `AqVaultSecurityProtocol` | Production (HTTP introspection) |
