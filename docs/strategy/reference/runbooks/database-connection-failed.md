# Runbook: Database Connection Failed

## Alert Details

**Alert Name**: `DatabaseConnectionFailed`
**Severity**: Critical
**Threshold**: Database connection errors > 0 for 2 minutes
**Component**: Database

## Symptoms

- Prometheus alert firing: "Database connection failures"
- `rate(db_connection_errors_total{job="aq-security"}[5m]) > 0`
- Application logs содержат database connection errors
- Users видят 500 errors при операциях с данными

## Impact

- **User Impact**: High - операции с данными недоступны
- **Business Impact**: High - невозможность read/write данных
- **SLA Impact**: Yes - affects availability и data integrity

## Diagnosis

### 1. Проверить database pods

```bash
# Статус PostgreSQL pods
kubectl get pods -n production -l app=postgres

# Детальная информация
kubectl describe pods -n production -l app=postgres

# Логи database
kubectl logs -n production -l app=postgres --tail=100
```

### 2. Проверить connectivity из application

```bash
# Проверить connection из pod
kubectl exec -n production deployment/aq-security -- \
  psql -h postgres -U aq_security -d aq_security -c "SELECT 1"

# Проверить DNS resolution
kubectl exec -n production deployment/aq-security -- \
  nslookup postgres

# Проверить network connectivity
kubectl exec -n production deployment/aq-security -- \
  nc -zv postgres 5432
```

### 3. Проверить database metrics

```bash
# Connection count
kubectl exec -n production -l app=postgres -- \
  psql -U postgres -c "SELECT count(*) FROM pg_stat_activity"

# Max connections
kubectl exec -n production -l app=postgres -- \
  psql -U postgres -c "SHOW max_connections"

# Current connections by database
kubectl exec -n production -l app=postgres -- \
  psql -U postgres -c "SELECT datname, count(*) FROM pg_stat_activity GROUP BY datname"
```

### 4. Проверить application connection pool

```bash
# Prometheus metrics
curl -s 'http://prometheus:9090/api/v1/query?query=db_connections_active{job="aq-security"}'
curl -s 'http://prometheus:9090/api/v1/query?query=db_connections_idle{job="aq-security"}'
curl -s 'http://prometheus:9090/api/v1/query?query=db_connections_max{job="aq-security"}'
```

## Common Causes

### 1. Database Pod Down

**Symptoms**: PostgreSQL pod не running или restarting

**Diagnosis**:
```bash
kubectl get pods -n production -l app=postgres
kubectl describe pod -n production <postgres-pod-name>
kubectl logs -n production <postgres-pod-name> --previous
```

**Resolution**:
```bash
# Если pod в CrashLoop - проверить persistent volume
kubectl get pv,pvc -n production

# Проверить disk space
kubectl exec -n production <postgres-pod-name> -- df -h

# Если volume issues - может потребоваться restore from backup
# См. backup-restore runbook

# Перезапустить pod
kubectl delete pod -n production <postgres-pod-name>
```

### 2. Connection Pool Exhausted

**Symptoms**: "too many connections" в логах, все connections используются

**Diagnosis**:
```bash
# Проверить текущие connections
kubectl exec -n production -l app=postgres -- \
  psql -U postgres -c "SELECT count(*), state FROM pg_stat_activity GROUP BY state"

# Проверить long-running queries
kubectl exec -n production -l app=postgres -- \
  psql -U postgres -c "SELECT pid, now() - query_start as duration, query FROM pg_stat_activity WHERE state = 'active' ORDER BY duration DESC"

# Проверить idle connections
kubectl exec -n production -l app=postgres -- \
  psql -U postgres -c "SELECT count(*) FROM pg_stat_activity WHERE state = 'idle'"
```

**Resolution**:
```bash
# Временно увеличить max_connections в PostgreSQL
kubectl exec -n production -l app=postgres -- \
  psql -U postgres -c "ALTER SYSTEM SET max_connections = 200"

# Перезапустить PostgreSQL для применения
kubectl rollout restart statefulset/postgres -n production

# Или kill idle connections
kubectl exec -n production -l app=postgres -- \
  psql -U postgres -c "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE state = 'idle' AND now() - state_change > interval '5 minutes'"

# Уменьшить connection pool size в приложении
kubectl set env deployment/aq-security -n production \
  DB_MAX_CONNECTIONS=20 \
  DB_MAX_IDLE_CONNECTIONS=5
```

### 3. Network Issues

**Symptoms**: Connection timeout, DNS resolution failures

**Diagnosis**:
```bash
# Проверить service
kubectl get svc -n production postgres

# Проверить endpoints
kubectl get endpoints -n production postgres

# Проверить network policies
kubectl get networkpolicies -n production

# Test connectivity
kubectl exec -n production deployment/aq-security -- \
  telnet postgres 5432
```

