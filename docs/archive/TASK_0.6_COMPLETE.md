# Task 0.6: Исправить LoggedStorable суффикс ✅

## Проблема

В Production Readiness Plan упоминалась проблема:
> `rbac_access_logs__log` не существует, реальная таблица `rbac_access_logs_log`

## Анализ

Проверил весь код и обнаружил, что:

1. **dart_vault использует правильную конвенцию** - `_log` (одинарное подчёркивание)
2. **Нет использования `__log`** (двойное подчёркивание) в коде
3. **Проблема была в описании**, а не в реализации

### Подтверждение конвенции

**Файл:** `pkgs/dart_vault_package/lib/storage/logged_repository_impl.dart:53`
```dart
_logCollection = '${collection}_log',
```

**Файл:** `pkgs/dart_vault_package/lib/storage/postgres/postgres_schema_deployer.dart:418`
```sql
CREATE TABLE IF NOT EXISTS ${domain.collection}_log (
  id TEXT NOT NULL,
  tenant_id TEXT NOT NULL,
  data JSONB NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (id, tenant_id)
);
```

## Решение

Создан документ **LOGGED_STORABLE_CONVENTION.md** в `pkgs/dart_vault_package/` с чёткой фиксацией конвенции:

### Правило

**LoggedStorable добавляет суффикс `_log` (одинарное подчёркивание)**

### Примеры

| Основная таблица | Log таблица |
|------------------|-------------|
| `security_sessions` | `security_sessions_log` |
| `security_api_keys` | `security_api_keys_log` |
| `rbac_access_logs` | `rbac_access_logs_log` |
| `rbac_alerts` | `rbac_alerts_log` |

### ❌ НЕПРАВИЛЬНО
- `${collection}__log` (двойное подчёркивание)

### ✅ ПРАВИЛЬНО
- `${collection}_log` (одинарное подчёркивание)

## Проверка

```bash
# Поиск неправильного использования
grep -r "__log" . --include="*.dart"
# Результат: (no matches) ✅

# Поиск правильного использования
grep -r "_log" pkgs/dart_vault_package/lib/storage/logged_repository_impl.dart
# Результат: _logCollection = '${collection}_log', ✅
```

## Итог

✅ Конвенция подтверждена: `_log` (одинарное подчёркивание)
✅ Код использует правильную конвенцию
✅ Документация создана в LOGGED_STORABLE_CONVENTION.md
✅ Нет использования неправильного суффикса `__log`

**Статус:** ЗАВЕРШЕНО

**Примечание:** Проблема, описанная в плане, не существует в текущем коде. Возможно, она была исправлена ранее или описание было неточным.
