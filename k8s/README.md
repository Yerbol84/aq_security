# Kubernetes Deployment Guide

Полное руководство по развертыванию AQ Security в Kubernetes.

## Требования

- Kubernetes cluster 1.24+
- kubectl configured
- Helm 3+ (опционально)
- cert-manager для TLS сертификатов
- Ingress controller (nginx-ingress)

## Быстрый старт

```bash
# Создать namespace
kubectl create namespace production

# Создать secrets
kubectl create secret generic aq-security-secrets \
  --from-literal=database-url="postgresql://user:password@postgres:5432/aq_security" \
  --from-literal=redis-url="redis://:password@redis:6379" \
  --from-literal=jwt-secret="your-jwt-secret" \
  -n production

# Применить манифесты
kubectl apply -f k8s/ -n production

# Проверить статус
kubectl get pods -n production
kubectl get svc -n production
kubectl get ingress -n production
```

## Архитектура

### Компоненты

1. **Deployment** - AQ Security приложение
   - Replicas: 3 (min) - 10 (max)
   - Rolling update strategy
   - Security context: non-root, read-only filesystem

2. **Service** - ClusterIP service
   - Port: 80 → 8080
   - Selector: app=aq-security

3. **HorizontalPodAutoscaler** - Auto-scaling
   - CPU target: 70%
   - Memory target: 80%
   - Scale up: быстро (30s)
   - Scale down: медленно (300s)

4. **PodDisruptionBudget** - High availability
   - minAvailable: 2
   - Защита от одновременного удаления всех pods

5. **Ingress** - External access
   - TLS termination
   - Rate limiting
   - Security headers
   - CORS configuration

## Подготовка

### 1. Установить зависимости

#### cert-manager (для TLS)

```bash
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.13.0/cert-manager.yaml

# Создать ClusterIssuer для Let's Encrypt
cat <<EOF | kubectl apply -f -
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: your-email@example.com
    privateKeySecretRef:
      name: letsencrypt-prod
    solvers:
    - http01:
        ingress:
          class: nginx
EOF
```

#### nginx-ingress

```bash
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update

helm install nginx-ingress ingress-nginx/ingress-nginx \
  --namespace ingress-nginx \
  --create-namespace \
  --set controller.metrics.enabled=true \
  --set controller.podAnnotations."prometheus\.io/scrape"=true \
  --set controller.podAnnotations."prometheus\.io/port"=10254
```

### 2. Создать namespace

```bash
kubectl create namespace production

# Добавить labels
kubectl label namespace production environment=production
kubectl label namespace production monitoring=enabled
```

### 3. Создать secrets

#### Database credentials

```bash
kubectl create secret generic aq-security-secrets \
  --from-literal=database-url="postgresql://aq_user:$(openssl rand -base64 32)@postgres:5432/aq_security" \
  --from-literal=redis-url="redis://:$(openssl rand -base64 32)@redis:6379" \
  --from-literal=jwt-secret="$(openssl rand -hex 32)" \
  -n production
```

#### TLS certificates (если не используете cert-manager)

```bash
kubectl create secret tls aq-security-tls \
  --cert=path/to/tls.crt \
  --key=path/to/tls.key \
  -n production
```

#### Grafana basic auth

```bash
htpasswd -c auth admin
kubectl create secret generic grafana-basic-auth \
  --from-file=auth \
  -n production
```

#### Prometheus basic auth

```bash
htpasswd -c auth admin
kubectl create secret generic prometheus-basic-auth \
  --from-file=auth \
  -n production
```

## Развертывание

### 1. Обновить конфигурацию

Отредактируйте `k8s/deployment.yaml`:

```yaml
# Обновить image
spec:
  template:
    spec:
      containers:
      - name: aq-security
        image: your-registry/aq-security:v1.0.0  # <-- Изменить
```

Отредактируйте `k8s/ingress.yaml`:

```yaml
# Обновить домены
spec:
  tls:
  - hosts:
    - api.your-domain.com  # <-- Изменить
  rules:
  - host: api.your-domain.com  # <-- Изменить
```

### 2. Применить манифесты

```bash
# Применить все манифесты
kubectl apply -f k8s/ -n production

# Или по отдельности
kubectl apply -f k8s/deployment.yaml -n production
kubectl apply -f k8s/ingress.yaml -n production
```

### 3. Проверить развертывание

```bash
# Проверить pods
kubectl get pods -n production -w

# Проверить deployment
kubectl rollout status deployment/aq-security -n production

# Проверить logs
kubectl logs -f deployment/aq-security -n production
```

## Управление

### Scaling

```bash
# Manual scaling
kubectl scale deployment aq-security --replicas=5 -n production

# HPA автоматически управляет scaling
kubectl get hpa -n production
```

### Rolling Update

```bash
# Обновить image
kubectl set image deployment/aq-security \
  aq-security=your-registry/aq-security:v1.1.0 \
  -n production

# Проверить статус
kubectl rollout status deployment/aq-security -n production

# Откатить если нужно
kubectl rollout undo deployment/aq-security -n production
```

### Restart

```bash
# Restart всех pods
kubectl rollout restart deployment/aq-security -n production
```

### Logs

```bash
# Все pods
kubectl logs -f deployment/aq-security -n production

# Конкретный pod
kubectl logs -f aq-security-xxx-yyy -n production

# Предыдущий container (если crashed)
kubectl logs aq-security-xxx-yyy -n production --previous
```

## Мониторинг

### Prometheus

Prometheus автоматически обнаружит pods с labels:
```yaml
prometheus.io/scrape: "true"
prometheus.io/port: "8080"
prometheus.io/path: "/metrics"
```

