# Подсессия 3 — Фаза 1B: ResourcePermissions + logOperation

**Источник:** AQ_SECURITY_ARCHITECTURE_REPORT.md → Часть 4, Приоритет 1 (ТЗ-1.3, ТЗ-1.4)

---

## Цель

Оживить защиту data layer: подключить реальный `ResourcePermissionService` вместо NoOp
и реализовать аудит операций (fire-and-forget).

---

## Предусловие

Подсессия 2 завершена, `dart analyze` → 0 errors.

---

## Задачи

### ТЗ-1.3: Подключить ResourcePermissionService (убрать NoOp)
**Проблема:** `AqVaultSecurityProtocol.resourcePermissions` → `_NoOpResourcePermissionService`. RLAC полностью не работает.

**Файл изменить:** `aq_security/lib/src/client/aq_vault_security_protocol.dart`

Принять `IResourcePermissionService` через конструктор:
```dart
AqVaultSecurityProtocol({
  required String introspectionEndpoint,
  required String encryptionKey,
  IResourcePermissionService? resourcePermissions,
});
```

`ResourcePermissionService` уже существует в `aq_security/lib/src/server/resource_permission_service.dart` — подключить его.

### ТЗ-1.4: Реализовать logOperation (аудит из data layer)
**Проблема:** `logOperation` — TODO/пусто. Аудит из data layer не пишется.

**Файл изменить:** `aq_security/lib/src/client/aq_vault_security_protocol.dart`

**Требования:**
- fire-and-forget через `unawaited()`
- если audit упал — логировать ошибку, НЕ пробрасывать
- POST к `/rbac/audit/access-logs` или через `HttpAuditService` из подсессии 2

```dart
@override
Future<void> logOperation({...}) async {
  if (claims == null) return;
  unawaited(_auditClient.logOperation(...).catchError((e) => _log.warning('Audit failed: $e')));
}
```

---

## Критерий завершения

- [ ] `resourcePermissions.grant()` / `revoke()` реально работают (не NoOp)
- [ ] `logOperation()` пишет аудит fire-and-forget
- [ ] Падение аудита не блокирует data layer операцию
- [ ] Тест: Mode A (embedded) и Mode B (distributed) для `AqVaultSecurityProtocol`
- [ ] `dart analyze` → 0 errors
- [ ] Заполнен `report.md`
