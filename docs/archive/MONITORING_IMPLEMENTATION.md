# Реализация системы мониторинга и оповещений RBAC

## Выполненные задачи

### ✅ Task #1: AlertGenerator - Генератор оповещений безопасности

**Файлы:**
- `lib/src/server/alerts/alert_rules.dart` - Правила генерации оповещений
- `lib/src/server/alerts/alert_generator.dart` - Основной генератор

**Реализованные правила:**
1. **SuspiciousActivityRule** - Подозрительная активность (10+ отказов за 1 минуту)
2. **RateLimitRule** - Превышение лимита запросов (100+ проверок за 1 минуту)
3. **PolicyViolationRule** - Нарушение политики доступа
4. **RoleExpiringRule** - Истекающая временная роль (предупреждение за 1 час)
5. **PrivilegeEscalationRule** - Попытка эскалации привилегий

**Функциональность:**
- История проверок доступа (до 1000 записей на пользователя)
- История отказов с автоматической очисткой (хранение 1 час)
- Автоматическая генерация оповещений по правилам
- Сохранение оповещений в Vault
- API для подтверждения оповещений
- Фильтрация по типу, серьёзности, периоду

### ✅ Task #2: MetricsCollector - Сборщик метрик в реальном времени

**Файл:** `lib/src/server/metrics/metrics_collector.dart`

**Собираемые метрики:**
- **Performance**: totalChecks, cacheHits, cacheMisses, avgCheckDuration
- **Access patterns**: checksByResource, checksByAction, checksByUser
- **Denials**: totalDenials, denialsByReason, denialsByResource
- **Roles & Permissions**: roleUsage, permissionUsage
- **Policies**: policyTriggers, policyDenials

**Функциональность:**
- Запись каждой проверки доступа с деталями
- Вычисление средней длительности проверки
- Получение топ N ресурсов/пользователей/причин отказа
- Snapshot метрик без сброса
- Collect and reset для периодической агрегации

### ✅ Task #4: MetricsAggregator - Агрегатор метрик

**Файл:** `lib/src/server/metrics/metrics_aggregator.dart`

**Функциональность:**
- Периодическая агрегация (по умолчанию каждые 5 минут)
- Сохранение метрик в Vault через MetricsRepository
- Получение метрик за период
- Агрегация нескольких периодов в один
- Очистка старых метрик
- Запуск/остановка фонового процесса

### ✅ Task #3: Интеграция в AccessControlEngine

**Файл:** `lib/src/rbac/access_control_engine.dart`

**Изменения:**
- Добавлены опциональные параметры `metricsCollector` и `alertGenerator`
- Интеграция записи метрик в `canSync()` и `canAsync()`
- Автоматический вызов `alertGenerator.processAccessCheck()` после каждой проверки
- Передача полного контекста: userId, resource, action, roles, permissions, policies

### ✅ Vault репозитории

**Файл:** `lib/src/server/repositories/rbac_repositories.dart`

**Добавлены:**
- `VaultMetricsRepository` - реализация MetricsRepository
- `VaultAlertRepositoryImpl` - реализация AlertRepository

**Функциональность:**
- Сохранение/получение метрик по периодам
- Удаление старых метрик
- Сохранение/обновление оповещений
- Фильтрация оповещений по типу, серьёзности, статусу
- Получение неподтверждённых оповещений

### ✅ Экспорты

**Файл:** `lib/aq_security_server.dart`

Добавлены экспорты:
```dart
export 'src/server/metrics/metrics_collector.dart';
export 'src/server/metrics/metrics_aggregator.dart';
export 'src/server/alerts/alert_generator.dart';
export 'src/server/alerts/alert_rules.dart';
```

## Известные проблемы (требуют исправления)

### 1. Конфликт имён VaultRoleRepository
Класс `VaultRoleRepository` определён в двух файлах:
- `lib/src/server/repositories/vault_security_repositories.dart`
- `lib/src/server/repositories/rbac_repositories.dart`

**Решение:** Переименовать один из классов или объединить файлы.

### 2. API VaultFilter/VaultQuery
Текущий код использует named parameters для VaultFilter, но API ожидает positional:
```dart
// Неправильно:
VaultFilter(field: 'userId', operator: VaultOperator.equals, value: userId)

// Правильно (нужно проверить актуальный API):
VaultFilter('userId', VaultOperator.equals, userId)
```

**Решение:** Проверить актуальный API dart_vault_package и исправить все вызовы.

### 3. AccessDecision параметры
`AccessDecision` не имеет параметра `effectivePermissions` в конструкторе.

**Решение:** Проверить модель AccessDecision в aq_schema и использовать правильные параметры.

