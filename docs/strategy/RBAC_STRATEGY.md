# RBAC System Strategy - Стратегия системы ролей и прав

**Дата:** 2026-04-07
**Версия:** 2.0
**Статус:** Design Phase

## Философия

RBAC система AQ Studio - это **отдельный продукт**, модульное решение для управления доступом, которое можно подключить к любому ресурсу. Клиент получает **zero-configuration** решение с мощными инструментами мониторинга и управления.

### Ключевые принципы

1. **Модульность** - система работает как независимый сервис
2. **Тонкий клиент** - клиент только читает и отображает, вся логика на сервере
3. **Расширяемость** - легко добавлять новые типы прав и ролей
4. **Мониторинг** - полная видимость всех операций доступа
5. **Аудит** - каждое действие логируется и может быть проанализировано

## Архитектура системы

```
┌─────────────────────────────────────────────────────────────────┐
│                        RBAC System                               │
├─────────────────────────────────────────────────────────────────┤
│                                                                   │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐          │
│  │   Roles      │  │ Permissions  │  │   Policies   │          │
│  │              │  │              │  │              │          │
│  │ - Hierarchy  │  │ - Wildcards  │  │ - Conditions │          │
│  │ - Temporary  │  │ - Scopes     │  │ - Time-based │          │
│  │ - Inherited  │  │ - Resources  │  │ - Context    │          │
│  └──────────────┘  └──────────────┘  └──────────────┘          │
│                                                                   │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │              Access Control Engine                        │   │
│  │  - Evaluation  - Caching  - Real-time checks             │   │
│  └──────────────────────────────────────────────────────────┘   │
│                                                                   │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │                 Audit & Monitoring                        │   │
│  │  - Access logs  - Metrics  - Alerts  - Analytics         │   │
│  └──────────────────────────────────────────────────────────┘   │
│                                                                   │
└─────────────────────────────────────────────────────────────────┘
```

## Компоненты системы

### 1. Roles (Роли)

#### Базовая роль
```dart
class AqRole {
  String id;
  String name;
  String? description;
  List<String> permissions;      // Прямые права
  List<String> inheritsFrom;     // Наследование от других ролей
  RoleMetadata metadata;
}
```

#### Иерархия ролей
```
System Admin
  ├─> Tenant Admin
  │     ├─> Project Admin
  │     │     ├─> Project Editor
  │     │     └─> Project Viewer
  │     └─> User Manager
  └─> System Auditor
```

**Правила наследования:**
- Дочерняя роль получает все права родительской
- Можно переопределять права (revoke)
- Циклические зависимости запрещены
- Максимальная глубина: 5 уровней

#### Временные роли
```dart
class TemporaryRole {
  String roleId;
  String userId;
  DateTime expiresAt;
  String? reason;           // Причина выдачи
  String? grantedBy;        // Кто выдал
}
```

**Использование:**
- Временный доступ для подрядчиков
- Escalation для support
- Trial periods
- Emergency access

### 2. Permissions (Права)

#### Формат прав

```
<resource>:<action>:<scope>
```

**Примеры:**
```
projects:read:*              # Чтение всех проектов
projects:write:own           # Запись только своих проектов
projects:delete:tenant       # Удаление проектов в своём tenant
users:manage:team            # Управление пользователями в команде
billing:view:*               # Просмотр биллинга
```

#### Wildcards (Подстановочные знаки)

```
*:*:*                        # Полный доступ (super admin)
projects:*:*                 # Все действия с проектами
*:read:*                     # Чтение всех ресурсов
projects:*:own               # Все действия со своими проектами
```

#### Scopes (Области видимости)

- `*` - глобальный доступ
- `tenant` - в рамках tenant
- `team` - в рамках команды
- `own` - только свои ресурсы
- `shared` - shared ресурсы
- `public` - публичные ресурсы

#### Resource Types (Типы ресурсов)

```dart
enum ResourceType {
  projects,
  workflows,
  instructions,
  blueprints,
  users,
  teams,
  tenants,
  apiKeys,
  sessions,
  billing,
  settings,
  audit,
}
```

#### Action Types (Типы действий)

