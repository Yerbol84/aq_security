# Runbooks Index

Пошаговые инструкции для реагирования на production инциденты.

## Critical Alerts

### Application Issues
- [High Error Rate](./high-error-rate.md) - Error rate > 5% for 5 minutes
- [Service Down](./service-down.md) - Service unavailable for 1 minute
- [High Memory Usage](./high-memory-usage.md) - Memory usage > 450MB for 5 minutes
- [Pod Restart Loop](./pod-restart-loop.md) - Pod restarting frequently

### Database Issues
- [Database Connection Failed](./database-connection-failed.md) - Database connection errors
- [Slow Database Queries](./slow-database-queries.md) - P95 query time > 0.5s

### Security Issues
- [DoS Attack Detected](./dos-attack-detected.md) - DoS protection blocking > 50 req/s
- [High Rate Limit Blocks](./high-rate-limit-blocks.md) - Rate limit blocking > 10 req/s
- [High Auth Failure Rate](./high-auth-failure-rate.md) - Auth failure rate > 30%

### Infrastructure Issues
- [Not Enough Healthy Pods](./not-enough-healthy-pods.md) - Less than 2 healthy pods
- [HPA At Max Replicas](./hpa-at-max-replicas.md) - HPA at maximum for 15 minutes

## How to Use Runbooks

### During an Incident

1. **Identify the alert** - Check Prometheus/Grafana/PagerDuty
2. **Open the runbook** - Find the corresponding runbook from the list above
3. **Follow the steps** - Execute diagnosis and resolution steps in order
4. **Escalate if needed** - Follow escalation path if issue persists
5. **Document actions** - Keep timeline of actions taken

### Runbook Structure

Each runbook contains:

- **Alert Details** - Severity, threshold, component
- **Symptoms** - What you'll see when this alert fires
- **Impact** - User, business, and SLA impact
- **Diagnosis** - Commands to identify root cause
- **Common Causes** - Typical reasons for this alert
- **Resolution Steps** - Step-by-step fix procedures
- **Escalation** - When and how to escalate
- **Post-Incident** - Actions after resolution
- **Prevention** - How to prevent recurrence

### Quick Start

```bash
# 1. Check alert in Prometheus
open https://prometheus.example.com/alerts

# 2. Check Grafana dashboard
open https://grafana.example.com/d/aq-security

# 3. Get pod status
kubectl get pods -n production -l app=aq-security

# 4. Check recent logs
kubectl logs -n production -l app=aq-security --tail=100

# 5. Open appropriate runbook and follow steps
```

## Incident Response Process

### Phase 1: Detection (0-2 minutes)

- Alert fires in Prometheus/PagerDuty
- On-call engineer acknowledges
- Open incident channel in Slack: `#aq-security-incidents`
- Post initial status update

### Phase 2: Diagnosis (2-10 minutes)

- Follow runbook diagnosis steps
- Identify root cause
- Assess impact and severity
- Decide on mitigation strategy

### Phase 3: Mitigation (10-30 minutes)

- Execute resolution steps from runbook
- Monitor metrics for improvement
- Escalate if needed
- Keep stakeholders updated every 5-10 minutes

### Phase 4: Recovery (30-60 minutes)

- Verify service fully recovered
- Monitor for recurrence
- Document timeline and actions
- Resolve alert

### Phase 5: Post-Incident (within 24 hours)

- Write post-mortem
- Identify action items
- Update runbooks with lessons learned
- Schedule team review

## Escalation Paths

### Level 1: On-Call Engineer (0-10 minutes)
- Initial response
- Follow runbook
- Basic troubleshooting

### Level 2: Senior Engineer / Team Lead (10-20 minutes)
- Complex issues
- Requires deep system knowledge
- Multiple services affected

### Level 3: Engineering Manager + DevOps Lead (20-30 minutes)
- Infrastructure issues
- Requires coordination across teams
- Major outage

### Level 4: CTO + Executive Team (30+ minutes)
- Critical business impact
- External communication needed
- Legal/compliance implications

## Communication Templates

### Initial Alert

```markdown
🚨 INCIDENT: [Alert Name]
⏰ Started: [timestamp]
📊 Severity: [Critical/High/Medium]
💥 Impact: [Description]
👤 Responder: @[your-name]
📖 Runbook: [link]
🔍 Status: Investigating
```

### Status Update (every 5-10 minutes)

