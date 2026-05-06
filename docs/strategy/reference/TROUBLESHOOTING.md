# Troubleshooting Guide

Краткое руководство по диагностике и решению типичных проблем.

## Quick Diagnostics

### Service Health Check

```bash
# Check service status
curl https://api.your-domain.com/auth/health

# Expected response
{
  "status": "healthy",
  "timestamp": "2026-04-11T05:00:00Z",
  "checks": {
    "database": "healthy",
    "redis": "healthy"
  }
}
```

### Pod Status

```bash
# Check all pods
kubectl get pods -n production -l app=aq-security

# Expected: All pods Running with READY 1/1
NAME                           READY   STATUS    RESTARTS   AGE
aq-security-7d8f9c5b6d-abc12   1/1     Running   0          2h
aq-security-7d8f9c5b6d-def34   1/1     Running   0          2h
aq-security-7d8f9c5b6d-ghi56   1/1     Running   0          2h
```

### Recent Logs

```bash
# Check for errors
kubectl logs -n production -l app=aq-security --tail=100 | grep -i error

# Check for warnings
kubectl logs -n production -l app=aq-security --tail=100 | grep -i warn
```

## Common Issues

### 1. Service Returning 500 Errors

**Symptoms**: HTTP 500 responses, high error rate

**Quick Check**:
```bash
# Check error rate
curl -s 'http://prometheus:9090/api/v1/query?query=rate(http_requests_total{job="aq-security",status=~"5.."}[5m])'

# Check logs
kubectl logs -n production -l app=aq-security --tail=50 | grep '"level":"error"'
```

**Common Causes**:
- Database connection issues → See [database-connection-failed.md](./runbooks/database-connection-failed.md)
- Redis connection issues → Check Redis pod status
- Application panic → Check logs for stack traces

**Quick Fix**:
```bash
# Restart pods
kubectl rollout restart deployment/aq-security -n production
```

### 2. High Latency

**Symptoms**: Slow response times, timeouts

**Quick Check**:
```bash
# Check p95 latency
curl -s 'http://prometheus:9090/api/v1/query?query=histogram_quantile(0.95,rate(http_request_duration_seconds_bucket{job="aq-security"}[5m]))'

# Check resource usage
kubectl top pods -n production -l app=aq-security
```

**Common Causes**:
- High CPU/memory usage → Scale up replicas
- Slow database queries → Check database performance
- Too many connections → Check connection limits

**Quick Fix**:
```bash
# Scale up
kubectl scale deployment/aq-security -n production --replicas=5
```

### 3. Rate Limiting Blocking Legitimate Users

**Symptoms**: Users getting 429 errors, complaints about access

**Quick Check**:
```bash
# Check block rate
curl -s 'http://prometheus:9090/api/v1/query?query=rate(rate_limit_blocked_total{job="aq-security"}[5m])'

# Check blocked IPs
kubectl logs -n production -l app=aq-security --tail=500 | grep '"rate_limit_blocked"' | jq -r '.ip' | sort | uniq -c | sort -rn
```

**Quick Fix**:
```bash
# Temporarily increase limits
kubectl set env deployment/aq-security -n production \
  RATE_LIMIT_PER_IP_RPS=200 \
  RATE_LIMIT_GLOBAL_RPS=2000
```

### 4. Database Connection Pool Exhausted

**Symptoms**: "too many connections" errors

**Quick Check**:
```bash
# Check current connections
kubectl exec -n production -l app=postgres -- \
  psql -U postgres -c "SELECT count(*) FROM pg_stat_activity"

# Check max connections
kubectl exec -n production -l app=postgres -- \
  psql -U postgres -c "SHOW max_connections"
```

**Quick Fix**:
```bash
# Kill idle connections
kubectl exec -n production -l app=postgres -- \
  psql -U postgres -c "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE state = 'idle' AND now() - state_change > interval '5 minutes'"
```

### 5. Pods Crashing (CrashLoopBackOff)

**Symptoms**: Pods constantly restarting

**Quick Check**:
```bash
# Check pod status
kubectl get pods -n production -l app=aq-security

# Check logs from crashed pod
kubectl logs -n production <pod-name> --previous
```

**Common Causes**:
- Configuration error → Check environment variables
- Missing secrets → Check secrets exist
- Resource limits too low → Increase limits
- Failed health checks → Check health endpoint

**Quick Fix**:
```bash
# If recent deploy caused it - rollback
kubectl rollout undo deployment/aq-security -n production
```

### 6. Memory Leak

**Symptoms**: Memory usage constantly increasing, OOMKilled events

**Quick Check**:
```bash
# Check memory usage trend
kubectl top pods -n production -l app=aq-security

# Check OOM events
kubectl get events -n production --field-selector reason=OOMKilled
```

**Quick Fix**:
```bash
# Temporarily increase memory limit
kubectl set resources deployment/aq-security -n production \
  --limits=memory=1Gi

# Restart pods to clear memory
kubectl rollout restart deployment/aq-security -n production
```

## Diagnostic Commands

### Kubernetes

