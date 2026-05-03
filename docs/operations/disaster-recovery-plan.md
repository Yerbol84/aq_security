# Disaster Recovery Plan

## Recovery Objectives

### RTO (Recovery Time Objective)

**Definition**: Максимальное допустимое время простоя после инцидента.

| Severity | RTO | Description |
|----------|-----|-------------|
| Critical (P0) | 15 minutes | Complete service outage, data loss risk |
| High (P1) | 1 hour | Partial service degradation, no data loss |
| Medium (P2) | 4 hours | Non-critical features affected |
| Low (P3) | 24 hours | Minor issues, workarounds available |

### RPO (Recovery Point Objective)

**Definition**: Максимальный допустимый объем потери данных (в единицах времени).

| Data Type | RPO | Backup Frequency | Retention |
|-----------|-----|------------------|-----------|
| Database (PostgreSQL) | 24 hours | Daily at 2 AM | 30 days |
| Audit logs | 1 hour | Continuous to persistent storage | 90 days |
| Configuration | 0 (no loss) | Version controlled in Git | Indefinite |
| Secrets | 0 (no loss) | Managed by Vault/AWS Secrets Manager | Indefinite |

**Current State**:
- Database backups: Daily (RPO = 24 hours)
- Audit logs: Persistent storage (RPO = 0)
- Application state: Stateless (RPO = 0)

**Target State** (для улучшения):
- Database: Continuous replication (RPO = 5 minutes)
- Point-in-time recovery capability

## Disaster Scenarios

### Scenario 1: Complete Service Outage

**Symptoms**: All pods down, service unreachable

**Impact**:
- RTO: 15 minutes
- RPO: 24 hours (last database backup)
- User Impact: Complete service unavailability

**Recovery Steps**:

1. **Immediate (0-5 min)**:
   ```bash
   # Check pod status
   kubectl get pods -n production -l app=aq-security

   # Check recent events
   kubectl get events -n production --sort-by='.lastTimestamp' | tail -20

   # Restart deployment
   kubectl rollout restart deployment/aq-security -n production
   ```

2. **If restart fails (5-10 min)**:
   ```bash
   # Rollback to previous version
   kubectl rollout undo deployment/aq-security -n production

   # Or use GitHub Actions rollback workflow
   # Go to: https://github.com/your-org/aq-security/actions/workflows/rollback.yml
   ```

3. **If rollback fails (10-15 min)**:
   ```bash
   # Deploy from known good image
   kubectl set image deployment/aq-security \
     aq-security=your-registry/aq-security:stable \
     -n production
   ```

**Escalation**: If not resolved in 15 minutes → Level 3 (Engineering Manager + DevOps Lead)

### Scenario 2: Database Failure

**Symptoms**: Database connection errors, data unavailable

**Impact**:
- RTO: 30 minutes
- RPO: 24 hours
- User Impact: All data operations fail

**Recovery Steps**:

1. **Check database status (0-5 min)**:
   ```bash
   kubectl get pods -n production -l app=postgres
   kubectl logs -n production -l app=postgres --tail=100
   ```

2. **Restart database (5-10 min)**:
   ```bash
   kubectl delete pod -n production <postgres-pod-name>
   # Wait for pod to restart
   kubectl wait --for=condition=ready pod -l app=postgres -n production --timeout=5m
   ```

3. **If data corruption detected (10-30 min)**:
   ```bash
   # List available backups
   kubectl exec -n production <backup-pod> -- ls -lh /backup/

   # Restore from latest backup
   kubectl create job --from=job/postgres-restore postgres-restore-emergency -n production
   kubectl set env job/postgres-restore-emergency BACKUP_FILE=<latest-backup> -n production

   # Monitor restore
   kubectl logs -f job/postgres-restore-emergency -n production
   ```

**Escalation**: If not resolved in 30 minutes → Level 3 + DBA

### Scenario 3: Data Center Failure

**Symptoms**: Entire Kubernetes cluster unreachable

**Impact**:
- RTO: 2 hours
- RPO: 24 hours
- User Impact: Complete outage

**Recovery Steps**:

1. **Verify outage scope (0-10 min)**:
   ```bash
   # Check cluster health
   kubectl cluster-info

   # Check node status
   kubectl get nodes

   # Contact cloud provider if infrastructure issue
   ```

2. **Failover to backup region (10-60 min)**:
   ```bash
   # Switch kubectl context to backup cluster
   kubectl config use-context backup-cluster

   # Deploy application
   kubectl apply -f k8s/ -n production

   # Restore database from backup
   # (Assuming backups are replicated to backup region)
   ```

3. **Update DNS (60-120 min)**:
   ```bash
   # Update DNS to point to backup region
   # (Depends on DNS provider)

   # Verify traffic routing
   curl -I https://api.your-domain.com/auth/health
   ```

**Escalation**: Immediate → Level 4 (CTO + Cloud Provider Support)

### Scenario 4: Security Breach

**Symptoms**: Unauthorized access detected, suspicious activity

