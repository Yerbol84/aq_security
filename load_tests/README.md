# Load Testing для AQ Security

**Дата:** 2026-04-10
**Статус:** ✅ Готово к использованию

---

## 📊 Обзор

Набор k6 load test scenarios для тестирования системы безопасности под нагрузкой.

### Test Scenarios

1. **normal_load.js** — Normal sustained load (1000-2000 req/s)
2. **rate_limit_test.js** — Rate limiting effectiveness
3. **dos_simulation.js** — DoS attack simulation
4. **concurrent_users.js** — 10k+ concurrent connections
5. **auth_load.js** — Authentication system load

---

## 🚀 Установка

### 1. Установить k6

```bash
# macOS
brew install k6

# Linux
sudo gpg -k
sudo gpg --no-default-keyring --keyring /usr/share/keyrings/k6-archive-keyring.gpg --keyserver hkp://keyserver.ubuntu.com:80 --recv-keys C5AD17C747E3415A3642D57D77C6C491D6AC1D69
echo "deb [signed-by=/usr/share/keyrings/k6-archive-keyring.gpg] https://dl.k6.io/deb stable main" | sudo tee /etc/apt/sources.list.d/k6.list
sudo apt-get update
sudo apt-get install k6

# Windows
choco install k6

# Docker
docker pull grafana/k6
```

### 2. Проверить установку

```bash
k6 version
```

---

## 📝 Test Scenarios

### 1. Normal Load Test

**Цель:** Проверить систему под нормальной нагрузкой

**Нагрузка:**
- 2 min: ramp to 100 users (≈1000 req/s)
- 5 min: stay at 100 users
- 2 min: ramp to 200 users (≈2000 req/s)
- 5 min: stay at 200 users
- 2 min: ramp down

**Thresholds:**
- P95 latency < 500ms
- P99 latency < 1s
- Error rate < 1%

**Запуск:**
```bash
cd pkgs/aq_security/load_tests
k6 run normal_load.js

# С custom BASE_URL
k6 run -e BASE_URL=http://your-server:8080 normal_load.js
```

**Ожидаемый результат:**
- Success rate > 99%
- P95 latency < 500ms
- No connection errors

---

### 2. Rate Limit Test

**Цель:** Проверить эффективность rate limiting

**Scenarios:**
- Burst traffic: 200 req/s from single IP (30s)
- Sustained high: ramp 50→200 req/s (5m)

**Thresholds:**
- Should have rate limit blocks
- 429 responses should be fast (P95 < 100ms)

**Запуск:**
```bash
k6 run rate_limit_test.js
```

**Ожидаемый результат:**
- Rate limit blocks > 0
- Block rate 10-30% (зависит от конфигурации)
- 429 responses are fast
- Rate limit headers present

---

### 3. DoS Simulation

**Цель:** Проверить защиту от DoS атак

**Scenarios:**
- Connection flooding: 100 concurrent connections (2m)
- Slow loris: 50 slow connections (2m)
- Request flooding: 500 req/s from single IP (1m)

**Thresholds:**
- Should block connections
- Should block IPs

**Запуск:**
```bash
k6 run dos_simulation.js
```

**Ожидаемый результат:**
- Connection blocks > 0
- IP blocks > 0
- Protection effectiveness > 50%
- System remains responsive

---

### 4. Concurrent Users Test

**Цель:** Проверить систему с 10k+ одновременных подключений

**Нагрузка:**
- 2 min: ramp to 1k users
- 2 min: ramp to 5k users
- 2 min: ramp to 10k users
- 5 min: stay at 10k users
- 4 min: ramp down

**Thresholds:**
- P95 latency < 1s
- P99 latency < 2s
- Error rate < 5%
- Max 500 failed requests

**Запуск:**
```bash
k6 run concurrent_users.js
```

**Ожидаемый результат:**
- Success rate > 95%
- P95 latency < 1s
- System handles 10k concurrent users

---

### 5. Auth Load Test

**Цель:** Проверить authentication систему под нагрузкой

**Scenarios:**
- Normal auth: 50-100 users doing login/logout cycles (9m)
- Failed logins: 10 failed attempts/sec (2m)

**Thresholds:**
- Login P95 < 500ms
- Token validation P95 < 100ms
- Login successes > 100

**Запуск:**
```bash
k6 run auth_load.js
```

**Ожидаемый результат:**
- Login success rate > 90%
- Login duration P95 < 500ms
- Token validation is fast
- Failed logins are handled correctly

---

## 📊 Результаты

### Просмотр результатов

Каждый тест создает JSON summary файл:
- `summary.json` (normal_load)
- `rate_limit_summary.json`
- `dos_simulation_summary.json`
- `concurrent_users_summary.json`
- `auth_load_summary.json`

