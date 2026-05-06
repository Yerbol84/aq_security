# aq_security — Документация

## Структура

```
docs/
├── working/        # Активные рабочие папки (сейчас пусто)
├── strategy/       # Стратегические документы и справочники
│   ├── reference/  # Справочники (runbooks, scenarios, guides)
│   └── *.md        # Стратегия, tech debt, планы
└── archive/        # Завершённые рабочие папки
```

## strategy/

| Файл / Папка | Описание |
|---|---|
| `RBAC_STRATEGY.md` | Стратегия системы ролей и прав |
| `RBAC_business_logic.md` | Полная бизнес-логика RBAC |
| `PRODUCTION_READINESS_PLAN.md` | Production Readiness Plan v1.0 |
| `MIGRATION_PLAN.md` | План миграции на TTL/VersionedStorable (заблокирован) |
| `TECH_DEBT.md` | Актуальный tech debt |
| `reference/` | Справочники |

## strategy/reference/

| Папка / Файл | Описание |
|---|---|
| `scenarios/` | Use-case сценарии SCN-001..010 |
| `runbooks/` | Runbooks для production инцидентов |
| `operations/` | Disaster recovery plan |
| `INTEGRATION_GUIDE.md` | Интеграция с dart_vault Data Layer |
| `VAULT_SECURITY_PROTOCOL.md` | AqVaultSecurityProtocol — API |
| `API_KEYS.md` | Управление API ключами |
| `LOGGING_AND_TRACING.md` | Structured logging и tracing |
| `PROMETHEUS_METRICS.md` | Prometheus метрики |
| `TROUBLESHOOTING.md` | Диагностика проблем |
| `AQ_SECURITY_ARCHITECTURE_REPORT.md` | Архитектурный отчёт |
| `SESSION_1_REPORT.md` | Итоговый отчёт Session 1 |

## Правило рабочих папок

Каждая большая работа = одна папка в `working/YYYY-MM_name/`.  
Обязательные файлы: `analysis.md` → `plan.md` → `report.md`.  
После завершения — вся папка целиком переезжает в `archive/`.  
Подробнее: `aq_platform_ai_rules/documentation_rules.xml`