**Resolution**:
```bash
# Если service endpoints пустые
kubectl describe svc -n production postgres

# Проверить selector matches pods
kubectl get pods -n production -l app=postgres --show-labels

# Если network policy блокирует
kubectl describe networkpolicy -n production

# Временно удалить restrictive policy
kubectl delete networkpolicy <policy-name> -n production
```

### 4. Authentication Failure

**Symptoms**: "password authentication failed" в логах

**Diagnosis**:
```bash
# Проверить credentials в secret
kubectl get secret -n production postgres-credentials -o yaml

# Проверить pg_hba.conf
kubectl exec -n production -l app=postgres -- cat /var/lib/postgresql/data/pg_hba.conf

# Проверить PostgreSQL logs для auth failures
kubectl logs -n production -l app=postgres | grep "authentication failed"
```

**Resolution**:
```bash
# Обновить password в PostgreSQL
kubectl exec -n production -l app=postgres -- \
  psql -U postgres -c "ALTER USER aq_security WITH PASSWORD 'new_password'"

# Обновить secret
kubectl create secret generic postgres-credentials \
  --from-literal=username=aq_security \
  --from-literal=password=new_password \
  -n production --dry-run=client -o yaml | kubectl apply -f -

# Перезапустить application pods
kubectl rollout restart deployment/aq-security -n production
```

### 5. Database Locked / Deadlock

**Symptoms**: Queries hanging, lock wait timeout errors

**Diagnosis**:
```bash
# Проверить locks
kubectl exec -n production -l app=postgres -- \
  psql -U postgres -c "SELECT * FROM pg_locks WHERE NOT granted"

# Проверить blocking queries
kubectl exec -n production -l app=postgres -- \
  psql -U postgres -c "
    SELECT blocked_locks.pid AS blocked_pid,
           blocking_locks.pid AS blocking_pid,
           blocked_activity.query AS blocked_query,
           blocking_activity.query AS blocking_query
    FROM pg_catalog.pg_locks blocked_locks
    JOIN pg_catalog.pg_stat_activity blocked_activity ON blocked_activity.pid = blocked_locks.pid
    JOIN pg_catalog.pg_locks blocking_locks ON blocking_locks.locktype = blocked_locks.locktype
    JOIN pg_catalog.pg_stat_activity blocking_activity ON blocking_activity.pid = blocking_locks.pid
    WHERE NOT blocked_locks.granted AND blocking_locks.granted
  "
```

**Resolution**:
```bash
# Kill blocking query
kubectl exec -n production -l app=postgres -- \
  psql -U postgres -c "SELECT pg_terminate_backend(<blocking_pid>)"

# Если deadlock - может потребоваться restart
kubectl rollout restart statefulset/postgres -n production
```

### 6. Disk Full

**Symptoms**: "No space left on device" в PostgreSQL logs

**Diagnosis**:
```bash
# Проверить disk usage
kubectl exec -n production -l app=postgres -- df -h

# Проверить database size
kubectl exec -n production -l app=postgres -- \
  psql -U postgres -c "SELECT pg_database.datname, pg_size_pretty(pg_database_size(pg_database.datname)) FROM pg_database"

# Проверить table sizes
kubectl exec -n production -l app=postgres -- \
  psql -U aq_security -d aq_security -c "
    SELECT schemaname, tablename, pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename))
    FROM pg_tables ORDER BY pg_total_relation_size(schemaname||'.'||tablename) DESC LIMIT 10
  "
```

**Resolution**:
```bash
# Увеличить PVC size (если поддерживается)
kubectl patch pvc postgres-data -n production -p '{"spec":{"resources":{"requests":{"storage":"100Gi"}}}}'

# Или cleanup старых данных
kubectl exec -n production -l app=postgres -- \
  psql -U aq_security -d aq_security -c "DELETE FROM audit_logs WHERE created_at < NOW() - INTERVAL '90 days'"

# Vacuum для освобождения места
kubectl exec -n production -l app=postgres -- \
  psql -U aq_security -d aq_security -c "VACUUM FULL"
```

## Resolution Steps

### Step 1: Quick Assessment (0-1 minute)

```bash
# 1. Database pod status
kubectl get pods -n production -l app=postgres

# 2. Recent errors
kubectl logs -n production -l app=postgres --tail=50 | grep -i error

# 3. Connection count
kubectl exec -n production -l app=postgres -- \
  psql -U postgres -c "SELECT count(*) FROM pg_stat_activity"
```

### Step 2: Immediate Mitigation (1-3 minutes)