**Impact**:
- RTO: Varies (may require complete rebuild)
- RPO: 0 (preserve all data for forensics)
- User Impact: Service may be taken offline intentionally

**Recovery Steps**:

1. **Immediate containment (0-15 min)**:
   ```bash
   # Isolate affected pods
   kubectl scale deployment/aq-security -n production --replicas=0

   # Block external access
   kubectl delete ingress aq-security -n production

   # Preserve evidence
   kubectl logs -n production -l app=aq-security --all-containers > incident-logs.txt
   ```

2. **Investigation (15-60 min)**:
   - Analyze logs for breach vector
   - Check audit trail
   - Identify compromised credentials
   - Assess data exposure

3. **Remediation (60-240 min)**:
   ```bash
   # Rotate all secrets
   kubectl delete secret postgres-credentials -n production
   kubectl create secret generic postgres-credentials --from-literal=...

   # Deploy patched version
   kubectl apply -f k8s/deployment.yaml -n production

   # Restore service with enhanced monitoring
   kubectl scale deployment/aq-security -n production --replicas=3
   ```

**Escalation**: Immediate → Security Team + Level 4

### Scenario 5: Data Corruption

**Symptoms**: Invalid data in database, application errors

**Impact**:
- RTO: 1 hour
- RPO: 24 hours (last known good backup)
- User Impact: Data inconsistency, potential data loss

**Recovery Steps**:

1. **Assess corruption scope (0-15 min)**:
   ```bash
   # Check database integrity
   kubectl exec -n production -l app=postgres -- \
     psql -U postgres -d aq_security -c "SELECT * FROM pg_stat_database"

   # Identify affected tables
   kubectl exec -n production -l app=postgres -- \
     psql -U postgres -d aq_security -c "SELECT schemaname, tablename FROM pg_tables"
   ```

2. **Attempt repair (15-30 min)**:
   ```bash
   # Run VACUUM and ANALYZE
   kubectl exec -n production -l app=postgres -- \
     psql -U postgres -d aq_security -c "VACUUM FULL ANALYZE"

   # Check for constraint violations
   kubectl exec -n production -l app=postgres -- \
     psql -U postgres -d aq_security -c "SELECT * FROM pg_constraint"
   ```

3. **Restore from backup if needed (30-60 min)**:
   ```bash
   # Restore to point before corruption
   kubectl create job --from=job/postgres-restore postgres-restore-corruption -n production
   kubectl set env job/postgres-restore-corruption BACKUP_FILE=<backup-before-corruption> -n production
   ```

**Escalation**: If data loss > 1 hour → Level 3 + DBA

## Recovery Procedures

### Database Restore Procedure

**Prerequisites**:
- Access to Kubernetes cluster
- Backup files available in PVC
- Database credentials

**Steps**:

1. **List available backups**:
   ```bash
   kubectl exec -n production <backup-pod> -- ls -lh /backup/
   ```

2. **Choose backup to restore**:
   ```bash
   BACKUP_FILE="aq_security_20260411_020000.sql.gz"
   ```

3. **Stop application pods** (to prevent writes during restore):
   ```bash
   kubectl scale deployment/aq-security -n production --replicas=0
   ```

4. **Run restore job**:
   ```bash
   kubectl create job --from=job/postgres-restore postgres-restore-$(date +%s) -n production
   kubectl set env job/postgres-restore-$(date +%s) BACKUP_FILE=$BACKUP_FILE -n production
   ```

5. **Monitor restore**:
   ```bash
   kubectl logs -f job/postgres-restore-$(date +%s) -n production
   ```

6. **Verify restore**:
   ```bash
   kubectl exec -n production -l app=postgres -- \
     psql -U postgres -d aq_security -c "SELECT COUNT(*) FROM pg_tables"
   ```

7. **Restart application**:
   ```bash
   kubectl scale deployment/aq-security -n production --replicas=3
   ```

8. **Verify application health**:
   ```bash
   curl https://api.your-domain.com/auth/health
   ```

### Rollback Procedure

**Prerequisites**:
- Access to GitHub Actions or kubectl
- Knowledge of target revision

**Option 1: GitHub Actions** (Recommended):

1. Go to: https://github.com/your-org/aq-security/actions/workflows/rollback.yml
2. Click "Run workflow"
3. Select environment (staging/production)
4. Enter revision number (or leave empty for previous)
5. Click "Run workflow"
6. Monitor progress in Actions tab

**Option 2: kubectl**:

```bash
# Check rollout history
kubectl rollout history deployment/aq-security -n production

# Rollback to previous
kubectl rollout undo deployment/aq-security -n production

# Or rollback to specific revision
kubectl rollout undo deployment/aq-security -n production --to-revision=5

# Monitor rollback
kubectl rollout status deployment/aq-security -n production
```

### Secret Rotation Procedure

**When to rotate**:
- Security breach suspected
- Scheduled rotation (quarterly)
- Employee offboarding
- Compliance requirement

**Steps**:

1. **Generate new secrets**:
   ```bash
   # Database password
   NEW_DB_PASSWORD=$(openssl rand -base64 32)

   # JWT secret
   NEW_JWT_SECRET=$(openssl rand -base64 64)
   ```

2. **Update secrets in Vault/AWS Secrets Manager**:
   ```bash
   # Using AWS Secrets Manager
   aws secretsmanager update-secret \
     --secret-id aq-security/db-password \
     --secret-string "$NEW_DB_PASSWORD"
   ```

3. **Update Kubernetes secrets**:
   ```bash
   kubectl create secret generic postgres-credentials \
     --from-literal=username=aq_user \
     --from-literal=password=$NEW_DB_PASSWORD \
     -n production --dry-run=client -o yaml | kubectl apply -f -
   ```

4. **Update database password**:
   ```bash
   kubectl exec -n production -l app=postgres -- \
     psql -U postgres -c "ALTER USER aq_user WITH PASSWORD '$NEW_DB_PASSWORD'"
   ```

5. **Restart application pods**:
   ```bash
   kubectl rollout restart deployment/aq-security -n production
   ```

6. **Verify connectivity**:
   ```bash
   kubectl logs -n production -l app=aq-security --tail=50 | grep -i "database\|connection"
   ```

## Testing and Drills

### Monthly Drills

**Backup Restore Drill** (First Monday of month):
- Restore latest backup to staging environment
- Verify data integrity
- Document time taken
- Update procedures if needed

**Rollback Drill** (Second Monday of month):
- Deploy test version to staging
- Perform rollback
- Verify service recovery
- Document time taken

### Quarterly Drills

**Full Disaster Recovery** (First week of quarter):
- Simulate complete outage
- Execute full recovery procedure
- Involve all team members
- Document lessons learned
- Update DR plan

**Security Incident Response** (Second week of quarter):
- Simulate security breach
- Execute containment and recovery
- Test communication procedures
- Update incident response plan

### Annual Tests

**Multi-Region Failover** (Once per year):
- Test failover to backup region
- Verify DNS switching
- Test data replication
- Document RTO/RPO achieved

## Communication Plan

### Internal Communication

**Incident Channels**:
- Slack: `#aq-security-incidents` (active incidents)
- PagerDuty: Automated escalation
- Email: incident-team@your-domain.com

**Status Updates**:
- Every 15 minutes during active incident
- Include: current status, actions taken, ETA
- Use standard template (see runbooks)

### External Communication

**Status Page**: https://status.your-domain.com
- Update within 5 minutes of confirmed outage
- Provide estimated resolution time
- Update every 30 minutes

**Customer Notifications**:
- Email to affected customers
- In-app notifications
- Social media (if public-facing)

**Post-Incident**:
- Post-mortem published within 48 hours
- Lessons learned shared with customers
- Action items tracked publicly

## Contacts

### Emergency Contacts

| Role | Primary | Backup | Phone | Email |
|------|---------|--------|-------|-------|
| On-Call Engineer | Rotation | Rotation | PagerDuty | oncall@your-domain.com |
| DevOps Lead | Name | Name | +1-XXX-XXX-XXXX | devops-lead@your-domain.com |
| DBA | Name | Name | +1-XXX-XXX-XXXX | dba@your-domain.com |
| Security Lead | Name | Name | +1-XXX-XXX-XXXX | security@your-domain.com |
| Engineering Manager | Name | Name | +1-XXX-XXX-XXXX | eng-manager@your-domain.com |
| CTO | Name | Name | +1-XXX-XXX-XXXX | cto@your-domain.com |

### External Contacts

| Service | Contact | Phone | Portal |
|---------|---------|-------|--------|
| Cloud Provider | Support | +1-XXX-XXX-XXXX | https://console.cloud.provider.com |
| DNS Provider | Support | +1-XXX-XXX-XXXX | https://dns.provider.com |
| Monitoring | Support | +1-XXX-XXX-XXXX | https://monitoring.provider.com |

## Appendix

### Backup Verification Checklist

- [ ] Backup file exists
- [ ] Backup file size > 1KB
- [ ] Backup file is not corrupted (gzip -t)
- [ ] Backup contains expected tables
- [ ] Backup timestamp is recent
- [ ] Backup is accessible from restore job

### Recovery Verification Checklist

- [ ] All pods are running
- [ ] Health check returns 200 OK
- [ ] Database connections successful
- [ ] No errors in application logs
- [ ] Metrics show normal operation
- [ ] Sample API requests succeed
- [ ] Monitoring alerts cleared

### Post-Incident Checklist

- [ ] Timeline documented
- [ ] Root cause identified
- [ ] Impact assessed (users, revenue, data)
- [ ] Recovery steps documented
- [ ] Post-mortem written
- [ ] Action items created
- [ ] Runbooks updated
- [ ] Team debrief scheduled
- [ ] Customers notified (if applicable)
- [ ] Status page updated

---

**Last Updated**: 2026-04-11
**Next Review**: 2026-07-11
**Owner**: DevOps Team
**Approved By**: CTO