```dart
enum ActionType {
  create,
  read,
  update,
  delete,
  execute,
  manage,
  share,
  export,
  import,
}
```

### 3. Policies (Политики)

#### Условные политики
```dart
class AccessPolicy {
  String id;
  String name;
  List<PolicyCondition> conditions;
  PolicyEffect effect;          // Allow / Deny
  int priority;                 // Для разрешения конфликтов
}

class PolicyCondition {
  String type;                  // time, ip, mfa, resource_state
  Map<String, dynamic> params;
}
```

**Примеры политик:**

```dart
// Доступ только в рабочее время
Policy(
  name: 'Business hours only',
  conditions: [
    TimeCondition(
      days: [Mon, Tue, Wed, Thu, Fri],
      hours: [9, 18],
      timezone: 'UTC',
    ),
  ],
  effect: Allow,
)

// Требовать MFA для критических операций
Policy(
  name: 'MFA for delete',
  conditions: [
    ActionCondition(actions: ['delete']),
    MFACondition(required: true),
  ],
  effect: Allow,
)

// Блокировать доступ с определённых IP
Policy(
  name: 'Block suspicious IPs',
  conditions: [
    IPCondition(blacklist: ['1.2.3.4', '5.6.7.8']),
  ],
  effect: Deny,
)

// Доступ только к опубликованным ресурсам
Policy(
  name: 'Published only',
  conditions: [
    ResourceStateCondition(state: 'published'),
  ],
  effect: Allow,
)
```

### 4. Access Control Engine

#### Алгоритм проверки доступа

```
1. Получить пользователя и его роли
2. Собрать все права (прямые + унаследованные)
3. Проверить wildcards
4. Применить политики (по приоритету)
5. Проверить временные ограничения
6. Кэшировать результат
7. Залогировать проверку
```

#### Кэширование

```dart
class AccessCache {
  Duration ttl = Duration(minutes: 5);
  int maxSize = 10000;

  // Ключ: userId:resource:action:scope
  Map<String, CachedDecision> cache;
}

class CachedDecision {
  bool allowed;
  DateTime cachedAt;
  String? reason;
}
```

**Инвалидация кэша:**
- При изменении ролей пользователя
- При изменении прав роли
- При изменении политик
- По истечении TTL

#### Real-time проверки

```dart
// Синхронная проверка (из кэша)
bool canSync(String userId, String permission);

// Асинхронная проверка (с политиками)
Future<AccessDecision> canAsync(
  String userId,
  String resource,
  String action,
  Map<String, dynamic> context,
);

// Batch проверка
Future<Map<String, bool>> canBatch(
  String userId,
  List<String> permissions,
);
```

## Мониторинг и метрики

### 1. Access Logs (Логи доступа)

```dart
class AccessLog {
  String id;
  String userId;
  String resource;
  String action;
  String scope;
  bool allowed;
  String? denialReason;
  Map<String, dynamic> context;
  int timestamp;
  int durationMs;
}
```

**Что логируется:**
- Все проверки доступа (allowed + denied)
- Контекст запроса (IP, user agent, etc.)
- Время выполнения проверки
- Причина отказа (если denied)
- Использованные роли и политики

### 2. Metrics (Метрики)

#### Server-side метрики

```dart
class RBACMetrics {
  // Performance
  int totalChecks;
  int cacheHits;
  int cacheMisses;
  double avgCheckDuration;

  // Access patterns
  Map<String, int> checksByResource;
  Map<String, int> checksByAction;
  Map<String, int> checksByUser;

  // Denials
  int totalDenials;
  Map<String, int> denialsByReason;
  Map<String, int> denialsByResource;

  // Roles
  Map<String, int> roleUsage;
  Map<String, int> permissionUsage;

  // Policies
  Map<String, int> policyTriggers;
  Map<String, int> policyDenials;
}
```

#### Client-side метрики

Клиент получает агрегированные метрики через API:

```dart
class ClientMetrics {
  // Для текущего пользователя
  int myAccessChecks;
  int myDenials;
  List<String> myMostUsedPermissions;

  // Для tenant (если admin)
  int tenantAccessChecks;
  int tenantDenials;
  List<TopUser> topUsers;
  List<TopResource> topResources;

  // Аномалии
  List<AccessAnomaly> anomalies;
}
```

### 3. Alerts (Оповещения)

```dart
class AccessAlert {
  String type;              // suspicious, policy_violation, rate_limit
  String severity;          // low, medium, high, critical
  String userId;
  String resource;
  String description;
  int timestamp;
}
```

**Типы оповещений:**
- Подозрительная активность (много denied подряд)
- Нарушение политик
- Rate limiting
- Необычные паттерны доступа
- Escalation прав
- Истечение временных ролей

### 4. Analytics (Аналитика)

```dart
class AccessAnalytics {
  // Временные ряды
  TimeSeries<int> checksOverTime;
  TimeSeries<int> denialsOverTime;

  // Распределения
  Distribution<String> resourceDistribution;
  Distribution<String> actionDistribution;

  // Корреляции
  Map<String, List<String>> commonPermissionPairs;
  Map<String, List<String>> roleEffectiveness;

  // Рекомендации
  List<Recommendation> recommendations;
}

class Recommendation {
  String type;              // unused_role, over_privileged, under_privileged
  String target;            // userId or roleId
  String suggestion;
  double confidence;
}
```

## API сервера

### Role Management

```dart
// CRUD ролей
POST   /rbac/roles                    # Создать роль
GET    /rbac/roles                    # Список ролей
GET    /rbac/roles/:id                # Получить роль
PUT    /rbac/roles/:id                # Обновить роль
DELETE /rbac/roles/:id                # Удалить роль

// Иерархия
POST   /rbac/roles/:id/inherit/:parentId    # Добавить наследование
DELETE /rbac/roles/:id/inherit/:parentId    # Убрать наследование
GET    /rbac/roles/:id/hierarchy            # Получить иерархию

// Права роли
POST   /rbac/roles/:id/permissions          # Добавить права
DELETE /rbac/roles/:id/permissions          # Убрать права
GET    /rbac/roles/:id/effective-permissions # Все права (с наследованием)
```

### User Role Assignment

```dart
// Назначение ролей
POST   /rbac/users/:userId/roles            # Назначить роль
DELETE /rbac/users/:userId/roles/:roleId    # Убрать роль
GET    /rbac/users/:userId/roles            # Роли пользователя

// Временные роли
POST   /rbac/users/:userId/temporary-roles  # Выдать временную роль
GET    /rbac/users/:userId/temporary-roles  # Список временных ролей
DELETE /rbac/users/:userId/temporary-roles/:id # Отозвать временную роль
```

### Access Control

```dart
// Проверка доступа
POST   /rbac/check                          # Проверить доступ
POST   /rbac/check/batch                    # Batch проверка
GET    /rbac/permissions/:userId            # Все права пользователя

// Политики
POST   /rbac/policies                       # Создать политику
GET    /rbac/policies                       # Список политик
PUT    /rbac/policies/:id                   # Обновить политику
DELETE /rbac/policies/:id                   # Удалить политику
```

### Monitoring & Analytics

```dart
// Логи
GET    /rbac/logs                           # Access logs
GET    /rbac/logs/user/:userId              # Логи пользователя
GET    /rbac/logs/resource/:resource        # Логи ресурса

// Метрики
GET    /rbac/metrics                        # Общие метрики
GET    /rbac/metrics/user/:userId           # Метрики пользователя
GET    /rbac/metrics/tenant/:tenantId       # Метрики tenant

// Аналитика
GET    /rbac/analytics                      # Аналитика
GET    /rbac/analytics/recommendations      # Рекомендации
GET    /rbac/analytics/anomalies            # Аномалии

// Оповещения
GET    /rbac/alerts                         # Список оповещений
POST   /rbac/alerts/:id/acknowledge         # Подтвердить оповещение
```

## Клиентские инструменты

### 1. Zero-configuration

Клиент не настраивает RBAC, только использует:

```dart
// Инициализация
final rbac = await RBACClient.init('http://rbac-service:8080');

// Проверка доступа
if (await rbac.can('projects:write:own')) {
  // Разрешено
}

// Batch проверка
final permissions = await rbac.canBatch([
  'projects:read:*',
  'projects:write:own',
  'projects:delete:own',
]);

// Получить все права
final myPermissions = await rbac.getMyPermissions();
```

### 2. UI Components (через aq_security_ui)

```dart
// Guard с RBAC
PermissionGuard(
  permission: 'projects:write:tenant',
  child: CreateProjectButton(),
);

// Условный рендеринг
RBACBuilder(
  permission: 'billing:view:*',
  builder: (context, allowed) {
    return allowed ? BillingDashboard() : AccessDenied();
  },
);

// Метрики виджет
RBACMetricsWidget(
  userId: currentUser.id,
  showAlerts: true,
);
```

### 3. Monitoring Dashboard

```dart
// Дашборд для админов
RBACDashboard(
  children: [
    AccessLogsWidget(),
    MetricsWidget(),
    AlertsWidget(),
    AnalyticsWidget(),
    RecommendationsWidget(),
  ],
);
```

## Модели данных

### Database Schema

```sql
-- Роли
CREATE TABLE rbac_roles (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  description TEXT,
  permissions JSONB NOT NULL,
  inherits_from JSONB,
  metadata JSONB,
  created_at BIGINT NOT NULL,
  updated_at BIGINT NOT NULL
);

-- Назначение ролей пользователям
CREATE TABLE rbac_user_roles (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL,
  role_id TEXT NOT NULL,
  tenant_id TEXT NOT NULL,
  granted_by TEXT,
  granted_at BIGINT NOT NULL,
  expires_at BIGINT,
  reason TEXT,
  UNIQUE(user_id, role_id)
);

-- Политики
CREATE TABLE rbac_policies (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  conditions JSONB NOT NULL,
  effect TEXT NOT NULL,
  priority INTEGER NOT NULL,
  enabled BOOLEAN DEFAULT true,
  created_at BIGINT NOT NULL,
  updated_at BIGINT NOT NULL
);

-- Логи доступа
CREATE TABLE rbac_access_logs (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL,
  resource TEXT NOT NULL,
  action TEXT NOT NULL,
  scope TEXT NOT NULL,
  allowed BOOLEAN NOT NULL,
  denial_reason TEXT,
  context JSONB,
  duration_ms INTEGER,
  timestamp BIGINT NOT NULL
);

-- Индексы для быстрого поиска
CREATE INDEX idx_user_roles_user ON rbac_user_roles(user_id);
CREATE INDEX idx_user_roles_role ON rbac_user_roles(role_id);
CREATE INDEX idx_access_logs_user ON rbac_access_logs(user_id);
CREATE INDEX idx_access_logs_resource ON rbac_access_logs(resource);
CREATE INDEX idx_access_logs_timestamp ON rbac_access_logs(timestamp);
```

## Примеры использования

### Сценарий 1: Создание иерархии ролей

```dart
// 1. Создать базовую роль
final viewer = await rbac.createRole(
  name: 'Project Viewer',
  permissions: ['projects:read:*', 'workflows:read:*'],
);

// 2. Создать роль с наследованием
final editor = await rbac.createRole(
  name: 'Project Editor',
  permissions: ['projects:write:own', 'workflows:write:own'],
  inheritsFrom: [viewer.id],
);

// 3. Создать admin роль
final admin = await rbac.createRole(
  name: 'Project Admin',
  permissions: ['projects:*:tenant', 'workflows:*:tenant', 'users:manage:team'],
  inheritsFrom: [editor.id],
);
```

### Сценарий 2: Временный доступ

```dart
// Выдать временный admin доступ на 2 часа
await rbac.grantTemporaryRole(
  userId: contractor.id,
  roleId: adminRole.id,
  duration: Duration(hours: 2),
  reason: 'Emergency fix for production issue #1234',
);

// Система автоматически отзовёт роль через 2 часа
// И отправит оповещение
```

### Сценарий 3: Политика с условиями