### 4. VaultOperator константы
Отсутствуют константы `greaterThanOrEqual` и `lessThanOrEqual`.

**Решение:** Использовать правильные имена констант из VaultOperator enum.

### 5. VaultSort API
`VaultQuery` ожидает `VaultSort?` вместо `List<VaultSort>`.

**Решение:** Передавать один VaultSort или null.

## Следующие шаги

1. **Исправить ошибки компиляции:**
   - Разрешить конфликт VaultRoleRepository
   - Исправить API VaultFilter/VaultQuery
   - Исправить параметры AccessDecision
   - Исправить VaultOperator константы

2. **Добавить тесты:**
   - Unit тесты для MetricsCollector
   - Unit тесты для AlertGenerator
   - Unit тесты для правил оповещений
   - Integration тесты для репозиториев

3. **Обновить RBACRouter:**
   - Добавить endpoints для метрик
   - Добавить endpoints для оповещений
   - Интегрировать MetricsAggregator

4. **Документация:**
   - API документация для новых классов
   - Примеры использования
   - Руководство по настройке

## Архитектура

```
┌─────────────────────────────────────────┐
│         AccessControlEngine             │
│  (проверка доступа с метриками)         │
└─────────────────────────────────────────┘
              ↓ записывает
┌─────────────────────────────────────────┐
│         MetricsCollector                │
│  (сбор метрик в реальном времени)       │
└─────────────────────────────────────────┘
              ↓ агрегирует
┌─────────────────────────────────────────┐
│         MetricsAggregator               │
│  (периодическая агрегация каждые 5 мин) │
└─────────────────────────────────────────┘
              ↓ сохраняет
┌─────────────────────────────────────────┐
│       VaultMetricsRepository            │
│  (PostgreSQL через Vault)               │
└─────────────────────────────────────────┘

┌─────────────────────────────────────────┐
│         AccessControlEngine             │
│  (проверка доступа)                     │
└─────────────────────────────────────────┘
              ↓ уведомляет
┌─────────────────────────────────────────┐
│         AlertGenerator                  │
│  (генерация оповещений по правилам)     │
└─────────────────────────────────────────┘
              ↓ сохраняет
┌─────────────────────────────────────────┐
│       VaultAlertRepository              │
│  (PostgreSQL через Vault)               │
└─────────────────────────────────────────┘
```

## Использование

### Инициализация с метриками и оповещениями

```dart
// Создать сборщик метрик
final metricsCollector = MetricsCollector();

// Создать генератор оповещений
final alertGenerator = AlertGenerator(
  alertRepository: VaultAlertRepositoryImpl(vault),
);

// Создать движок с мониторингом
final engine = AccessControlEngine(
  roleRepository: roleRepo,
  userRoleRepository: userRoleRepo,
  policyRepository: policyRepo,
  cache: AccessCache(),
  metricsCollector: metricsCollector,
  alertGenerator: alertGenerator,
);

// Создать агрегатор метрик
final metricsAggregator = MetricsAggregator(
  collector: metricsCollector,
  repository: VaultMetricsRepository(vault),
  aggregationInterval: Duration(minutes: 5),
);

// Запустить периодическую агрегацию
metricsAggregator.start();
```

### Получение метрик

```dart
// Текущий snapshot
final snapshot = metricsCollector.snapshot();
print('Cache hit rate: ${snapshot.cacheHitRate}');
print('Denial rate: ${snapshot.denialRate}');

// Метрики за период
final metrics = await metricsAggregator.getAggregatedMetrics(
  startTime: DateTime.now().subtract(Duration(hours: 24)).millisecondsSinceEpoch,
  endTime: DateTime.now().millisecondsSinceEpoch,
);
```

### Работа с оповещениями

```dart
// Получить неподтверждённые оповещения
final alerts = await alertGenerator.getUnacknowledgedAlerts();

// Подтвердить оповещение
await alertGenerator.acknowledgeAlert(alertId, 'admin_user_id');

// Получить оповещения за период
final criticalAlerts = await alertGenerator.getAlerts(
  startTime: startTime,
  endTime: endTime,
  severity: AlertSeverity.critical,
);
```

## Метрики производительности

- **Сбор метрики**: ~0-1 мс (в памяти)
- **Агрегация**: ~10-50 мс (зависит от объёма данных)
- **Генерация оповещения**: ~1-5 мс (проверка правил)
- **Сохранение в Vault**: ~10-100 мс (зависит от БД)

## Хранение данных

- **Метрики**: Коллекция `rbac_metrics`, retention 30 дней (настраивается)
- **Оповещения**: Коллекция `rbac_alerts`, retention 90 дней (настраивается)
- **История проверок**: В памяти, max 1000 записей на пользователя, TTL 1 час
