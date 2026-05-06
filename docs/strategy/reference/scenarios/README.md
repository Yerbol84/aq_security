# Сценарии использования aq_security

Каждый сценарий — исполнимый use-case с реальными вызовами кода через `InMemoryVaultSecurityProtocol` и `InMemoryRepositories`.

## Список сценариев

| ID | Название | Покрывает |
|---|---|---|
| [SCN-001](scn_001_user_registration_login.md) | Регистрация и вход | `ISecurityService`, `TokenIssuer` |
| [SCN-002](scn_002_rbac_access_control.md) | RBAC: проверка прав | `AccessControlEngine.canAsync` |
| [SCN-003](scn_003_vault_security_protocol.md) | Data Layer: VaultSecurityProtocol | `IVaultSecurityProtocol` |
| [SCN-004](scn_004_service_account_api_key.md) | Сервисный аккаунт: API Key | `ApiKeyService` |
| [SCN-005](scn_005_role_hierarchy.md) | Иерархия ролей | `_collectPermissionsRecursive` |
| [SCN-006](scn_006_temporary_role_expiry.md) | Временная роль: истечение | `AqUserRole.isExpired` |
| [SCN-007](scn_007_policy_ip_block.md) | Policy Engine: IP-блокировка | `_evaluateIpAddressCondition` |
| [SCN-008](scn_008_multitenancy_isolation.md) | Мультитенантность | `AqUserRole.tenantId`, `claims.tid` |
| [SCN-009](scn_009_token_revocation.md) | Отзыв токена | `TokenRevocationService` |
| [SCN-010](scn_010_batch_and_encryption.md) | Batch права + шифрование | `canBatch`, `FieldEncryptionService` |