```markdown
⏰ Update [HH:MM]
🔍 Status: [Investigating/Identified/Fixing/Monitoring]
📝 Progress: [What's been done]
⏭️ Next: [Next action]
⏱️ ETA: [Estimated resolution time]
```

### Resolution

```markdown
✅ RESOLVED: [Alert Name]
⏰ Duration: [X minutes]
🔍 Root Cause: [Brief description]
🛠️ Fix: [What was done]
📋 Follow-up: [Action items]
📄 Post-mortem: [Link when ready]
```

## Common Commands

### Kubernetes

```bash
# Pod status
kubectl get pods -n production -l app=aq-security

# Logs
kubectl logs -n production -l app=aq-security --tail=100

# Describe pod
kubectl describe pod -n production <pod-name>

# Restart deployment
kubectl rollout restart deployment/aq-security -n production

# Rollback deployment
kubectl rollout undo deployment/aq-security -n production

# Scale deployment
kubectl scale deployment/aq-security -n production --replicas=5

# Check events
kubectl get events -n production --sort-by='.lastTimestamp' | tail -20
```

### Prometheus Queries

```bash
# Error rate
rate(http_requests_total{job="aq-security",status=~"5.."}[5m]) / rate(http_requests_total{job="aq-security"}[5m]) * 100

# Response time p95
histogram_quantile(0.95, rate(http_request_duration_seconds_bucket{job="aq-security"}[5m]))

# DoS block rate
rate(dos_blocked_total{job="aq-security"}[1m])

# Database errors
rate(db_connection_errors_total{job="aq-security"}[5m])
```

### Database

```bash
# Connection count
kubectl exec -n production -l app=postgres -- psql -U postgres -c "SELECT count(*) FROM pg_stat_activity"

# Kill idle connections
kubectl exec -n production -l app=postgres -- psql -U postgres -c "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE state = 'idle'"

# Check locks
kubectl exec -n production -l app=postgres -- psql -U postgres -c "SELECT * FROM pg_locks WHERE NOT granted"
```

## Contacts

### Slack Channels
- `#aq-security-incidents` - Active incidents
- `#aq-security-alerts` - Alert notifications
- `#database-team` - Database issues
- `#security-team` - Security incidents

### PagerDuty
- "AQ Security On-Call" - Primary escalation
- "Backend Engineering" - Level 2 escalation
- "Infrastructure On-Call" - Infrastructure issues
- "Security On-Call" - Security incidents

### External
- Cloud Provider Support: [support portal]
- Database Administrator: @dba-oncall
- Security Team: @security-oncall

## Tools and Dashboards

### Monitoring
- [Prometheus](https://prometheus.example.com)
- [Grafana - Application Overview](https://grafana.example.com/d/aq-security)
- [Grafana - Rate Limiting](https://grafana.example.com/d/rate-limiting)
- [Grafana - DoS Protection](https://grafana.example.com/d/dos-protection)
- [Grafana - Performance](https://grafana.example.com/d/performance)

### Logs
- [Grafana Loki](https://loki.example.com)
- Kubernetes logs: `kubectl logs`

### Incident Management
- [PagerDuty](https://aq-studio.pagerduty.com)
- [Status Page](https://status.example.com)

## Training and Drills

### Monthly Drills
- Practice incident response procedures
- Test runbook accuracy
- Verify escalation paths
- Update contact information

### Quarterly Reviews
- Review all incidents from quarter
- Update runbooks with lessons learned
- Identify patterns and prevention opportunities
- Team training on new procedures

## Contributing to Runbooks

### When to Update
- After every incident (add lessons learned)
- When procedures change
- When new tools/dashboards added
- When contact information changes

### How to Update
1. Create branch: `git checkout -b update-runbook-[name]`
2. Edit runbook markdown file
3. Test commands and procedures
4. Submit PR with description of changes
5. Get review from team lead
6. Merge and announce in team channel

### Runbook Quality Checklist
- [ ] Commands are tested and work
- [ ] Links are valid
- [ ] Contact information is current
- [ ] Escalation paths are clear
- [ ] Examples are realistic
- [ ] Prevention section is actionable

## Related Documentation

- [Architecture Overview](../architecture/README.md)
- [Deployment Guide](../deployment/kubernetes.md)
- [Monitoring Setup](../monitoring/README.md)
- [Security Best Practices](../security/best-practices.md)
- [Post-Mortem Template](../templates/post-mortem.md)

---

**Last Updated**: 2026-04-11
**Maintained By**: AQ Security Team
**Questions**: #aq-security in Slack
