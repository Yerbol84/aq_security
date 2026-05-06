# Runbook: DoS Attack Detected

## Alert Details

**Alert Name**: `DoSAttackDetected`
**Severity**: Critical
**Threshold**: DoS protection blocking > 50 requests/s for 2 minutes
**Component**: Security

## Symptoms

- Prometheus alert firing: "Potential DoS attack detected"
- `rate(dos_blocked_total{job="aq-security"}[1m]) > 50`
- Высокая нагрузка на сервис
- Legitimate users могут испытывать slowdowns
- Множество IP адресов заблокированы

## Impact

- **User Impact**: Medium - legitimate users могут быть затронуты
- **Business Impact**: Medium - потенциальная деградация сервиса
- **SLA Impact**: Possible - зависит от масштаба атаки

## Diagnosis

### 1. Проверить DoS metrics

```bash
# Текущий rate блокировок
curl -s 'http://prometheus:9090/api/v1/query?query=rate(dos_blocked_total{job="aq-security"}[1m])'

# Блокировки по причинам
curl -s 'http://prometheus:9090/api/v1/query?query=rate(dos_blocked_total{job="aq-security"}[5m])' | jq '.data.result[] | {reason: .metric.reason, value: .value[1]}'

# Количество заблокированных IP
curl -s 'http://prometheus:9090/api/v1/query?query=count(dos_ip_blocked{job="aq-security",blocked="true"})'

# Active connections
curl -s 'http://prometheus:9090/api/v1/query?query=dos_connections_active{job="aq-security"}'
```

### 2. Проверить логи атаки

```bash
# DoS блокировки в логах
kubectl logs -n production -l app=aq-security --tail=500 | grep '"dos_blocked"'

# Топ заблокированных IP
kubectl logs -n production -l app=aq-security --tail=1000 | \
  grep '"dos_blocked"' | jq -r '.ip' | sort | uniq -c | sort -rn | head -20

# Причины блокировок
kubectl logs -n production -l app=aq-security --tail=1000 | \
  grep '"dos_blocked"' | jq -r '.reason' | sort | uniq -c | sort -rn
```

### 3. Анализ паттернов атаки

```bash
# Request rate по IP
kubectl logs -n production -l app=aq-security --tail=5000 | \
  jq -r 'select(.ip != null) | .ip' | sort | uniq -c | sort -rn | head -50

# User agents атакующих
kubectl logs -n production -l app=aq-security --tail=1000 | \
  grep '"dos_blocked"' | jq -r '.user_agent' | sort | uniq -c | sort -rn | head -20

# Targeted endpoints
kubectl logs -n production -l app=aq-security --tail=1000 | \
  grep '"dos_blocked"' | jq -r '.path' | sort | uniq -c | sort -rn | head -20

# Geographic distribution (если есть GeoIP)
kubectl logs -n production -l app=aq-security --tail=1000 | \
  grep '"dos_blocked"' | jq -r '.country' | sort | uniq -c | sort -rn
```

### 4. Проверить infrastructure impact

```bash
# CPU usage
kubectl top pods -n production -l app=aq-security

# Memory usage
kubectl get pods -n production -l app=aq-security -o json | \
  jq '.items[].status.containerStatuses[].state'

# Network traffic
kubectl exec -n production deployment/aq-security -- \
  curl -s http://localhost:8080/metrics | grep http_requests_total
```

## Attack Types

### 1. High Volume Attack

**Characteristics**: Огромное количество requests с множества IP

**Diagnosis**:
```bash
# Requests per second
curl -s 'http://prometheus:9090/api/v1/query?query=rate(http_requests_total{job="aq-security"}[1m])'

# Unique IPs
kubectl logs -n production -l app=aq-security --tail=10000 | \
  jq -r '.ip' | sort -u | wc -l
```

**Response**:
```bash
# Включить более агрессивные rate limits
kubectl set env deployment/aq-security -n production \
  RATE_LIMIT_GLOBAL_RPS=100 \
  RATE_LIMIT_PER_IP_RPS=10

# Масштабировать для обработки нагрузки
kubectl scale deployment/aq-security -n production --replicas=10

# Включить CDN/WAF если доступно
# (зависит от infrastructure)
```

### 2. Slowloris Attack

**Characteristics**: Медленные connections, держат соединения открытыми

**Diagnosis**:
```bash
# Slowloris detections
curl -s 'http://prometheus:9090/api/v1/query?query=rate(dos_slowloris_detected_total{job="aq-security"}[5m])'

# Long-lived connections
kubectl logs -n production -l app=aq-security --tail=500 | \
  grep '"slowloris_detected"'
```

**Response**:
```bash
# Уменьшить connection timeout
kubectl set env deployment/aq-security -n production \
  CONNECTION_TIMEOUT=30s \
  READ_TIMEOUT=10s \
  WRITE_TIMEOUT=10s

# Уменьшить max connections per IP
kubectl set env deployment/aq-security -n production \
  MAX_CONNECTIONS_PER_IP=5
```

### 3. Application Layer Attack

