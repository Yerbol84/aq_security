# Grafana Dashboards для AQ Security

**Дата:** 2026-04-10
**Статус:** ✅ Готовы к использованию

---

## 📊 Доступные дашборды

### 1. Security Overview Dashboard
**Файл:** `security_overview_dashboard.json`

Общий обзор безопасности системы.

**Панели:**
- ✅ Authentication Success Rate
- ✅ Failed Auth Attempts (Last 5m)
- ✅ Rate Limit Blocks (Last 5m)
- ✅ Blocked IPs (Last 5m)
- ✅ Authentication Attempts Over Time
- ✅ Rate Limiting Activity
- ✅ Active Connections
- ✅ Connection Attempts
- ✅ Token Operations
- ✅ Policy & Permission Checks
- ✅ Top Blocked IPs by Reason

**Использование:** Основной дашборд для мониторинга безопасности в реальном времени.

---

### 2. HTTP Performance Dashboard
**Файл:** `http_performance_dashboard.json`

Производительность HTTP запросов.

**Панели:**
- ✅ Request Rate
- ✅ Error Rate
- ✅ P95 Latency
- ✅ P99 Latency
- ✅ Request Rate by Method
- ✅ Request Rate by Status Code
- ✅ Latency Percentiles (P50, P90, P95, P99)
- ✅ Top 10 Slowest Endpoints
- ✅ Request Rate by Endpoint (Table)
- ✅ Error Rate by Endpoint (Table)

**Использование:** Мониторинг производительности API и выявление узких мест.

---

### 3. Alerts & Critical Events Dashboard
**Файл:** `alerts_dashboard.json`

Критические события и алерты.

**Панели:**
- 🚨 High Error Rate Alert
- 🚨 High Latency Alert
- 🚨 Connection Limit Alert
- 🚨 Auth Failure Spike
- ✅ Critical Events Timeline
- ✅ Failed Authentication Attempts
- ✅ Rate Limit Violations
- ✅ Blocked IPs by Reason
- ✅ Connection Rejections
- ✅ Recent Critical Events (Logs)

**Использование:** Быстрое реагирование на критические события и атаки.

---

## 🚀 Установка

### 1. Импорт дашбордов в Grafana

#### Через UI:
1. Открыть Grafana → Dashboards → Import
2. Загрузить JSON файл дашборда
3. Выбрать Prometheus data source
4. Нажать Import

#### Через API:
```bash
# Security Overview
curl -X POST http://admin:admin@localhost:3000/api/dashboards/db \
  -H "Content-Type: application/json" \
  -d @security_overview_dashboard.json

# HTTP Performance
curl -X POST http://admin:admin@localhost:3000/api/dashboards/db \
  -H "Content-Type: application/json" \
  -d @http_performance_dashboard.json

# Alerts
curl -X POST http://admin:admin@localhost:3000/api/dashboards/db \
  -H "Content-Type: application/json" \
  -d @alerts_dashboard.json
```

#### Через provisioning:
```yaml
# grafana/provisioning/dashboards/dashboards.yml
apiVersion: 1

providers:
  - name: 'AQ Security'
    orgId: 1
    folder: 'Security'
    type: file
    disableDeletion: false
    updateIntervalSeconds: 10
    allowUiUpdates: true
    options:
      path: /etc/grafana/dashboards
```

Скопировать JSON файлы в `/etc/grafana/dashboards/`.

---

### 2. Настройка Prometheus Alerts

#### Добавить в prometheus.yml:
```yaml
rule_files:
  - "prometheus_alerts.yml"

alerting:
  alertmanagers:
    - static_configs:
        - targets:
            - alertmanager:9093
```

#### Перезапустить Prometheus:
```bash
docker-compose restart prometheus
# или
systemctl restart prometheus
```

#### Проверить alerts:
```bash
# Проверить синтаксис
promtool check rules prometheus_alerts.yml

# Посмотреть активные alerts
curl http://localhost:9090/api/v1/alerts
```

---

### 3. Настройка Alertmanager

#### alertmanager.yml:
```yaml
global:
  resolve_timeout: 5m

route:
  group_by: ['alertname', 'severity']
  group_wait: 10s
  group_interval: 10s
  repeat_interval: 12h
  receiver: 'default'
  routes:
    - match:
        severity: critical
      receiver: 'critical'
      continue: true
    - match:
        severity: warning
      receiver: 'warning'

receivers:
  - name: 'default'
    webhook_configs:
      - url: 'http://localhost:5001/webhook'

  - name: 'critical'
    slack_configs:
      - api_url: 'YOUR_SLACK_WEBHOOK_URL'
        channel: '#security-alerts'
        title: '🚨 CRITICAL: {{ .GroupLabels.alertname }}'
        text: '{{ range .Alerts }}{{ .Annotations.description }}{{ end }}'
    email_configs:
      - to: 'security-team@example.com'
        from: 'alerts@example.com'
        smarthost: 'smtp.example.com:587'
        auth_username: 'alerts@example.com'
        auth_password: 'password'

  - name: 'warning'
    slack_configs:
      - api_url: 'YOUR_SLACK_WEBHOOK_URL'
        channel: '#security-warnings'
        title: '⚠️ WARNING: {{ .GroupLabels.alertname }}'
        text: '{{ range .Alerts }}{{ .Annotations.description }}{{ end }}'
```

