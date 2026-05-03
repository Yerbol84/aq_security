# Docker Deployment Guide

Полное руководство по развертыванию AQ Security в Docker.

## Быстрый старт

```bash
# Клонировать репозиторий
git clone <repository-url>
cd aq_security

# Создать .env файл
cp docker/.env.example docker/.env
# Отредактировать docker/.env с реальными значениями

# Запустить весь стек
cd docker
docker-compose up -d

# Проверить статус
docker-compose ps

# Просмотреть логи
docker-compose logs -f app
```

## Архитектура стека

Docker Compose стек включает 10 сервисов:

### Основные сервисы

1. **app** - AQ Security приложение
   - Порт: 8080
   - Health check: `/api/health`
   - Зависит от: postgres, redis

2. **postgres** - PostgreSQL база данных
   - Порт: 5432
   - Версия: 15-alpine
   - Persistent volume: `postgres_data`

3. **redis** - Redis кэш и rate limiting
   - Порт: 6379
   - Версия: 7-alpine
   - Persistent volume: `redis_data`

### Мониторинг

4. **prometheus** - Сбор метрик
   - Порт: 9090
   - Scrape interval: 15s
   - Retention: 15 дней

5. **grafana** - Визуализация метрик
   - Порт: 3000
   - Credentials: admin/admin (изменить при первом входе)
   - Datasources: Prometheus, Loki

6. **alertmanager** - Управление алертами
   - Порт: 9093
   - Интеграция с Prometheus

### Логирование

7. **loki** - Агрегация логов
   - Порт: 3100
   - Retention: 30 дней

8. **promtail** - Сбор логов
   - Читает логи из Docker containers
   - Отправляет в Loki

### Reverse Proxy

9. **nginx** - Reverse proxy и load balancer
   - Порт: 80, 443
   - TLS termination
   - Rate limiting
   - Security headers

## Конфигурация

### Environment Variables

Создайте файл `docker/.env`:

```bash
# Application
APP_ENV=production
LOG_LEVEL=info

# Database
POSTGRES_HOST=postgres
POSTGRES_PORT=5432
POSTGRES_DB=aq_security
POSTGRES_USER=aq_user
POSTGRES_PASSWORD=<strong-password>

# Redis
REDIS_HOST=redis
REDIS_PORT=6379
REDIS_PASSWORD=<strong-password>

# Security
JWT_SECRET=<random-256-bit-hex>
ENCRYPTION_KEY=<random-256-bit-hex>

# Monitoring
GRAFANA_ADMIN_PASSWORD=<strong-password>
ALERTMANAGER_SLACK_WEBHOOK=<slack-webhook-url>
```

### Генерация секретов

```bash
# JWT Secret (256 bit)
openssl rand -hex 32

# Encryption Key (256 bit)
openssl rand -hex 32

# Strong password
openssl rand -base64 32
```

## Управление

### Запуск

```bash
# Запустить все сервисы
docker-compose up -d

# Запустить конкретный сервис
docker-compose up -d app

# Пересобрать и запустить
docker-compose up -d --build
```

### Остановка

```bash
# Остановить все сервисы
docker-compose down

# Остановить и удалить volumes
docker-compose down -v

# Остановить конкретный сервис
docker-compose stop app
```

### Логи

```bash
# Все логи
docker-compose logs -f

# Логи конкретного сервиса
docker-compose logs -f app

# Последние 100 строк
docker-compose logs --tail=100 app
```

### Масштабирование

```bash
# Запустить 3 инстанса приложения
docker-compose up -d --scale app=3

# Nginx автоматически распределит нагрузку
```

## Мониторинг

### Prometheus

Доступ: http://localhost:9090

Основные метрики:
- `http_requests_total` - Общее количество запросов
- `http_request_duration_seconds` - Длительность запросов
- `rate_limit_blocked_total` - Заблокированные запросы
- `dos_connections_active` - Активные соединения

