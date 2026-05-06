# Runbook: High Error Rate

## Alert Details

**Alert Name**: `HighErrorRate`
**Severity**: Critical
**Threshold**: Error rate > 5% for 5 minutes
**Component**: Application

## Symptoms

- Prometheus alert firing: "High error rate detected"
- Error rate exceeds 5% of total requests
- Users experiencing 5xx errors

## Impact

- **User Impact**: High - users cannot complete requests
- **Business Impact**: High - service degradation, potential data loss
- **SLA Impact**: Yes - affects availability SLA

## Diagnosis

### 1. Проверить текущий error rate

```bash
# Prometheus query
rate(http_requests_total{job="aq-security",status=~"5.."}[5m]) / rate(http_requests_total{job="aq-security"}[5m]) * 100

# Или через curl
curl -s 'http://prometheus:9090/api/v1/query?query=rate(http_requests_total{job="aq-security",status=~"5.."}[5m])/rate(http_requests_total{job="aq-security"}[5m])*100'
```

### 2. Проверить логи приложения

```bash
# Последние 100 ошибок
kubectl logs -n production -l app=aq-security --tail=100 | grep '"level":"error"'

# Группировка ошибок по типу
kubectl logs -n production -l app=aq-security --tail=1000 | grep '"level":"error"' | jq -r '.error' | sort | uniq -c | sort -rn
```

### 3. Проверить статус зависимостей

```bash
# Database connectivity
kubectl exec -n production deployment/aq-security -- curl -s http://localhost:8080/health | jq '.checks.database'

# Redis connectivity
kubectl exec -n production deployment/aq-security -- curl -s http://localhost:8080/health | jq '.checks.redis'
```

### 4. Проверить метрики ресурсов

```bash
# CPU usage
kubectl top pods -n production -l app=aq-security

# Memory usage
kubectl get pods -n production -l app=aq-security -o json | jq '.items[].status.containerStatuses[].state'
```

## Common Causes

### 1. Database Connection Issues

**Symptoms**: Errors содержат "database connection failed" или "timeout"

**Resolution**:
```bash
# Проверить database pods
kubectl get pods -n production -l app=postgres

# Проверить database logs
kubectl logs -n production -l app=postgres --tail=100

# Проверить connection pool
kubectl exec -n production deployment/aq-security -- curl -s http://localhost:8080/metrics | grep db_connections
```

**Fix**: Если database недоступна, см. [database-connection-failed.md](./database-connection-failed.md)

### 2. Redis Connection Issues

**Symptoms**: Errors содержат "redis connection failed" или "cache error"

**Resolution**:
```bash
# Проверить redis pods
kubectl get pods -n production -l app=redis

# Проверить redis connectivity
kubectl exec -n production deployment/aq-security -- redis-cli -h redis ping
```

**Fix**: Если redis недоступен, см. [redis-connection-failed.md](./redis-connection-failed.md)

### 3. Memory Exhaustion

**Symptoms**: OOMKilled events, high memory usage

**Resolution**:
```bash
# Проверить OOM events
kubectl get events -n production --field-selector reason=OOMKilled

# Проверить memory limits
kubectl describe pod -n production -l app=aq-security | grep -A 5 "Limits:"
```

**Fix**:
```bash
# Временно увеличить memory limit
kubectl set resources deployment/aq-security -n production --limits=memory=768Mi

# Перезапустить pods
kubectl rollout restart deployment/aq-security -n production
```

### 4. Code Bug / Panic

**Symptoms**: Stack traces в логах, panic recovery messages

**Resolution**:
```bash
# Найти panic traces
kubectl logs -n production -l app=aq-security --tail=1000 | grep -A 20 "panic:"

# Проверить последний deploy
kubectl rollout history deployment/aq-security -n production
```

**Fix**:
```bash
# Rollback к предыдущей версии
kubectl rollout undo deployment/aq-security -n production

# Проверить статус rollback
kubectl rollout status deployment/aq-security -n production
```

### 5. Downstream Service Failure

**Symptoms**: Errors при вызове внешних API

