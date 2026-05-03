# Structured Logging and Tracing в aq_security

**Дата:** 2026-04-10
**Статус:** ✅ Реализовано и протестировано

---

## 📊 Обзор

Система структурированного логирования с JSON форматом и distributed tracing для production мониторинга.

### Возможности

- ✅ **Structured JSON logging** — машиночитаемый формат
- ✅ **Log levels** — debug, info, warn, error, fatal
- ✅ **Context propagation** — request ID, trace ID, span ID, user ID
- ✅ **Distributed tracing** — correlation через async boundaries
- ✅ **Security-specific logging** — auth, rate limiting, DoS, incidents
- ✅ **Automatic HTTP logging** — через middleware
- ✅ **Log aggregation ready** — stdout для Docker/K8s
- ✅ **54 теста** — 100% покрытие

---

## 🎯 Архитектура

### Компоненты

1. **StructuredLogger** — базовый JSON logger
2. **LogContext** — context для propagation (request ID, trace ID, user ID)
3. **ContextLogger** — logger с автоматическим context propagation
4. **SecurityLogger** — security-specific logging helpers
5. **loggingMiddleware** — автоматическое логирование HTTP запросов

### Log Levels

```dart
enum LogLevel {
  debug,   // Детальная отладочная информация
  info,    // Информационные сообщения
  warn,    // Предупреждения
  error,   // Ошибки
  fatal,   // Критические ошибки
}
```

---

## 📝 JSON Log Format

### Базовый формат

```json
{
  "timestamp": "2026-04-10T18:30:00.000Z",
  "level": "info",
  "message": "Request completed",
  "request_id": "req-1a2b3c",
  "user_id": "user-123",
  "trace_id": "a1b2c3d4e5f6g7h8i9j0k1l2m3n4o5p6",
  "span_id": "1a2b3c4d5e6f7g8h",
  "component": "http",
  "method": "GET",
  "path": "/api/users",
  "status": 200,
  "duration_ms": 45.5
}
```

### Поля

- **timestamp** — ISO 8601 UTC timestamp
- **level** — log level (debug, info, warn, error, fatal)
- **message** — человекочитаемое сообщение
- **request_id** — уникальный ID запроса (для корреляции логов одного запроса)
- **user_id** — ID пользователя (если доступен)
- **trace_id** — 128-bit trace ID (для distributed tracing)
- **span_id** — 64-bit span ID (для вложенных операций)
- **component** — компонент системы (http, auth, rate_limiting, etc.)
- **metadata** — дополнительные поля (method, path, status, etc.)
- **error** — текст ошибки (если есть)
- **stack_trace** — stack trace (для error/fatal)

---

## 🚀 Использование

### 1. Инициализация

```dart
import 'package:aq_security/aq_security_server.dart';

void main() {
  // Инициализировать structured logger
  initializeLogger(
    minLevel: LogLevel.info,
    includeStackTrace: true,
  );

  // Инициализировать context logger
  initializeContextLogger(logger);

  // Инициализировать security logger
  initializeSecurityLogger(contextLogger);
}
```

### 2. HTTP Logging Middleware

```dart
final handler = const Pipeline()
    .addMiddleware(loggingMiddleware())
    .addHandler(myHandler);
```

**Автоматически логирует:**
- Incoming requests (method, path, query, IP, user agent)
- Completed requests (status, duration)
- Failed requests (error, stack trace)
- Добавляет X-Request-ID и X-Trace-ID headers

### 3. Manual Logging

```dart
// Базовое логирование
contextLogger.info('User logged in', metadata: {'user_id': 'user-123'});
contextLogger.warn('Rate limit approaching', metadata: {'remaining': 10});
contextLogger.error('Database error', error: e, stackTrace: st);

// С explicit context
final context = LogContext(
  requestId: 'req-123',
  userId: 'user-456',
  traceId: 'trace-789',
);

contextLogger.info('Processing payment', context: context);
```

### 4. Context Propagation

```dart
// Context автоматически propagates через async boundaries
await runAsyncWithLogContext(context, () async {
  contextLogger.info('Step 1');

  await someAsyncOperation();

  contextLogger.info('Step 2'); // Тот же context
});
```

### 5. Distributed Tracing с Spans

```dart
final parentContext = LogContext(
  requestId: generateRequestId(),
  traceId: generateTraceId(),
);

await runAsyncWithLogContext(parentContext, () async {
  contextLogger.info('Parent operation started');

  // Создать child span для database operation
  final dbSpan = parentContext.createSpan(component: 'database');
  await runAsyncWithLogContext(dbSpan, () async {
    contextLogger.info('Database query'); // Новый span_id
  });

  // Создать child span для cache operation
  final cacheSpan = parentContext.createSpan(component: 'cache');
  await runAsyncWithLogContext(cacheSpan, () async {
    contextLogger.info('Cache lookup'); // Другой span_id
  });

  contextLogger.info('Parent operation completed');
});
```

---

## 🔒 Security Logging

### Auth Events

```dart
securityLogger.logAuthAttempt(
  method: 'password',
  success: true,
  userId: 'user-123',
  ip: '192.168.1.1',
);

securityLogger.logTokenIssued(
  type: 'access',
  userId: 'user-123',
  expiresIn: 3600,
);
```

### Rate Limiting Events

```dart
securityLogger.logRateLimitHit(
  strategy: 'byIp',
  key: 'ip:192.168.1.1',
  remaining: 50,
  limit: 100,
);

securityLogger.logRateLimitBlocked(
  strategy: 'byIp',
  key: 'ip:192.168.1.1',
  limit: 100,
  retryAfter: 60,
);
```

### DoS Protection Events