**Characteristics**: Атака на конкретные endpoints (например, expensive queries)

**Diagnosis**:
```bash
# Requests по endpoints
kubectl logs -n production -l app=aq-security --tail=5000 | \
  jq -r '.path' | sort | uniq -c | sort -rn | head -20

# Response times
curl -s 'http://prometheus:9090/api/v1/query?query=histogram_quantile(0.95, rate(http_request_duration_seconds_bucket{job="aq-security"}[5m]))'
```

**Response**:
```bash
# Добавить endpoint-specific rate limits
kubectl set env deployment/aq-security -n production \
  RATE_LIMIT_EXPENSIVE_ENDPOINT_RPS=5

# Включить caching для expensive endpoints
kubectl set env deployment/aq-security -n production \
  CACHE_ENABLED=true \
  CACHE_TTL=60s

# Временно отключить expensive endpoints если критично
# (требует code change или feature flag)
```

### 4. Distributed Attack (Botnet)

**Characteristics**: Атака с множества IP, выглядит как legitimate traffic

**Diagnosis**:
```bash
# Количество уникальных IP
kubectl logs -n production -l app=aq-security --tail=10000 | \
  jq -r '.ip' | sort -u | wc -l

# Request patterns (боты часто имеют одинаковые patterns)
kubectl logs -n production -l app=aq-security --tail=5000 | \
  jq -r '"\(.ip) \(.user_agent) \(.path)"' | sort | uniq -c | sort -rn | head -50
```

**Response**:
```bash
# Включить CAPTCHA для suspicious requests
# (требует integration с CAPTCHA service)

# Блокировать по User-Agent patterns
kubectl exec -n production deployment/aq-security -- \
  curl -X POST http://localhost:8080/admin/block-user-agent \
  -d '{"pattern": "suspicious-bot-pattern"}'

# Использовать IP reputation services
# (требует integration с threat intelligence)
```

## Resolution Steps

### Step 1: Immediate Assessment (0-2 minutes)

```bash
# 1. Подтвердить атаку
curl -s 'http://prometheus:9090/api/v1/query?query=rate(dos_blocked_total{job="aq-security"}[1m])'

# 2. Определить тип атаки
kubectl logs -n production -l app=aq-security --tail=500 | \
  grep '"dos_blocked"' | jq -r '.reason' | sort | uniq -c

# 3. Оценить impact на legitimate users
curl -s 'http://prometheus:9090/api/v1/query?query=rate(http_requests_total{job="aq-security",status=~"5.."}[5m])'
```

### Step 2: Immediate Mitigation (2-5 minutes)

```bash
# 1. Масштабировать для обработки нагрузки
kubectl scale deployment/aq-security -n production --replicas=10

# 2. Включить более агрессивные rate limits
kubectl set env deployment/aq-security -n production \
  RATE_LIMIT_GLOBAL_RPS=100 \
  RATE_LIMIT_PER_IP_RPS=10 \
  MAX_CONNECTIONS_PER_IP=5

# 3. Если есть явные атакующие IP - заблокировать на firewall level
# (зависит от cloud provider)
gcloud compute firewall-rules create block-attack \
  --action=DENY \
  --rules=tcp:443 \
  --source-ranges=<attacking-ip-ranges>
```

### Step 3: Detailed Analysis (5-15 minutes)

```bash
# 1. Собрать полную картину атаки
kubectl logs -n production -l app=aq-security --since=30m > /tmp/dos-attack-logs.txt

# 2. Анализ атакующих IP
cat /tmp/dos-attack-logs.txt | grep '"dos_blocked"' | \
  jq -r '.ip' | sort | uniq -c | sort -rn > /tmp/attacking-ips.txt

# 3. Проверить legitimate users affected
cat /tmp/dos-attack-logs.txt | grep '"status":429' | \
  jq -r 'select(.ip | IN("known-legitimate-ips")) | .ip' | sort | uniq

# 4. Создать threat intelligence report
cat /tmp/attacking-ips.txt | head -100 > /tmp/threat-report.txt
```

### Step 4: Advanced Mitigation

В зависимости от типа атаки:

**High Volume**:
```bash
# Enable CDN/WAF
# Configure DDoS protection at cloud provider level
# Add geographic restrictions if attack is localized
```

**Slowloris**:
```bash
# Reduce timeouts
kubectl set env deployment/aq-security -n production \
  CONNECTION_TIMEOUT=15s \
  READ_TIMEOUT=5s
```

**Application Layer**:
```bash
# Add endpoint-specific protections
# Enable caching
# Implement CAPTCHA for expensive endpoints
```

**Distributed**:
```bash
# Use IP reputation services
# Implement behavioral analysis
# Add CAPTCHA challenges
```

### Step 5: Monitor and Adjust

