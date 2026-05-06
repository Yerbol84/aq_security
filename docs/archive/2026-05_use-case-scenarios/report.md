# Report: Use-Case Scenarios для aq_security

**Дата:** 2026-05-04  
**Статус:** ✅ Завершено

---

## Что сделано

### Оценка стратегии vs код

Стратегия в целом точная. Ключевые расхождения зафиксированы в analysis.md:
- `canSync` — заглушка (всегда false)
- `AccessCache` удалён → `IAQCache`
- HTTP RBAC клиент не реализован
- Analytics/Anomaly detection — Phase 3/4, не реализованы

### Созданные сценарии

| ID | Файл | Покрывает |
|---|---|---|
| SCN-005 | scn_005_role_hierarchy.md | `_collectPermissionsRecursive` |
| SCN-006 | scn_006_temporary_role_expiry.md | `AqUserRole.isExpired` |
| SCN-007 | scn_007_policy_ip_block.md | `_evaluateIpAddressCondition` |
| SCN-008 | scn_008_multitenancy_isolation.md | `AqUserRole.tenantId`, `claims.tid` |
| SCN-009 | scn_009_token_revocation.md | `TokenRevocationService` |
| SCN-010 | scn_010_batch_and_encryption.md | `canBatch`, `FieldEncryptionService` |

Все сценарии размещены в `docs/working/scenarios/` (→ перемещены в `strategy/reference/scenarios/`).

## Отклонений от плана нет.
