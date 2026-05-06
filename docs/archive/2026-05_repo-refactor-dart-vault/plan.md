# Plan: Рефакторинг репозиториев — удаление зависимости от dart_vault

**Дата:** 2026-05-05

---

## Шаги

1. ✅ Удалить `RBACVaultRoleRepository` — заменить на `VaultRoleRepository`
2. ✅ Добавить `findById`, `getAllRoles`, `saveRole`, `deleteRole` в `IRoleRepository` (aq_schema)
3. ✅ Добавить `IUserRoleRepository` в aq_schema
4. ✅ Добавить методы `IPolicyRepository` в aq_schema
5. ✅ Удалить локальные интерфейсы `RoleRepository`, `UserRoleRepository`, `PolicyRepository` из `access_control_engine.dart`
6. ✅ Переключить `AccessControlEngine` и `RBACService` на интерфейсы из aq_schema
7. ✅ Переключить конструкторы репозиториев с `VaultStorage` на `DirectRepository<T>` / `LoggedRepository<T>`
8. ✅ Удалить все 3 импорта `dart_vault` из `vault_security_repositories.dart`
9. ✅ Добавить `StorableAccessAlert`, `StorableRBACMetrics` в aq_schema
10. ✅ Перевести `VaultAlertRepository`, `VaultAlertRepositoryImpl`, `VaultMetricsRepository` на `DirectRepository<T>`
11. ✅ Обновить `AuthServerRepos` — убрать `dynamic storage`, добавить типизированные поля
12. ✅ dart analyze — 0 errors в обоих пакетах

## Критерии готовности

- Нет импортов `dart_vault` в `lib/` aq_security
- Нет `dynamic` в репозиториях
- 0 errors в dart analyze
