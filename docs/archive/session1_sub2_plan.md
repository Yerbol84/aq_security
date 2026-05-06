# Подсессия 2 — Фаза 1A: HTTP клиенты для RBAC / Policy / Audit

**Источник:** AQ_SECURITY_ARCHITECTURE_REPORT.md → Часть 4, Приоритет 1 (ТЗ-1.1, ТЗ-1.2)

---

## Цель

Подключить клиентский `AQSecurityService` к серверному RBAC через HTTP transport.
Устранить `UnimplementedError` в геттерах `roleManagement`, `policies`, `audit`.

---

## Предусловие

Подсессия 1 завершена, `dart analyze` → 0 errors.

---

## Задачи

### ТЗ-1.1: HttpRoleManagementService
**Создать файл:** `aq_security/lib/src/client/http_role_management_service.dart`

Реализует `IRoleManagementService` через HTTP к endpoints сервера:
- `GET /rbac/roles` → `getRoles()`
- `POST /rbac/roles` → `createRole()`
- `PUT /rbac/roles/:id` → `updateRole()`
- `DELETE /rbac/roles/:id` → `deleteRole()`
- `POST /rbac/roles/:id/assign` → `assignRole()`
- `DELETE /rbac/roles/:id/revoke` → `revokeRole()`
- `GET /rbac/users/:id/roles` → `getUserRoles()`

**Интегрировать в:** `AQSecurityService` — добавить поле `_roleManagement`, вернуть из геттера вместо `UnimplementedError`

### ТЗ-1.2: HttpPolicyService
**Создать файл:** `aq_security/lib/src/client/http_policy_service.dart`

Реализует `IPolicyService` через HTTP:
- `GET /rbac/policies` → `getPolicies()`
- `POST /rbac/policies` → `createPolicy()`
- `PUT /rbac/policies/:id` → `updatePolicy()`
- `DELETE /rbac/policies/:id` → `deletePolicy()`

**Интегрировать в:** `AQSecurityService` — геттер `policies`

### ТЗ-1.3: HttpAuditService
**Создать файл:** `aq_security/lib/src/client/http_audit_service.dart`

Реализует `IAuditService` через HTTP:
- `GET /rbac/audit/access-logs` → `getAccessLogs()`
- `GET /rbac/audit/trail` → `getAuditTrail()`

**Интегрировать в:** `AQSecurityService` — геттер `audit`

---

## Критерий завершения

- [ ] `ISecurityService.roleManagement.getRoles()` не бросает `UnimplementedError`
- [ ] `ISecurityService.policies` не бросает `UnimplementedError`
- [ ] `ISecurityService.audit` не бросает `UnimplementedError`
- [ ] Unit тесты для каждого HttpXxxService с mock HTTP server
- [ ] `dart analyze` → 0 errors
- [ ] Заполнен `report.md`
