# Analysis: Use-Case Scenarios для aq_security

**Дата:** 2026-05-04  
**Статус:** В работе

---

## 1. Оценка стратегических документов

### RBAC_STRATEGY.md
**Что описано хорошо:**
- Архитектура компонентов (Roles, Permissions, Policies, Engine) — точно соответствует коду
- Формат прав `resource:action:scope` — реализован в `AqPermission`
- Wildcards (`projects:*:own`) — реализованы в `_checkPermission`
- Иерархия ролей с рекурсивным обходом — реализована в `_collectPermissionsRecursive`
- Временные роли (`expiresAt`) — реализованы в `AqUserRole.isExpired`
- Policy Engine с условиями (time, ip, mfa, role, scope) — реализован в `_evaluatePolicies`
- Кэширование через `IAQCache` — реализовано

**Расхождения стратегия → код:**
- Стратегия описывает `canSync` как "из кэша" — в коде всегда возвращает `false` (заглушка)
- Стратегия описывает `scope` как часть ключа кэша (`userId:resource:action:scope`) — в коде scope **не** входит в ключ (намеренно, по комментарию)
- Стратегия описывает `AccessCache` с `ttl` и `maxSize` — удалён, заменён на `IAQCache`
- Стратегия описывает `RBACClient` с HTTP API — не реализован (нет HTTP клиента для RBAC)
- Стратегия описывает `Analytics`, `Recommendations`, `Anomaly detection` — не реализованы (Phase 3/4)
- Стратегия описывает `ResourceType` enum с `workflows, blueprints, billing` — в коде `ResourceType` в `AqVaultSecurityProtocol` покрывает только `project, graph, instruction, prompt, dataset, model, apiKey, session`

**Что устарело:**
- Roadmap Phase 1/2 — уже выполнены
- `AccessCache` класс — удалён в пользу `IAQCache`
- `RBACClient` — не существует, клиент работает через `AqSecurityService`

### RBAC_business_logic.md
**Что описано хорошо:**
- Полный flow проверки доступа (6 шагов) — точно соответствует `canAsync`
- Описание кэш-ключа — соответствует коду
- Описание политик с примерами — соответствует `_evaluatePolicies`

**Расхождения:**
- Описывает `VaultUserRoleRepository` — в коде это `InMemoryUserRoleRepository` / абстрактный `UserRoleRepository`
- Описывает `AqSecurityClient` с HTTP — в коде это `AqSecurityService` (Dart, не HTTP клиент)

### PRODUCTION_READINESS_PLAN.md
- Исторический документ, описывает план который уже выполнен
- Актуален как справка по архитектурным решениям

---

## 2. Реальные возможности системы (из кода)

Что система **реально умеет** сейчас:

| Возможность | Реализация |
|---|---|
| Регистрация / логин email+password | `AuthRouter`, `UserService`, `PasswordService` |
| JWT access + refresh токены | `TokenIssuer`, `TokenCodec` |
| Логин через API Key | `ApiKeyService` |
| RBAC: роли + права + wildcards | `AccessControlEngine.canAsync` |
| Иерархия ролей (наследование) | `_collectPermissionsRecursive` |
| Временные роли (expiresAt) | `AqUserRole.isExpired` |
| Policy Engine (time, ip, mfa, role, scope) | `_evaluatePolicies` |
| Кэш решений (IAQCache) | `_cacheDecision` |
| Batch проверка прав | `canBatch` |
| VaultSecurityProtocol (data layer) | `AqVaultSecurityProtocol`, `InMemoryVaultSecurityProtocol` |
| Шифрование полей (AES-256-GCM) | `FieldEncryptionService` |
| Rate limiting | `RateLimiter` |
| Аудит (fire-and-forget) | `logOperation` |
| In-memory режим для тестов | `InMemoryVaultSecurityProtocol.withDefaults()` |
| Метрики (Prometheus) | `RbacMetricsCollector` |
| Алерты | `AlertGenerator` |

---

## 3. Пробелы в существующих сценариях (scn_001..004)

| Сценарий | Что не покрыто |
|---|---|
| SCN-001 | Нет проверки refresh token flow |
| SCN-002 | Нет проверки иерархии ролей (Editor наследует от Viewer) |
| SCN-002 | Нет проверки временной роли с истечением |
| SCN-002 | Нет проверки Policy Engine (ip, time, mfa) |
| SCN-003 | Нет проверки шифрования полей |
| SCN-003 | Нет проверки rate limiting |
| SCN-004 | Нет проверки batch прав |
| Все | Нет сценария мультитенантности (tid изоляция) |
| Все | Нет сценария отзыва токена |

---

## 4. Новые сценарии для создания

1. **SCN-005** — Иерархия ролей: Editor наследует права Viewer
2. **SCN-006** — Временная роль: истекает, доступ блокируется
3. **SCN-007** — Policy Engine: IP-блокировка
4. **SCN-008** — Мультитенантность: изоляция данных между tenant'ами
5. **SCN-009** — Отзыв токена: повторный запрос отклонён
6. **SCN-010** — Batch проверка прав + шифрование полей