### Grafana

Доступ: http://localhost:3000
Credentials: admin/admin

Предустановленные дашборды:
- AQ Security Overview
- Rate Limiting
- DoS Protection
- Application Performance

### Loki

Доступ через Grafana: Explore → Loki

Примеры запросов:
```logql
# Все логи приложения
{container_name="aq-security-app-1"}

# Только ошибки
{container_name="aq-security-app-1"} |= "level=error"

# Rate limit события
{container_name="aq-security-app-1"} |= "rate_limit"
```

## Backup и Recovery

### Database Backup

```bash
# Создать backup
docker-compose exec postgres pg_dump -U aq_user aq_security > backup.sql

# Восстановить из backup
docker-compose exec -T postgres psql -U aq_user aq_security < backup.sql
```

### Автоматический backup

Добавьте в crontab:

```bash
# Ежедневный backup в 2:00
0 2 * * * cd /path/to/docker && docker-compose exec -T postgres pg_dump -U aq_user aq_security | gzip > backups/backup-$(date +\%Y\%m\%d).sql.gz
```

### Redis Backup

```bash
# Создать snapshot
docker-compose exec redis redis-cli SAVE

# Копировать dump
docker cp aq-security-redis-1:/data/dump.rdb ./redis-backup.rdb
```

## Health Checks

### Application Health

```bash
curl http://localhost:8080/api/health
```

Ожидаемый ответ:
```json
{
  "status": "healthy",
  "timestamp": "2026-04-10T18:55:00Z",
  "checks": {
    "database": "ok",
    "redis": "ok"
  }
}
```

### Service Status

```bash
# Проверить все сервисы
docker-compose ps

# Проверить конкретный сервис
docker-compose ps app
```

## Troubleshooting

### Приложение не запускается

```bash
# Проверить логи
docker-compose logs app

# Проверить зависимости
docker-compose ps postgres redis

# Пересоздать контейнер
docker-compose up -d --force-recreate app
```

### Database connection failed

```bash
# Проверить PostgreSQL
docker-compose exec postgres psql -U aq_user -d aq_security -c "SELECT 1"

# Проверить сеть
docker-compose exec app ping postgres
```

### Redis connection failed

```bash
# Проверить Redis
docker-compose exec redis redis-cli ping

# Проверить пароль
docker-compose exec redis redis-cli -a <password> ping
```

### High memory usage

```bash
# Проверить использование ресурсов
docker stats

# Ограничить память для сервиса (в docker-compose.yml)
services:
  app:
    deploy:
      resources:
        limits:
          memory: 512M
```

## Security Best Practices

1. **Изменить дефолтные пароли**
   - Grafana admin password
   - PostgreSQL password
   - Redis password

2. **Использовать secrets management**
   - Docker secrets
   - HashiCorp Vault
   - AWS Secrets Manager

3. **Ограничить доступ к портам**
   - Expose только необходимые порты
   - Использовать firewall rules

4. **Регулярные обновления**
   ```bash
   # Обновить образы
   docker-compose pull
   docker-compose up -d
   ```

5. **Мониторинг безопасности**
   - Проверять логи на подозрительную активность
   - Настроить алерты в Alertmanager

## Production Checklist

- [ ] Изменены все дефолтные пароли
- [ ] Настроены environment variables
- [ ] Настроен автоматический backup
- [ ] Настроены алерты в Alertmanager
- [ ] Настроен TLS для Nginx
- [ ] Ограничен доступ к Prometheus/Grafana
- [ ] Настроен log rotation
- [ ] Проверены health checks
- [ ] Проведено load testing
- [ ] Настроен мониторинг

## Дополнительные ресурсы

- [Docker Compose Documentation](https://docs.docker.com/compose/)
- [Prometheus Documentation](https://prometheus.io/docs/)
- [Grafana Documentation](https://grafana.com/docs/)
- [Loki Documentation](https://grafana.com/docs/loki/)