**Resolution**:
```bash
# Проверить external service calls в логах
kubectl logs -n production -l app=aq-security --tail=500 | grep '"external_service"'

# Проверить network policies
kubectl get networkpolicies -n production
```

## Resolution Steps

### Step 1: Immediate Mitigation

```bash
# 1. Проверить health check
curl -s http://aq-security.production.svc.cluster.local:8080/health

# 2. Если pods unhealthy, перезапустить
kubectl rollout restart deployment/aq-security -n production

# 3. Масштабировать для распределения нагрузки
kubectl scale deployment/aq-security -n production --replicas=5
```

### Step 2: Root Cause Analysis

```bash
# 1. Собрать логи за период алерта
kubectl logs -n production -l app=aq-security --since=10m > /tmp/error-logs.txt

# 2. Проанализировать error patterns
cat /tmp/error-logs.txt | grep '"level":"error"' | jq -r '.error' | sort | uniq -c | sort -rn | head -20

# 3. Проверить correlation с другими событиями
kubectl get events -n production --sort-by='.lastTimestamp' | tail -50
```

### Step 3: Apply Fix

В зависимости от root cause:
- Database issues → см. database runbooks
- Redis issues → см. redis runbooks
- Code bug → rollback deployment
- Resource exhaustion → увеличить limits
- External service → implement circuit breaker / fallback

### Step 4: Verify Resolution

```bash
# 1. Проверить error rate снизился
curl -s 'http://prometheus:9090/api/v1/query?query=rate(http_requests_total{job="aq-security",status=~"5.."}[5m])/rate(http_requests_total{job="aq-security"}[5m])*100'

# 2. Проверить все pods healthy
kubectl get pods -n production -l app=aq-security

# 3. Проверить health endpoint
for pod in $(kubectl get pods -n production -l app=aq-security -o name); do
  echo "Checking $pod"
  kubectl exec -n production $pod -- curl -s http://localhost:8080/health | jq '.status'
done
```

## Escalation

### When to Escalate

- Error rate > 20% for more than 10 minutes
- Unable to identify root cause within 15 minutes
- Rollback не помог
- Multiple services affected

### Escalation Path

1. **Level 1**: On-call engineer (you)
2. **Level 2**: Senior backend engineer
3. **Level 3**: Engineering manager + DevOps lead
4. **Level 4**: CTO

### Escalation Contacts

- Slack: `#aq-security-incidents`
- PagerDuty: Escalate to "Backend Engineering"
- Phone: See on-call rotation schedule

## Post-Incident

### 1. Document Timeline

```markdown
- HH:MM - Alert fired
- HH:MM - Investigation started
- HH:MM - Root cause identified
- HH:MM - Fix applied
- HH:MM - Service recovered
- HH:MM - Alert resolved
```

### 2. Create Post-Mortem

Template: `docs/post-mortems/YYYY-MM-DD-high-error-rate.md`

Include:
- Timeline
- Root cause
- Impact (users affected, duration)
- Resolution steps
- Action items to prevent recurrence

### 3. Update Monitoring

- Adjust alert thresholds if needed
- Add new metrics if gaps identified
- Update runbook with lessons learned

## Prevention

### Short-term

- [ ] Review recent code changes
- [ ] Check resource utilization trends
- [ ] Verify all dependencies healthy
- [ ] Test error handling paths

### Long-term

- [ ] Implement circuit breakers for external calls
- [ ] Add retry logic with exponential backoff
- [ ] Improve error handling and recovery
- [ ] Add chaos engineering tests
- [ ] Implement graceful degradation

## Related Runbooks

- [Database Connection Failed](./database-connection-failed.md)
- [Redis Connection Failed](./redis-connection-failed.md)
- [High Memory Usage](./high-memory-usage.md)
- [Service Down](./service-down.md)

## References

- [Grafana Dashboard](https://grafana.example.com/d/aq-security)
- [Prometheus Alerts](https://prometheus.example.com/alerts)
- [Architecture Docs](../architecture/)
- [Deployment Guide](../deployment/kubernetes.md)
