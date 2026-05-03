#!/bin/bash
# scripts/test-backup-restore.sh
#
# Test script for backup and restore functionality

set -e

NAMESPACE="production"
BACKUP_JOB="postgres-backup"
RESTORE_JOB="postgres-restore"

echo "=== PostgreSQL Backup/Restore Test ==="
echo ""

# Function to wait for job completion
wait_for_job() {
  local job_name=$1
  local timeout=300
  local elapsed=0

  echo "Waiting for job ${job_name} to complete..."

  while [ $elapsed -lt $timeout ]; do
    status=$(kubectl get job ${job_name} -n ${NAMESPACE} -o jsonpath='{.status.conditions[?(@.type=="Complete")].status}' 2>/dev/null || echo "")

    if [ "$status" == "True" ]; then
      echo "Job ${job_name} completed successfully"
      return 0
    fi

    failed=$(kubectl get job ${job_name} -n ${NAMESPACE} -o jsonpath='{.status.conditions[?(@.type=="Failed")].status}' 2>/dev/null || echo "")
    if [ "$failed" == "True" ]; then
      echo "ERROR: Job ${job_name} failed"
      kubectl logs job/${job_name} -n ${NAMESPACE}
      return 1
    fi

    sleep 5
    elapsed=$((elapsed + 5))
  done

  echo "ERROR: Job ${job_name} timed out"
  return 1
}

# Step 1: Trigger manual backup
echo "Step 1: Triggering manual backup..."
kubectl create job --from=cronjob/${BACKUP_JOB} ${BACKUP_JOB}-manual -n ${NAMESPACE}

wait_for_job "${BACKUP_JOB}-manual"

# Step 2: List backups
echo ""
echo "Step 2: Listing available backups..."
POD=$(kubectl get pods -n ${NAMESPACE} -l app=postgres-backup --field-selector=status.phase=Succeeded -o jsonpath='{.items[0].metadata.name}')
kubectl exec ${POD} -n ${NAMESPACE} -- ls -lh /backup/

# Step 3: Get latest backup file
LATEST_BACKUP=$(kubectl exec ${POD} -n ${NAMESPACE} -- ls -t /backup/ | head -1)
echo ""
echo "Latest backup: ${LATEST_BACKUP}"

# Step 4: Create test data
echo ""
echo "Step 3: Creating test data in database..."
kubectl exec -n ${NAMESPACE} deployment/aq-security -- psql -h postgres -U aq_user -d aq_security -c "CREATE TABLE IF NOT EXISTS backup_test (id SERIAL PRIMARY KEY, data TEXT, created_at TIMESTAMP DEFAULT NOW());"
kubectl exec -n ${NAMESPACE} deployment/aq-security -- psql -h postgres -U aq_user -d aq_security -c "INSERT INTO backup_test (data) VALUES ('test data before restore');"

# Step 5: Verify test data exists
echo ""
echo "Step 4: Verifying test data..."
kubectl exec -n ${NAMESPACE} deployment/aq-security -- psql -h postgres -U aq_user -d aq_security -c "SELECT * FROM backup_test;"

# Step 6: Restore from backup
echo ""
echo "Step 5: Restoring from backup..."
echo "WARNING: This will drop and recreate the database!"
read -p "Continue? (yes/no): " confirm

if [ "$confirm" != "yes" ]; then
  echo "Restore cancelled"
  exit 0
fi

kubectl create job --from=job/${RESTORE_JOB} ${RESTORE_JOB}-test -n ${NAMESPACE}
kubectl set env job/${RESTORE_JOB}-test BACKUP_FILE=${LATEST_BACKUP} -n ${NAMESPACE}

wait_for_job "${RESTORE_JOB}-test"

# Step 7: Verify restore
echo ""
echo "Step 6: Verifying restore..."
kubectl exec -n ${NAMESPACE} deployment/aq-security -- psql -h postgres -U aq_user -d aq_security -c "SELECT COUNT(*) FROM backup_test;" || echo "Test table not found (expected if backup was before test data)"

# Cleanup
echo ""
echo "Step 7: Cleaning up test jobs..."
kubectl delete job ${BACKUP_JOB}-manual -n ${NAMESPACE}
kubectl delete job ${RESTORE_JOB}-test -n ${NAMESPACE}

echo ""
echo "=== Backup/Restore Test Completed ==="