```bash
# Pod status
kubectl get pods -n production -l app=aq-security

# Pod details
kubectl describe pod -n production <pod-name>

# Logs
kubectl logs -n production <pod-name> --tail=100

# Previous logs (if crashed)
kubectl logs -n production <pod-name> --previous

# Events
kubectl get events -n production --sort-by='.lastTimestamp' | tail -20

# Resource usage
kubectl top pods -n production -l app=aq-security

# Exec into pod
kubectl exec -it -n production <pod-name> -- /bin/sh
```

### Database

```bash
# Connection count
kubectl exec -n production -l app=postgres -- \
  psql -U postgres -c "SELECT count(*) FROM pg_stat_activity"

# Active queries
kubectl exec -n production -l app=postgres -- \
  psql -U postgres -c "SELECT pid, now() - query_start as duration, query FROM pg_stat_activity WHERE state = 'active' ORDER BY duration DESC"

# Database size
kubectl exec -n production -l app=postgres -- \
  psql -U postgres -c "SELECT pg_database.datname, pg_size_pretty(pg_database_size(pg_database.datname)) FROM pg_database"

# Locks
kubectl exec -n production -l app=postgres -- \
  psql -U postgres -c "SELECT * FROM pg_locks WHERE NOT granted"
```

### Redis

```bash
# Check connectivity
kubectl exec -n production deployment/aq-security -- redis-cli -h redis ping

# Check memory usage
kubectl exec -n production -l app=redis -- redis-cli INFO memory

# Check connected clients
kubectl exec -n production -l app=redis -- redis-cli INFO clients
```

### Metrics

```bash
# Error rate
curl -s 'http://prometheus:9090/api/v1/query?query=rate(http_requests_total{job="aq-security",status=~"5.."}[5m])/rate(http_requests_total{job="aq-security"}[5m])*100'

# Response time p95
curl -s 'http://prometheus:9090/api/v1/query?query=histogram_quantile(0.95,rate(http_request_duration_seconds_bucket{job="aq-security"}[5m]))'

# Request rate
curl -s 'http://prometheus:9090/api/v1/query?query=rate(http_requests_total{job="aq-security"}[5m])'

# Active connections
curl -s 'http://prometheus:9090/api/v1/query?query=dos_connections_active{job="aq-security"}'
```

## Performance Issues

### Slow Queries

```bash
# Enable slow query logging
kubectl exec -n production -l app=postgres -- \
  psql -U postgres -c "ALTER SYSTEM SET log_min_duration_statement = 1000"

# Reload config
kubectl exec -n production -l app=postgres -- \
  psql -U postgres -c "SELECT pg_reload_conf()"

# Check slow queries in logs
kubectl logs -n production -l app=postgres | grep "duration:"
```

### High CPU Usage

```bash
# Check CPU usage
kubectl top pods -n production -l app=aq-security

# Check goroutines (if applicable)
curl -s http://localhost:8080/metrics | grep go_goroutines

# Scale up if needed
kubectl scale deployment/aq-security -n production --replicas=5
```

## Security Issues

### Suspicious Activity

```bash
# Check DoS blocks
kubectl logs -n production -l app=aq-security --tail=1000 | grep '"dos_blocked"' | jq -r '.ip' | sort | uniq -c | sort -rn

# Check rate limit blocks
kubectl logs -n production -l app=aq-security --tail=1000 | grep '"rate_limit_blocked"' | jq -r '.ip' | sort | uniq -c | sort -rn

# Check auth failures
kubectl logs -n production -l app=aq-security --tail=1000 | grep '"auth_failed"' | jq -r '.ip' | sort | uniq -c | sort -rn
```

### Block Suspicious IP

```bash
# Add to firewall (cloud provider specific)
# Example for GCP:
gcloud compute firewall-rules create block-attack \
  --action=DENY \
  --rules=tcp:443 \
  --source-ranges=<attacking-ip>
```

## Recovery Procedures

### Rollback Deployment

```bash
# Check rollout history
kubectl rollout history deployment/aq-security -n production

# Rollback to previous
kubectl rollout undo deployment/aq-security -n production

# Rollback to specific revision
kubectl rollout undo deployment/aq-security -n production --to-revision=5
```

### Restore Database

```bash
# List backups
kubectl exec -n production <backup-pod> -- ls -lh /backup/

# Restore from backup
kubectl create job --from=job/postgres-restore postgres-restore-emergency -n production
kubectl set env job/postgres-restore-emergency BACKUP_FILE=<backup-file> -n production
```

### Clear Redis Cache

```bash
# Flush all keys (use with caution!)
kubectl exec -n production -l app=redis -- redis-cli FLUSHALL

# Or flush specific database
kubectl exec -n production -l app=redis -- redis-cli -n 0 FLUSHDB
```

## When to Escalate

### Immediate Escalation (Level 2+)

- Service down > 5 minutes
- Data corruption suspected
- Security breach detected
- Multiple services affected
- Unable to identify root cause

### Escalation Contacts

- **Slack**: `#aq-security-incidents`
- **PagerDuty**: Escalate to "Backend Engineering"
- **DevOps Lead**: @devops-lead
- **Security Team**: @security-oncall

## Useful Links

- [Grafana Dashboards](https://grafana.example.com/d/aq-security)
- [Prometheus Alerts](https://prometheus.example.com/alerts)
- [Runbooks](./runbooks/)
- [Disaster Recovery Plan](./operations/disaster-recovery-plan.md)

---

**For detailed runbooks, see**: [docs/runbooks/](./runbooks/)
