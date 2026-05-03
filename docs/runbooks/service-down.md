# Runbook: Service Down

## Alert Details

**Alert Name**: `ServiceDown`
**Severity**: Critical
**Threshold**: Service unavailable for 1 minute
**Component**: Application

## Symptoms

- Prometheus alert firing: "AQ Security service is down"
- `up{job="aq-security"} == 0`
- Service не отвечает на health checks
- Users не могут получить доступ к сервису

## Impact

- **User Impact**: Critical - полная недоступность сервиса
- **Business Impact**: Critical - все операции остановлены
- **SLA Impact**: Yes - нарушение availability SLA

## Diagnosis

### 1. Проверить статус pods

```bash
# Проверить все pods
kubectl get pods -n production -l app=aq-security

# Детальная информация
kubectl describe pods -n production -l app=aq-security

# Проверить events
kubectl get events -n production --field-selector involvedObject.name=aq-security --sort-by='.lastTimestamp'
```

### 2. Проверить логи

```bash
# Логи всех pods
kubectl logs -n production -l app=aq-security --tail=100

# Логи конкретного pod
kubectl logs -n production <pod-name> --previous  # Если pod перезапустился
```

### 3. Проверить deployment status

```bash
# Deployment status
kubectl get deployment -n production aq-security

# Rollout status
kubectl rollout status deployment/aq-security -n production

# Rollout history
kubectl rollout history deployment/aq-security -n production
```

### 4. Проверить ресурсы

```bash
# Node resources
kubectl top nodes

# Pod resources
kubectl top pods -n production -l app=aq-security

# Resource limits
kubectl describe deployment -n production aq-security | grep -A 10 "Limits:"
```

## Common Causes

### 1. Pod CrashLoopBackOff

**Symptoms**: Pods постоянно перезапускаются

**Diagnosis**:
```bash
# Проверить restart count
kubectl get pods -n production -l app=aq-security

# Проверить причину crash
kubectl logs -n production <pod-name> --previous

# Проверить liveness probe failures
kubectl describe pod -n production <pod-name> | grep -A 10 "Liveness:"
```

**Resolution**:
```bash
# Если проблема в последнем deploy - rollback
kubectl rollout undo deployment/aq-security -n production

# Если проблема в конфигурации - исправить и применить
kubectl edit deployment -n production aq-security

# Если проблема в зависимостях - проверить database/redis
kubectl get pods -n production -l app=postgres
kubectl get pods -n production -l app=redis
```

### 2. ImagePullBackOff

**Symptoms**: Pods не могут загрузить image

**Diagnosis**:
```bash
# Проверить image pull status
kubectl describe pod -n production <pod-name> | grep -A 5 "Events:"

# Проверить image registry credentials
kubectl get secrets -n production | grep regcred
```

**Resolution**:
```bash
# Проверить image существует
docker pull <image-name>:<tag>

# Пересоздать registry secret если нужно
kubectl create secret docker-registry regcred \
  --docker-server=<registry> \
  --docker-username=<username> \
  --docker-password=<password> \
  -n production --dry-run=client -o yaml | kubectl apply -f -

# Перезапустить deployment
kubectl rollout restart deployment/aq-security -n production
```

### 3. Insufficient Resources

**Symptoms**: Pods в состоянии Pending, events показывают "Insufficient cpu/memory"

**Diagnosis**:
```bash
# Проверить pending pods
kubectl get pods -n production -l app=aq-security | grep Pending

# Проверить причину
kubectl describe pod -n production <pod-name> | grep -A 10 "Events:"

# Проверить доступные ресурсы на nodes
kubectl describe nodes | grep -A 5 "Allocated resources:"
```

**Resolution**:
```bash
# Временно уменьшить resource requests
kubectl set resources deployment/aq-security -n production \
  --requests=cpu=100m,memory=128Mi

# Или добавить новые nodes (если auto-scaling не сработал)
# Зависит от cloud provider

# Или уменьшить количество реплик других сервисов
kubectl scale deployment/<other-service> -n production --replicas=1
```

### 4. Node Failure

**Symptoms**: Все pods на одном node недоступны

**Diagnosis**:
```bash
# Проверить node status
kubectl get nodes

# Детали проблемного node
kubectl describe node <node-name>

# Pods на проблемном node
kubectl get pods -n production -o wide | grep <node-name>
```

