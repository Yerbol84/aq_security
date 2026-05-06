# Analysis: Рефакторинг репозиториев — удаление зависимости от dart_vault

**Дата:** 2026-05-05

---

## Текущее состояние (до)

- `aq_security` напрямую зависел от `dart_vault` через 3 импорта в `vault_security_repositories.dart`
- `RBACVaultRoleRepository` дублировал `VaultRoleRepository` — две параллельные реализации одной бизнес-логики
- Три интерфейса (`RoleRepository`, `UserRoleRepository`, `PolicyRepository`) дублировали `IRoleRepository`, `IUserRoleRepository`, `IPolicyRepository` из `aq_schema`
- Все RBAC репозитории использовали `dynamic vault` — нет типизации, нет контракта
- `StorableAccessAlert` и `StorableRBACMetrics` отсутствовали в `aq_schema`

## Проблема

По правилам платформы пакеты не должны зависеть друг от друга напрямую — только через интерфейсы из `aq_schema`. `aq_security` и `dart_vault` — равноправные реализации, ни один не должен знать о другом.

## Риски

- Нельзя подменить хранилище без изменения `aq_security`
- `dynamic vault` — нет compile-time проверки, ошибки только в runtime
- Дублирование интерфейсов — два источника правды для одного контракта