---

## 📈 Alert Rules

### Критические алерты (severity: critical)

1. **VeryHighErrorRate** — Error rate > 10% за 1 минуту
2. **VeryHighLatency** — P95 latency > 5s за 2 минуты
3. **CriticalAuthFailureSpike** — > 200 failed auth за 5 минут
4. **CriticalRateLimitBlocks** — > 50 blocks/sec за 2 минуты
5. **ConnectionLimitCritical** — > 950 active connections
6. **CriticalIpBlocking** — > 50 IPs blocked за 5 минут
7. **ServiceDown** — Сервис не отвечает 1 минуту
8. **CriticalRequestRate** — > 5000 req/sec за 2 минуты

### Warning алерты (severity: warning)

1. **HighErrorRate** — Error rate > 5% за 2 минуты
2. **HighLatency** — P95 latency > 1s за 5 минут
3. **AuthFailureSpike** — > 50 failed auth за 5 минут
4. **HighRateLimitBlocks** — > 10 blocks/sec за 5 минут
5. **ConnectionLimitWarning** — > 800 active connections
6. **HighConnectionRejections** — > 5 rejections/sec
7. **IpBlockingSpike** — > 10 IPs blocked за 5 минут
8. **HighPermissionDenials** — > 10 denials/sec
9. **HighRequestRate** — > 1000 req/sec за 5 минут

---

## 🎯 Рекомендуемые действия при алертах

### 🚨 CriticalAuthFailureSpike
**Возможная причина:** Brute force атака

**Действия:**
1. Проверить IP адреса в дашборде "Top Blocked IPs"
2. Заблокировать подозрительные IP через IP blacklist
3. Временно ужесточить rate limiting
4. Проверить логи на паттерны атаки

### 🚨 CriticalRateLimitBlocks
**Возможная причина:** DoS атака или легитимный traffic spike

**Действия:**
1. Проверить источники трафика
2. Если атака — заблокировать IP ranges
3. Если легитимный трафик — увеличить rate limits
4. Масштабировать инфраструктуру при необходимости

### 🚨 ConnectionLimitCritical
**Возможная причина:** Connection flooding или высокая нагрузка

**Действия:**
1. Проверить количество connections per IP
2. Заблокировать IP с аномально высоким количеством connections
3. Увеличить connection limits если легитимная нагрузка
4. Добавить больше инстансов сервиса

### 🚨 VeryHighErrorRate
**Возможная причина:** Проблемы с сервисом или зависимостями

**Действия:**
1. Проверить логи ошибок
2. Проверить статус зависимых сервисов (БД, кэш)
3. Проверить метрики инфраструктуры (CPU, memory, disk)
4. Откатить последний deploy если проблема началась после него

---

## 🔧 Кастомизация

### Изменение thresholds

Отредактировать JSON дашборда:
```json
"thresholds": {
  "mode": "absolute",
  "steps": [
    {"value": 0, "color": "green"},
    {"value": 80, "color": "yellow"},  // ← изменить
    {"value": 95, "color": "red"}      // ← изменить
  ]
}
```

### Добавление новых панелей

1. Открыть дашборд в Grafana
2. Add Panel → Add new panel
3. Настроить query и visualization
4. Save dashboard
5. Export JSON → сохранить в репозиторий

### Изменение alert rules

Отредактировать `prometheus_alerts.yml`:
```yaml
- alert: MyCustomAlert
  expr: my_metric > 100  # ← изменить threshold
  for: 5m                # ← изменить duration
  labels:
    severity: warning    # ← изменить severity
```

---

## 📚 Полезные PromQL запросы

### Request rate за последние 5 минут
```promql
sum(rate(http_requests_total[5m]))
```

### Error rate в процентах
```promql
sum(rate(http_requests_total{status=~"5.."}[5m]))
/
sum(rate(http_requests_total[5m])) * 100
```

### P95 latency
```promql
histogram_quantile(0.95,
  sum(rate(http_request_duration_seconds_bucket[5m])) by (le)
)
```

### Top 10 endpoints по количеству запросов
```promql
topk(10, sum(rate(http_requests_total[5m])) by (path))
```

### Auth success rate
```promql
sum(rate(auth_attempts_total{success="true"}[5m]))
/
sum(rate(auth_attempts_total[5m])) * 100
```

---

## ✅ Checklist для production

- [ ] Импортированы все 3 дашборда
- [ ] Настроен Prometheus data source
- [ ] Загружены alert rules в Prometheus
- [ ] Настроен Alertmanager
- [ ] Настроены notification channels (Slack, Email)
- [ ] Протестированы алерты (можно вручную trigger через Alertmanager)
- [ ] Настроены retention policies для метрик
- [ ] Настроен backup дашбордов
- [ ] Документированы runbooks для каждого алерта
- [ ] Обучена команда работе с дашбордами

---

**Статус:** ✅ Grafana дашборды готовы к production использованию!
