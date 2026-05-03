# Исправление проблемы MetricsCollector

**Дата**: 2026-04-11
**Проблема**: Дублирование класса `MetricsCollector`
**Статус**: ✅ ИСПРАВЛЕНО

## Проблема

Проект не компилировался из-за конфликта имен:
```
Error: 'MetricsCollector' is exported from both
'package:aq_security/src/server/metrics/metrics_collector.dart' and
'package:aq_security/src/server/monitoring/metrics.dart'.
```

**Влияние**: 19 тестов не загружались из-за ошибки компиляции.

## Причина

В проекте существовало два класса с одинаковым именем `MetricsCollector`:

1. **RBAC MetricsCollector** (`lib/src/server/metrics/metrics_collector.dart`)
   - Создан в Week 1 для RBAC метрик
   - Собирает метрики проверок доступа, cache hits/misses, denials
   - Специфичен для RBAC системы

2. **Prometheus MetricsCollector** (`lib/src/server/monitoring/metrics.dart`)
   - Создан в Phase 5 для Prometheus метрик
   - Универсальный collector для любых метрик
   - Поддерживает counter, gauge, histogram

Оба класса экспортировались в `lib/aq_security_server.dart`, что создавало конфликт имен.

## Решение

Переименован старый класс `MetricsCollector` → `RbacMetricsCollector`:

### Измененные файлы

1. **lib/src/server/metrics/metrics_collector.dart**
   - `class MetricsCollector` → `class RbacMetricsCollector`

2. **lib/src/rbac/access_control_engine.dart**
   - `final MetricsCollector? metricsCollector` → `final RbacMetricsCollector? metricsCollector`

3. **lib/src/server/metrics/metrics_aggregator.dart**
   - `final MetricsCollector collector` → `final RbacMetricsCollector collector`
   - Обновлен комментарий в документации

## Результаты

### До исправления
- ❌ Проект не компилировался
- ❌ 19 тестов не загружались
- ❌ 148 passed, 21 failed

### После исправления
- ✅ Проект компилируется без ошибок
- ✅ Все тесты загружаются
- ✅ 346 passed, 12 failed

**Улучшение**: +198 тестов теперь работают!

### Оставшиеся проблемы

12 тестов все еще падают:
- 1 тест: `MockApiKeyRepository` - отсутствуют методы `listAll()` и `update()`
- 11 тестов: E2E тесты требуют запущенные серверы (ожидаемо)

## Проверка

```bash
# Проверка компиляции
dart analyze lib/aq_security_server.dart
# Result: No issues found!

# Запуск тестов
dart test
# Result: 346 passed, 12 failed
```

## Рекомендации

1. ✅ **ГОТОВО**: Проблема с MetricsCollector решена
2. ⏭️ **СЛЕДУЮЩЕЕ**: Исправить `MockApiKeyRepository` (добавить методы `listAll()` и `update()`)
3. ⏭️ **СЛЕДУЮЩЕЕ**: Документировать требование запущенных серверов для E2E тестов

---

**Автор**: Claude Opus 4.6
**Время исправления**: ~5 минут
**Статус**: ✅ ЗАВЕРШЕНО