```bash
# Если database pod down - restart
kubectl delete pod -n production <postgres-pod-name>

# Если connection pool exhausted - kill idle connections
kubectl exec -n production -l app=postgres -- \
  psql -U postgres -c "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE state = 'idle' AND now() - state_change > interval '5 minutes'"

# Если application overwhelmed - scale down temporarily
kubectl scale deployment/aq-security -n production --replicas=2
```

### Step 3: Root Cause Analysis (3-10 minutes)

```bash
# Собрать диагностику
kubectl logs -n production -l app=postgres --tail=500 > /tmp/postgres-logs.txt
kubectl logs -n production -l app=aq-security --tail=500 | grep -i database > /tmp/app-db-errors.txt

# Проверить metrics
curl -s 'http://prometheus:9090/api/v1/query?query=db_connection_errors_total{job="aq-security"}' > /tmp/db-errors-metrics.json

# Проверить database health
kubectl exec -n production -l app=postgres -- \
  psql -U postgres -c "SELECT * FROM pg_stat_database WHERE datname = 'aq_security'"
```

### Step 4: Apply Fix

В зависимости от root cause:
- Pod down → restart pod, check PV
- Connection exhausted → increase max_connections, kill idle
- Network → fix service/networkpolicy
- Auth → update credentials
- Locks → kill blocking queries
- Disk full → expand PVC or cleanup data

### Step 5: Verify Recovery

```bash
# 1. Database pod healthy
kubectl get pods -n production -l app=postgres
# Ожидаем: STATUS=Running, READY=1/1

# 2. Connection works
kubectl exec -n production deployment/aq-security -- \
  psql -h postgres -U aq_security -d aq_security -c "SELECT 1"
# Ожидаем: успешное подключение

# 3. No connection errors
curl -s 'http://prometheus:9090/api/v1/query?query=rate(db_connection_errors_total{job="aq-security"}[5m])'
# Ожидаем: value=0

# 4. Application health check
kubectl exec -n production deployment/aq-security -- curl -s http://localhost:8080/health | jq '.checks.database'
# Ожидаем: "healthy"
```

## Escalation

### When to Escalate

- Database down > 5 minutes
- Data corruption suspected
- Backup restore required
- Persistent volume issues

### Escalation Path

1. **Level 1**: On-call engineer (you)
2. **Level 2**: Database administrator
3. **Level 3**: DevOps lead + Senior DBA
4. **Level 4**: Infrastructure team + Cloud provider support

### Escalation Contacts

- Slack: `#aq-security-incidents` + `#database-team`
- PagerDuty: "Database On-Call"
- DBA: @database-admin in Slack

## Post-Incident

### Immediate Actions

```bash
# Backup current state
kubectl exec -n production -l app=postgres -- \
  pg_dump -U aq_security aq_security > /tmp/post-incident-backup.sql

# Collect diagnostics
kubectl logs -n production -l app=postgres --since=2h > incident-postgres-logs.txt
kubectl describe pod -n production -l app=postgres > incident-postgres-pod.txt
```

### Post-Mortem

Include:
- Connection error patterns
- Database metrics during incident
- Impact on data integrity
- Recovery steps taken
- Prevention measures

### Follow-up

- [ ] Review connection pool configuration
- [ ] Optimize slow queries
- [ ] Add connection monitoring alerts
- [ ] Test failover procedures
- [ ] Update backup strategy

## Prevention

### Short-term

- [ ] Monitor connection pool usage
- [ ] Set up alerts for connection exhaustion
- [ ] Implement connection retry logic
- [ ] Add circuit breaker for database calls

### Long-term

- [ ] Implement database replication
- [ ] Set up read replicas
- [ ] Implement connection pooling (PgBouncer)
- [ ] Regular database maintenance (vacuum, analyze)
- [ ] Capacity planning based on growth

## Related Runbooks

- [High Error Rate](./high-error-rate.md)
- [Service Down](./service-down.md)
- [Slow Database Queries](./slow-database-queries.md)
- [Backup and Restore](./backup-restore.md)

## Quick Reference

### Essential Commands

```bash
# Check database status
kubectl get pods -n production -l app=postgres

# Check connections
kubectl exec -n production -l app=postgres -- psql -U postgres -c "SELECT count(*) FROM pg_stat_activity"

# Kill idle connections
kubectl exec -n production -l app=postgres -- psql -U postgres -c "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE state = 'idle'"

# Test connection from app
kubectl exec -n production deployment/aq-security -- psql -h postgres -U aq_security -d aq_security -c "SELECT 1"
```

## References

- [PostgreSQL Documentation](https://www.postgresql.org/docs/)
- [Connection Pooling Best Practices](../architecture/database.md)
- [Backup Strategy](../operations/backup-strategy.md)