Проверить targets:
```bash
kubectl port-forward -n monitoring svc/prometheus 9090:9090
# Открыть http://localhost:9090/targets
```

### Grafana

```bash
# Port forward
kubectl port-forward -n monitoring svc/grafana 3000:3000

# Открыть http://localhost:3000
# Credentials: admin/admin
```

### Metrics

```bash
# CPU и Memory usage
kubectl top pods -n production

# HPA status
kubectl get hpa aq-security -n production

# Events
kubectl get events -n production --sort-by='.lastTimestamp'
```

## Health Checks

### Application Health

```bash
# Port forward
kubectl port-forward -n production svc/aq-security 8080:80

# Check health
curl http://localhost:8080/api/health
```

### Liveness/Readiness Probes

Проверить статус probes:
```bash
kubectl describe pod aq-security-xxx-yyy -n production | grep -A 10 "Liveness\|Readiness"
```

## Troubleshooting

### Pod не запускается

```bash
# Проверить events
kubectl describe pod aq-security-xxx-yyy -n production

# Проверить logs
kubectl logs aq-security-xxx-yyy -n production

# Проверить init containers
kubectl logs aq-security-xxx-yyy -n production -c wait-for-postgres
```

### ImagePullBackOff

```bash
# Проверить image
kubectl describe pod aq-security-xxx-yyy -n production | grep Image

# Проверить registry credentials
kubectl get secret -n production
```

### CrashLoopBackOff

```bash
# Проверить logs предыдущего container
kubectl logs aq-security-xxx-yyy -n production --previous

# Проверить liveness probe
kubectl describe pod aq-security-xxx-yyy -n production | grep Liveness
```

### Database connection failed

```bash
# Проверить secrets
kubectl get secret aq-security-secrets -n production -o yaml

# Проверить connectivity
kubectl run -it --rm debug --image=busybox --restart=Never -n production -- sh
# В shell: nc -zv postgres 5432
```

### High memory usage

```bash
# Проверить usage
kubectl top pods -n production

# Увеличить limits в deployment.yaml
resources:
  limits:
    memory: "1Gi"  # Увеличить
```

## Backup и Recovery

### Database Backup

```bash
# Создать CronJob для backup
cat <<EOF | kubectl apply -f -
apiVersion: batch/v1
kind: CronJob
metadata:
  name: postgres-backup
  namespace: production
spec:
  schedule: "0 2 * * *"  # Daily at 2am
  jobTemplate:
    spec:
      template:
        spec:
          containers:
          - name: backup
            image: postgres:15-alpine
            command:
            - /bin/sh
            - -c
            - pg_dump -h postgres -U aq_user aq_security | gzip > /backup/backup-\$(date +%Y%m%d).sql.gz
            env:
            - name: PGPASSWORD
              valueFrom:
                secretKeyRef:
                  name: aq-security-secrets
                  key: database-password
            volumeMounts:
            - name: backup
              mountPath: /backup
          volumes:
          - name: backup
            persistentVolumeClaim:
              claimName: backup-pvc
          restartPolicy: OnFailure
EOF
```

### Application State Backup

```bash
# Backup всех манифестов
kubectl get all,ingress,configmap,secret -n production -o yaml > backup.yaml

# Восстановить
kubectl apply -f backup.yaml
```

## Security Best Practices

### 1. Network Policies

```bash
cat <<EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: aq-security-netpol
  namespace: production
spec:
  podSelector:
    matchLabels:
      app: aq-security
  policyTypes:
  - Ingress
  - Egress
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          name: ingress-nginx
    ports:
    - protocol: TCP
      port: 8080
  egress:
  - to:
    - podSelector:
        matchLabels:
          app: postgres
    ports:
    - protocol: TCP
      port: 5432
  - to:
    - podSelector:
        matchLabels:
          app: redis
    ports:
    - protocol: TCP
      port: 6379
EOF
```

### 2. Pod Security Standards

```bash
# Enforce restricted policy
kubectl label namespace production \
  pod-security.kubernetes.io/enforce=restricted \
  pod-security.kubernetes.io/audit=restricted \
  pod-security.kubernetes.io/warn=restricted
```

### 3. RBAC

```bash
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ServiceAccount
metadata:
  name: aq-security
  namespace: production
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: aq-security-role
  namespace: production
rules:
- apiGroups: [""]
  resources: ["configmaps", "secrets"]
  verbs: ["get", "list"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: aq-security-rolebinding
  namespace: production
subjects:
- kind: ServiceAccount
  name: aq-security
  namespace: production
roleRef:
  kind: Role
  name: aq-security-role
  apiGroup: rbac.authorization.k8s.io
EOF
```

## Production Checklist

- [ ] cert-manager установлен и настроен
- [ ] nginx-ingress установлен
- [ ] Namespace создан с labels
- [ ] Secrets созданы с сильными паролями
- [ ] Image registry настроен
- [ ] Домены обновлены в Ingress
- [ ] TLS сертификаты настроены
- [ ] HPA настроен
- [ ] PodDisruptionBudget настроен
- [ ] Resource limits установлены
- [ ] Liveness/Readiness probes настроены
- [ ] Prometheus scraping настроен
- [ ] Grafana dashboards импортированы
- [ ] Backup CronJob настроен
- [ ] Network Policies применены
- [ ] RBAC настроен
- [ ] Load testing проведено

## Дополнительные ресурсы

- [Kubernetes Documentation](https://kubernetes.io/docs/)
- [nginx-ingress Documentation](https://kubernetes.github.io/ingress-nginx/)
- [cert-manager Documentation](https://cert-manager.io/docs/)
- [Prometheus Operator](https://github.com/prometheus-operator/prometheus-operator)