**Resolution**:
```bash
# Drain node (переместить pods на другие nodes)
kubectl drain <node-name> --ignore-daemonsets --delete-emptydir-data

# Если node не восстанавливается - удалить
kubectl delete node <node-name>

# Pods автоматически переместятся на здоровые nodes
```

### 5. Network Issues

**Symptoms**: Pods running, но недоступны через service

**Diagnosis**:
```bash
# Проверить service
kubectl get svc -n production aq-security

# Проверить endpoints
kubectl get endpoints -n production aq-security

# Проверить network policies
kubectl get networkpolicies -n production

# Тест connectivity изнутри pod
kubectl exec -n production <pod-name> -- curl -s http://localhost:8080/health
```

**Resolution**:
```bash
# Если endpoints пустые - проверить selector
kubectl get svc -n production aq-security -o yaml | grep selector
kubectl get pods -n production -l app=aq-security --show-labels

# Если network policy блокирует - временно удалить
kubectl delete networkpolicy <policy-name> -n production

# Пересоздать service если нужно
kubectl delete svc -n production aq-security
kubectl apply -f k8s/service.yaml
```

### 6. Configuration Error

**Symptoms**: Pods запускаются, но сразу падают с ошибкой конфигурации

**Diagnosis**:
```bash
# Проверить environment variables
kubectl get deployment -n production aq-security -o yaml | grep -A 20 "env:"

# Проверить configmaps
kubectl get configmap -n production

# Проверить secrets
kubectl get secrets -n production

# Логи с ошибкой конфигурации
kubectl logs -n production <pod-name> | grep -i "config\|error\|fatal"
```

**Resolution**:
```bash
# Исправить configmap
kubectl edit configmap -n production aq-security-config

# Или исправить secret
kubectl edit secret -n production aq-security-secrets

# Перезапустить pods для применения изменений
kubectl rollout restart deployment/aq-security -n production
```

## Resolution Steps

### Step 1: Immediate Assessment (0-2 minutes)

```bash
# 1. Быстрая проверка статуса
kubectl get pods -n production -l app=aq-security
kubectl get deployment -n production aq-security

# 2. Проверить последние events
kubectl get events -n production --sort-by='.lastTimestamp' | tail -20

# 3. Определить масштаб проблемы
# - Все pods down? → Critical infrastructure issue
# - Некоторые pods down? → Partial outage
# - Pods running но unhealthy? → Application issue
```

### Step 2: Quick Fix Attempt (2-5 minutes)

```bash
# Если последний deploy был недавно - rollback
kubectl rollout undo deployment/aq-security -n production

# Если pods в CrashLoop - проверить зависимости
kubectl get pods -n production -l app=postgres
kubectl get pods -n production -l app=redis

# Если resource issues - временно увеличить limits
kubectl set resources deployment/aq-security -n production \
  --limits=cpu=1000m,memory=512Mi
```

### Step 3: Detailed Investigation (5-15 minutes)

```bash
# 1. Собрать все логи
kubectl logs -n production -l app=aq-security --tail=500 > /tmp/service-down-logs.txt

# 2. Проверить все зависимости
./scripts/check-dependencies.sh

# 3. Проверить recent changes
kubectl rollout history deployment/aq-security -n production
git log --oneline --since="2 hours ago"

# 4. Проверить metrics
curl -s 'http://prometheus:9090/api/v1/query?query=up{job="aq-security"}'
```

### Step 4: Apply Root Cause Fix

В зависимости от причины:
- CrashLoop → rollback или fix config
- ImagePull → fix registry credentials
- Resources → scale nodes or reduce requests
- Node failure → drain and replace node
- Network → fix service/networkpolicy
- Config → fix configmap/secret

### Step 5: Verify Recovery

```bash
# 1. Все pods running и ready
kubectl get pods -n production -l app=aq-security
# Ожидаем: STATUS=Running, READY=1/1

# 2. Health check проходит
kubectl exec -n production deployment/aq-security -- curl -s http://localhost:8080/health
# Ожидаем: {"status":"healthy"}

# 3. Prometheus видит service up
curl -s 'http://prometheus:9090/api/v1/query?query=up{job="aq-security"}'
# Ожидаем: value=1

# 4. External health check
curl -s https://aq-security.example.com/health
# Ожидаем: 200 OK
```

## Escalation

### When to Escalate

- Service down > 5 minutes без прогресса
- Проблема затрагивает infrastructure (nodes, network)
- Требуется доступ к production secrets/credentials
- Multiple services affected

### Escalation Path

