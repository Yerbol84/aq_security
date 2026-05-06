# Plan: Use-Case Scenarios для aq_security

**Дата:** 2026-05-04

---

## Цель

1. Оценить стратегические документы на соответствие реальному коду
2. Создать исполнимые use-case сценарии для примеров и тестирования (SCN-005..010)

## Шаги

1. ✅ Прочитать RBAC_STRATEGY.md, RBAC_business_logic.md, PRODUCTION_READINESS_PLAN.md
2. ✅ Сравнить с реальным кодом (AccessControlEngine, InMemoryRepositories, VaultSecurityProtocol)
3. ✅ Зафиксировать расхождения в analysis.md
4. ✅ Создать SCN-005 — иерархия ролей
5. ✅ Создать SCN-006 — временная роль
6. ✅ Создать SCN-007 — Policy Engine IP-блокировка
7. ✅ Создать SCN-008 — мультитенантность
8. ✅ Создать SCN-009 — отзыв токена
9. ✅ Создать SCN-010 — batch права + шифрование полей
10. ✅ Обновить README сценариев

## Критерии готовности

- Все сценарии написаны с реальными вызовами кода через InMemoryVaultSecurityProtocol
- Каждый сценарий покрывает конкретный механизм безопасности
- README обновлён