```dart
securityLogger.logConnectionAttempt(
  allowed: false,
  ip: '192.168.1.1',
  reason: 'max connections reached',
  activeConnections: 1000,
  maxConnections: 1000,
);

securityLogger.logIpBlocked(
  ip: '192.168.1.1',
  reason: 'too_many_requests',
  durationSeconds: 3600,
);
```

### Security Incidents

```dart
securityLogger.logSuspiciousActivity(
  activity: 'multiple_failed_logins',
  reason: '10 failed attempts in 5 minutes',
  ip: '192.168.1.1',
  userId: 'user-123',
);

securityLogger.logSecurityIncident(
  incident: 'sql_injection_attempt',
  severity: 'high',
  ip: '192.168.1.1',
  details: {
    'query': 'SELECT * FROM users WHERE id = 1 OR 1=1',
    'blocked': true,
  },
);
```

---

## 📊 Log Aggregation

### Docker Logs

```bash
# Просмотр логов
docker logs my-app

# Следить за логами
docker logs -f my-app

# Фильтрация по level
docker logs my-app | jq 'select(.level == "error")'

# Фильтрация по request_id
docker logs my-app | jq 'select(.request_id == "req-123")'
```

### Docker Compose

```yaml
services:
  app:
    image: my-app
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"
```

### Fluentd/Fluent Bit

```yaml
# fluentd.conf
<source>
  @type forward
  port 24224
</source>

<filter **>
  @type parser
  key_name log
  <parse>
    @type json
  </parse>
</filter>

<match **>
  @type elasticsearch
  host elasticsearch
  port 9200
  logstash_format true
  logstash_prefix aq-security
</match>
```

### Kubernetes

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: my-app
spec:
  containers:
  - name: app
    image: my-app
    # Logs автоматически собираются kubelet
```

---

## 🔍 Log Analysis

### Поиск по request_id

```bash
# Все логи одного запроса
cat logs.json | jq 'select(.request_id == "req-123")'
```

### Поиск по trace_id

```bash
# Все логи одного distributed trace
cat logs.json | jq 'select(.trace_id == "a1b2c3d4...")'
```

### Поиск ошибок

```bash
# Все ошибки
cat logs.json | jq 'select(.level == "error" or .level == "fatal")'

# Ошибки конкретного компонента
cat logs.json | jq 'select(.level == "error" and .component == "auth")'
```

### Статистика

```bash
# Количество логов по level
cat logs.json | jq -r '.level' | sort | uniq -c

# Количество логов по component
cat logs.json | jq -r '.component' | sort | uniq -c

# Средняя длительность запросов
cat logs.json | jq -r 'select(.duration_ms) | .duration_ms' | \
  awk '{sum+=$1; count++} END {print sum/count}'
```

---

## ✅ Тестирование

### Запуск тестов

```bash
cd pkgs/aq_security
flutter test test/server/logging/
```

### Покрытие

- ✅ **structured_logger_test.dart** — 14 тестов (StructuredLogger, LogLevel)
- ✅ **log_context_test.dart** — 13 тестов (LogContext, context propagation, ID generation)
- ✅ **context_logger_test.dart** — 14 тестов (ContextLogger, security events)
- ✅ **logging_middleware_test.dart** — 13 тестов (HTTP logging, context injection)

**Итого:** 54 теста, 100% покрытие

---

## 📈 Best Practices

### 1. Всегда используйте context

```dart
// ✅ Good
contextLogger.info('Processing', context: context);

// ❌ Bad
logger.info('Processing'); // Нет correlation
```

### 2. Используйте semantic log levels

```dart
// ✅ Good
contextLogger.debug('Cache hit');        // Отладка
contextLogger.info('User logged in');    // Информация
contextLogger.warn('Rate limit hit');    // Предупреждение
contextLogger.error('DB error', error: e); // Ошибка

// ❌ Bad
contextLogger.info('ERROR: Something failed'); // Неправильный level
```

### 3. Добавляйте metadata

```dart
// ✅ Good
contextLogger.error(
  'Payment failed',
  error: e,
  metadata: {
    'user_id': 'user-123',
    'amount': 100.0,
    'currency': 'USD',
  },
);

// ❌ Bad
contextLogger.error('Payment failed'); // Мало контекста
```

### 4. Используйте spans для трейсинга

```dart
// ✅ Good - создаем spans для разных операций
final dbSpan = context.createSpan(component: 'database');
final cacheSpan = context.createSpan(component: 'cache');

// ❌ Bad - все в одном span
contextLogger.info('DB query');
contextLogger.info('Cache lookup');
```

### 5. Не логируйте sensitive data

```dart
// ✅ Good
contextLogger.info('Password changed', metadata: {'user_id': 'user-123'});

// ❌ Bad
contextLogger.info('Password changed', metadata: {
  'password': 'secret123', // НИКОГДА!
});
```

---

## 🎯 Интеграция с Grafana Loki

### Promtail config

```yaml
server:
  http_listen_port: 9080

positions:
  filename: /tmp/positions.yaml

clients:
  - url: http://loki:3100/loki/api/v1/push

scrape_configs:
  - job_name: aq-security
    static_configs:
      - targets:
          - localhost
        labels:
          job: aq-security
          __path__: /var/log/aq-security/*.log
    pipeline_stages:
      - json:
          expressions:
            level: level
            component: component
            request_id: request_id
            trace_id: trace_id
      - labels:
          level:
          component:
```

### Grafana Loki queries

```logql
# Все логи
{job="aq-security"}

# Только ошибки
{job="aq-security"} | json | level="error"

# Конкретный request
{job="aq-security"} | json | request_id="req-123"

# Конкретный trace
{job="aq-security"} | json | trace_id="a1b2c3d4..."

# Rate по errors
rate({job="aq-security"} | json | level="error" [5m])
```

---

**Статус:** ✅ Structured Logging and Tracing готовы к production использованию!