### Анализ результатов

```bash
# Просмотр summary
cat summary.json | jq

# Ключевые метрики
cat summary.json | jq '{
  duration: .state.testRunDurationMs,
  requests: .metrics.http_reqs.values.count,
  rps: .metrics.http_reqs.values.rate,
  error_rate: .metrics.http_req_failed.values.rate,
  p95: .metrics.http_req_duration.values["p(95)"],
  p99: .metrics.http_req_duration.values["p(99)"]
}'
```

### Grafana Integration

k6 может отправлять метрики в Prometheus/Grafana:

```bash
# Установить k6 extension
xk6 build --with github.com/grafana/xk6-output-prometheus-remote

# Запустить с Prometheus output
k6 run -o experimental-prometheus-rw normal_load.js
```

---

## 🎯 Performance Benchmarks

### Целевые показатели

**Normal Load (1000 req/s):**
- P95 latency: < 500ms
- P99 latency: < 1s
- Error rate: < 1%
- Success rate: > 99%

**Rate Limiting:**
- Block rate: 10-30%
- 429 response time: < 100ms
- Rate limit headers: present

**DoS Protection:**
- Connection blocks: > 0
- IP blocks: > 0
- Protection effectiveness: > 50%
- System responsive: yes

**Concurrent Users (10k):**
- P95 latency: < 1s
- P99 latency: < 2s
- Error rate: < 5%
- Success rate: > 95%

**Authentication:**
- Login P95: < 500ms
- Token validation P95: < 100ms
- Success rate: > 90%

---

## 🔧 Настройка тестов

### Environment Variables

```bash
# BASE_URL
export BASE_URL=http://localhost:8080
k6 run normal_load.js

# Или inline
k6 run -e BASE_URL=http://localhost:8080 normal_load.js
```

### Изменение нагрузки

Отредактировать `options.stages` в test файле:

```javascript
export const options = {
  stages: [
    { duration: '1m', target: 50 },   // Изменить target
    { duration: '5m', target: 50 },   // Изменить duration
  ],
};
```

### Изменение thresholds

```javascript
export const options = {
  thresholds: {
    'http_req_duration': ['p(95)<1000'],  // Изменить threshold
    'http_req_failed': ['rate<0.05'],     // Изменить error rate
  },
};
```

---

## 📈 Continuous Load Testing

### CI/CD Integration

```yaml
# .github/workflows/load-test.yml
name: Load Tests

on:
  schedule:
    - cron: '0 2 * * *'  # Daily at 2am
  workflow_dispatch:

jobs:
  load-test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3

      - name: Install k6
        run: |
          sudo gpg -k
          sudo gpg --no-default-keyring --keyring /usr/share/keyrings/k6-archive-keyring.gpg --keyserver hkp://keyserver.ubuntu.com:80 --recv-keys C5AD17C747E3415A3642D57D77C6C491D6AC1D69
          echo "deb [signed-by=/usr/share/keyrings/k6-archive-keyring.gpg] https://dl.k6.io/deb stable main" | sudo tee /etc/apt/sources.list.d/k6.list
          sudo apt-get update
          sudo apt-get install k6

      - name: Run load tests
        run: |
          cd pkgs/aq_security/load_tests
          k6 run normal_load.js
          k6 run rate_limit_test.js

      - name: Upload results
        uses: actions/upload-artifact@v3
        with:
          name: load-test-results
          path: pkgs/aq_security/load_tests/*.json
```

### Docker

```bash
# Run in Docker
docker run --rm -i grafana/k6 run - < normal_load.js

# With custom BASE_URL
docker run --rm -i -e BASE_URL=http://host.docker.internal:8080 grafana/k6 run - < normal_load.js
```

---

## 🐛 Troubleshooting

### Too many open files

```bash
# macOS
ulimit -n 10000

# Linux
sudo sysctl -w fs.file-max=100000
ulimit -n 100000
```

### Connection refused

```bash
# Check server is running
curl http://localhost:8080/api/health

# Check firewall
sudo ufw status
```

### High memory usage

```bash
# Reduce VUs or use arrival-rate executor
export const options = {
  scenarios: {
    test: {
      executor: 'constant-arrival-rate',
      rate: 100,
      timeUnit: '1s',
      duration: '5m',
      preAllocatedVUs: 50,
      maxVUs: 100,
    },
  },
};
```

---

## 📚 Дополнительные ресурсы

- [k6 Documentation](https://k6.io/docs/)
- [k6 Examples](https://k6.io/docs/examples/)
- [k6 Best Practices](https://k6.io/docs/testing-guides/test-types/)
- [Grafana k6 Cloud](https://k6.io/cloud/)

---

**Статус:** ✅ Load tests готовы к использованию!