```bash
# 1. Мониторить block rate
watch -n 5 'curl -s "http://prometheus:9090/api/v1/query?query=rate(dos_blocked_total{job=\"aq-security\"}[1m])" | jq ".data.result[0].value[1]"'

# 2. Мониторить legitimate user impact
watch -n 5 'curl -s "http://prometheus:9090/api/v1/query?query=rate(http_requests_total{job=\"aq-security\",status=\"429\"}[1m])" | jq ".data.result[0].value[1]"'

# 3. Adjust rate limits если нужно
# Если слишком много false positives - ослабить
# Если атака продолжается - усилить
```

## Escalation

### When to Escalate

- Attack rate > 1000 req/s
- Infrastructure overwhelmed (CPU/memory maxed)
- Legitimate users significantly impacted
- Attack continues > 30 minutes
- Requires cloud provider DDoS protection

### Escalation Path

1. **Level 1**: On-call engineer (you) - 0-10 min
2. **Level 2**: Security team + DevOps lead - 10-20 min
3. **Level 3**: Infrastructure team + Cloud provider support - 20-30 min
4. **Level 4**: CISO + Executive team - 30+ min (for major attacks)

### Escalation Contacts

- **Security Team**: Slack `#security-incidents` + PagerDuty "Security On-Call"
- **Cloud Provider**: Support ticket + phone (for DDoS protection)
- **Law Enforcement**: If attack is severe and criminal

## Communication

### Internal

```markdown
🚨 SECURITY INCIDENT: DoS Attack Detected

⏰ Started: [timestamp]
📊 Scale: [requests/s being blocked]
🎯 Type: [High Volume / Slowloris / Application Layer / Distributed]
🌍 Source: [IP ranges / countries / botnet]
💥 Impact: [None / Minor / Moderate / Severe] on legitimate users
🛡️ Mitigation: [Current actions]
📈 Status: [Under Control / Escalating / Resolved]
```

### External (if needed)

- Update status page if user-facing impact
- Notify key customers if SLA affected
- Coordinate with law enforcement if criminal activity

## Post-Incident

### Immediate Actions

```bash
# 1. Сохранить evidence
kubectl logs -n production -l app=aq-security --since=2h > incident-dos-attack-logs.txt
cat /tmp/attacking-ips.txt > incident-attacking-ips.txt

# 2. Создать threat intelligence report
# Submit attacking IPs to threat intelligence platforms
# Share with security community if appropriate

# 3. Постепенно вернуть normal rate limits
kubectl set env deployment/aq-security -n production \
  RATE_LIMIT_GLOBAL_RPS=1000 \
  RATE_LIMIT_PER_IP_RPS=100
```

### Post-Mortem

Include:
- Attack timeline and characteristics
- Detection time and response time
- Mitigation effectiveness
- Impact on legitimate users
- Lessons learned
- Prevention measures

### Follow-up

- [ ] Review and update DoS protection rules
- [ ] Implement additional protections identified
- [ ] Test incident response procedures
- [ ] Update monitoring and alerting
- [ ] Share threat intelligence

## Prevention

### Immediate (в течение недели)

- [ ] Implement CDN/WAF if not already
- [ ] Configure cloud provider DDoS protection
- [ ] Add IP reputation checking
- [ ] Implement CAPTCHA for suspicious traffic
- [ ] Set up automated blocking rules

### Long-term (в течение месяца)

- [ ] Implement behavioral analysis
- [ ] Add machine learning for anomaly detection
- [ ] Set up honeypots for threat intelligence
- [ ] Regular DoS simulation testing
- [ ] Participate in threat intelligence sharing

## Related Runbooks

- [High Rate Limit Blocks](./high-rate-limit-blocks.md)
- [High Error Rate](./high-error-rate.md)
- [Service Down](./service-down.md)

## Quick Reference

### Essential Commands

```bash
# Check DoS block rate
curl -s 'http://prometheus:9090/api/v1/query?query=rate(dos_blocked_total{job="aq-security"}[1m])'

# Top attacking IPs
kubectl logs -n production -l app=aq-security --tail=1000 | grep '"dos_blocked"' | jq -r '.ip' | sort | uniq -c | sort -rn | head -20

# Scale up
kubectl scale deployment/aq-security -n production --replicas=10

# Tighten rate limits
kubectl set env deployment/aq-security -n production RATE_LIMIT_PER_IP_RPS=10
```

### Decision Tree

```
DoS Attack Detected
├─ High volume (>1000 req/s)?
│  ├─ Yes → Enable cloud DDoS protection, scale infrastructure
│  └─ No → Continue with application-level mitigation
├─ Slowloris pattern?
│  ├─ Yes → Reduce timeouts, limit connections per IP
│  └─ No → Check other patterns
├─ Targeting specific endpoint?
│  ├─ Yes → Add endpoint rate limits, enable caching
│  └─ No → Apply global rate limits
└─ Distributed (many IPs)?
   ├─ Yes → Use IP reputation, implement CAPTCHA
   └─ No → Block specific IP ranges
```

## References

- [DoS Protection Architecture](../architecture/dos-protection.md)
- [Rate Limiting Documentation](../architecture/rate-limiting.md)
- [Security Best Practices](../security/best-practices.md)
- [Grafana DoS Dashboard](https://grafana.example.com/d/dos-protection)