1. **Level 1**: On-call engineer (you) - 0-5 min
2. **Level 2**: DevOps lead - 5-15 min
3. **Level 3**: Engineering manager + Infrastructure team - 15-30 min
4. **Level 4**: CTO + Cloud provider support - 30+ min

### Escalation Contacts

- **Immediate**: Slack `#aq-security-incidents` + PagerDuty escalation
- **DevOps Lead**: @devops-lead in Slack
- **Infrastructure Team**: PagerDuty "Infrastructure On-Call"
- **Emergency**: Phone numbers in on-call rotation doc

## Communication

### Internal Communication

```markdown
**Status Update Template** (post every 5 minutes in #aq-security-incidents):

🔴 INCIDENT: AQ Security Service Down
⏰ Duration: X minutes
🔍 Status: [Investigating | Identified | Fixing | Monitoring]
📊 Impact: [All users | Partial | Specific region]
🛠️ Action: [Current action being taken]
⏭️ Next: [Next step]
ETA: [Estimated time to resolution]
```

### External Communication

Если downtime > 10 minutes:
- Update status page: https://status.example.com
- Notify key customers via email
- Post on social media if public-facing

## Post-Incident

### 1. Immediate Actions

```bash
# Собрать все артефакты
kubectl logs -n production -l app=aq-security --since=1h > incident-logs.txt
kubectl get events -n production --sort-by='.lastTimestamp' > incident-events.txt
kubectl describe deployment -n production aq-security > incident-deployment.txt
```

### 2. Post-Mortem (в течение 24 часов)

Template: `docs/post-mortems/YYYY-MM-DD-service-down.md`

Обязательные секции:
- **Timeline**: Детальная хронология событий
- **Root Cause**: Что именно сломалось и почему
- **Impact**: Сколько пользователей затронуто, revenue impact
- **Detection**: Как мы узнали о проблеме
- **Resolution**: Что сделали для восстановления
- **Action Items**: Что делаем чтобы не повторилось

### 3. Follow-up Actions

- [ ] Review и update runbook
- [ ] Implement preventive measures
- [ ] Add monitoring/alerting gaps
- [ ] Update deployment procedures
- [ ] Schedule team review meeting

## Prevention

### Immediate (в течение недели)

- [ ] Add pre-deployment smoke tests
- [ ] Implement canary deployments
- [ ] Add automated rollback on health check failures
- [ ] Review resource limits and requests
- [ ] Test disaster recovery procedures

### Long-term (в течение месяца)

- [ ] Implement multi-region deployment
- [ ] Add chaos engineering tests
- [ ] Improve observability (tracing, profiling)
- [ ] Automate common recovery procedures
- [ ] Regular disaster recovery drills

## Related Runbooks

- [High Error Rate](./high-error-rate.md)
- [Pod Restart Loop](./pod-restart-loop.md)
- [Database Connection Failed](./database-connection-failed.md)
- [High Memory Usage](./high-memory-usage.md)

## Quick Reference

### Essential Commands

```bash
# Status check
kubectl get pods -n production -l app=aq-security

# Logs
kubectl logs -n production -l app=aq-security --tail=100

# Rollback
kubectl rollout undo deployment/aq-security -n production

# Restart
kubectl rollout restart deployment/aq-security -n production

# Scale
kubectl scale deployment/aq-security -n production --replicas=3

# Health check
kubectl exec -n production deployment/aq-security -- curl http://localhost:8080/health
```

### Decision Tree

```
Service Down
├─ Pods not running?
│  ├─ CrashLoopBackOff → Check logs, rollback if recent deploy
│  ├─ ImagePullBackOff → Fix registry credentials
│  ├─ Pending → Check resources, scale nodes
│  └─ Unknown → Check events, describe pod
├─ Pods running but unhealthy?
│  ├─ Health check failing → Check dependencies (DB, Redis)
│  ├─ High error rate → See high-error-rate runbook
│  └─ Slow response → Check resources, scale up
└─ Pods healthy but unreachable?
   ├─ Service issue → Check endpoints, recreate service
   ├─ Network policy → Review and fix policies
   └─ Ingress issue → Check ingress controller
```

## References

- [Kubernetes Troubleshooting Guide](https://kubernetes.io/docs/tasks/debug/)
- [Deployment Guide](../deployment/kubernetes.md)
- [Architecture Docs](../architecture/)
- [Grafana Dashboard](https://grafana.example.com/d/aq-security)