```dart
// Разрешить delete только с MFA
await rbac.createPolicy(
  name: 'MFA for destructive actions',
  conditions: [
    ActionCondition(actions: ['delete', 'drop']),
    MFACondition(required: true),
  ],
  effect: PolicyEffect.allow,
  priority: 100,
);

// Теперь при попытке delete:
// 1. Проверяется наличие прав
// 2. Проверяется MFA
// 3. Если MFA нет - denied с причиной "MFA required"
```

### Сценарий 4: Мониторинг подозрительной активности

```dart
// Сервер автоматически детектит аномалии
// Клиент получает оповещения

final alerts = await rbac.getAlerts();
for (final alert in alerts) {
  if (alert.severity == 'critical') {
    // Показать уведомление
    showNotification(
      title: 'Security Alert',
      body: alert.description,
    );
  }
}
```

## Расширяемость

### Добавление новых типов ресурсов

```dart
// 1. Добавить в enum
enum ResourceType {
  // ... existing
  customResource,
}

// 2. Зарегистрировать в системе
rbac.registerResourceType(
  type: 'customResource',
  actions: ['create', 'read', 'update', 'delete', 'custom_action'],
  scopes: ['*', 'tenant', 'own'],
);

// 3. Использовать
await rbac.can('customResource:custom_action:tenant');
```

### Добавление новых типов политик

```dart
// 1. Создать condition
class CustomCondition extends PolicyCondition {
  @override
  Future<bool> evaluate(AccessContext context) async {
    // Кастомная логика
    return true;
  }
}

// 2. Зарегистрировать
rbac.registerConditionType('custom', CustomCondition.new);

// 3. Использовать в политиках
await rbac.createPolicy(
  conditions: [
    CustomCondition(params: {...}),
  ],
);
```

## Производительность

### Целевые метрики

- **Проверка доступа (cached):** < 1ms
- **Проверка доступа (uncached):** < 10ms
- **Проверка с политиками:** < 50ms
- **Batch проверка (100 прав):** < 100ms
- **Cache hit rate:** > 95%
- **Throughput:** > 10,000 checks/sec

### Оптимизации

1. **Кэширование** - агрессивное кэширование решений
2. **Batch операции** - проверка нескольких прав за раз
3. **Индексы** - оптимизированные индексы в БД
4. **Денормализация** - хранение эффективных прав
5. **Async** - асинхронные проверки где возможно

## Безопасность

### Защита от атак

1. **Rate limiting** - ограничение частоты проверок
2. **Audit logging** - полное логирование всех операций
3. **Anomaly detection** - детектирование подозрительной активности
4. **Principle of least privilege** - минимальные права по умолчанию
5. **Separation of duties** - разделение критических операций

### Compliance

- **GDPR** - логирование доступа к персональным данным
- **SOC 2** - аудит всех изменений прав
- **ISO 27001** - контроль доступа к критическим ресурсам

## Roadmap

### Phase 1: Foundation (Current)
- ✅ Базовые роли и права
- ✅ Простая проверка доступа
- ⏳ Иерархия ролей
- ⏳ Wildcards

### Phase 2: Advanced (Next)
- ⏳ Политики с условиями
- ⏳ Временные роли
- ⏳ Кэширование
- ⏳ Базовый мониторинг

### Phase 3: Enterprise (Future)
- ⏳ Продвинутая аналитика
- ⏳ Anomaly detection
- ⏳ Рекомендации
- ⏳ Compliance отчёты

### Phase 4: AI-powered (Vision)
- ⏳ ML для детектирования аномалий
- ⏳ Автоматическое назначение ролей
- ⏳ Предиктивная аналитика
- ⏳ Smart recommendations

## Заключение

RBAC система AQ Studio - это **комплексное модульное решение** для управления доступом. Она предоставляет:

- **Для разработчиков:** Zero-configuration API, готовые UI компоненты
- **Для администраторов:** Мощные инструменты управления и мониторинга
- **Для аудиторов:** Полное логирование и аналитика
- **Для бизнеса:** Compliance, безопасность, масштабируемость

Система спроектирована как **отдельный продукт**, который можно подключить к любому ресурсу и получить enterprise-grade контроль доступа из коробки.
