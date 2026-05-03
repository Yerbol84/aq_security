# Docker Stack — Детальный план

**Компонент**: Docker Compose Stack  
**Приоритет**: Высокий  
**Оценка**: 2 часа  
**Статус**: Планирование

---

## Цель

Создать Docker Compose конфигурацию для запуска всего стека одной командой:
- Auth Service
- Data Layer (Vault server)
- PostgreSQL
- Redis

---

## Структура

```
stack/
├── docker-compose.yml          # Главная конфигурация
├── .env.example                # Шаблон переменных окружения
├── postgres/
│   ├── init.sql                # Инициализация БД
│   └── Dockerfile              # Кастомный образ (если нужно)
├── redis/
│   └── redis.conf              # Конфигурация Redis
└── README.md                   # Инструкции по запуску
```

---

## docker-compose.yml

### Сервисы

#### 1. PostgreSQL
```yaml
postgres:
  image: postgres:15-alpine
  container_name: aq_security_postgres
  environment:
    POSTGRES_DB: aq_security
    POSTGRES_USER: aq_security_user
    POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
  volumes:
    - postgres_data:/var/lib/postgresql/data
    - ./postgres/init.sql:/docker-entrypoint-initdb.d/init.sql
  ports:
    - "5432:5432"  # Для отладки, в production закрыть
  networks:
    - aq_security_network
  healthcheck:
    test: ["CMD-SHELL", "pg_isready -U aq_security_user"]
    interval: 10s
    timeout: 5s
    retries: 5
```

#### 2. Redis
```yaml
redis:
  image: redis:7-alpine
  container_name: aq_security_redis
  command: redis-server /usr/local/etc/redis/redis.conf
  volumes:
    - redis_data:/data
    - ./redis/redis.conf:/usr/local/etc/redis/redis.conf
  ports:
    - "6379:6379"  # Для отладки
  networks:
    - aq_security_network
  healthcheck:
    test: ["CMD", "redis-cli", "ping"]
    interval: 10s
    timeout: 5s
    retries: 5
```

#### 3. Data Layer (Vault Server)
```yaml
server_data:
  build:
    context: ../server_data
    dockerfile: Dockerfile
  container_name: aq_security_data
  environment:
    DATA_SERVICE_PORT: 8090
    POSTGRES_HOST: postgres
    POSTGRES_PORT: 5432
    POSTGRES_DB: aq_security
    POSTGRES_USER: aq_security_user
    POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
  ports:
    - "8090:8090"  # Для отладки, в production только internal
  networks:
    - aq_security_network
  depends_on:
    postgres:
      condition: service_healthy
  healthcheck:
    test: ["CMD", "curl", "-f", "http://localhost:8090/health"]
    interval: 10s
    timeout: 5s
    retries: 5
```

#### 4. Auth Service
```yaml
server_auth:
  build:
    context: ../server_auth
    dockerfile: Dockerfile
  container_name: aq_security_auth
  environment:
    AUTH_SERVICE_PORT: 8080
    AUTH_DATA_SERVICE_URL: http://server_data:8090
    AUTH_JWT_SECRET: ${AUTH_JWT_SECRET}
    GOOGLE_CLIENT_ID: ${GOOGLE_CLIENT_ID}
    GOOGLE_CLIENT_SECRET: ${GOOGLE_CLIENT_SECRET}
    GOOGLE_REDIRECT_URI: ${GOOGLE_REDIRECT_URI}
    REDIS_URL: redis://redis:6379
    ALLOWED_ORIGINS: ${ALLOWED_ORIGINS}
  ports:
    - "8080:8080"
  networks:
    - aq_security_network
  depends_on:
    server_data:
      condition: service_healthy
    redis:
      condition: service_healthy
  healthcheck:
    test: ["CMD", "curl", "-f", "http://localhost:8080/health"]
    interval: 10s
    timeout: 5s
    retries: 5
```

### Networks
```yaml
networks:
  aq_security_network:
    driver: bridge
```

### Volumes
```yaml
volumes:
  postgres_data:
  redis_data:
```

---

## .env.example

```bash
# PostgreSQL
POSTGRES_PASSWORD=secure_password_change_me

# Auth Service
AUTH_JWT_SECRET=your_jwt_secret_min_32_chars_change_me
GOOGLE_CLIENT_ID=your_google_client_id
GOOGLE_CLIENT_SECRET=your_google_client_secret
GOOGLE_REDIRECT_URI=http://localhost:8080/auth/google/callback
ALLOWED_ORIGINS=http://localhost:3000,http://localhost:8081

# GitHub OAuth (optional)
GITHUB_CLIENT_ID=your_github_client_id
GITHUB_CLIENT_SECRET=your_github_client_secret
GITHUB_REDIRECT_URI=http://localhost:8080/auth/github/callback
```

---

## postgres/init.sql

```sql
-- Инициализация БД для aq_security

-- Создание расширений
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Создание схемы
CREATE SCHEMA IF NOT EXISTS security;

-- Комментарий
COMMENT ON SCHEMA security IS 'AQ Security data layer schema';

-- Таблицы создаются автоматически через dart_vault migrations
```

---

## redis/redis.conf

```conf
# Redis конфигурация для aq_security

# Persistence
save 900 1
save 300 10
save 60 10000

# Memory
maxmemory 256mb
maxmemory-policy allkeys-lru

# Security
requirepass change_me_in_production

# Logging
loglevel notice
```

---

## README.md

```markdown
# AQ Security Stack

Docker Compose стек для запуска полного auth-сервера.

## Быстрый старт

1. Скопировать `.env.example` в `.env`:
   ```bash
   cp .env.example .env
   ```

2. Отредактировать `.env` (заменить секреты)

3. Запустить стек:
   ```bash
   docker-compose up -d
   ```

4. Проверить статус:
   ```bash
   docker-compose ps
   ```

5. Проверить логи:
   ```bash
   docker-compose logs -f server_auth
   ```

## Endpoints

- Auth Service: http://localhost:8080
- Data Layer: http://localhost:8090 (только для отладки)
- PostgreSQL: localhost:5432
- Redis: localhost:6379

## Остановка

```bash
docker-compose down
```

## Очистка данных

```bash
docker-compose down -v
```

## Troubleshooting

### Проблема: Auth service не стартует
- Проверить логи: `docker-compose logs server_auth`
- Проверить подключение к data layer: `docker-compose exec server_auth curl http://server_data:8090/health`

### Проблема: PostgreSQL не доступен
- Проверить healthcheck: `docker-compose ps postgres`
- Проверить логи: `docker-compose logs postgres`
```

---

## Задачи реализации

### Задача 1.1: Создать docker-compose.yml
**Оценка**: 30 минут
- Определить все сервисы
- Настроить networks
- Настроить volumes
- Добавить healthchecks
- Настроить depends_on

### Задача 1.2: Создать .env.example
**Оценка**: 15 минут
- Все переменные окружения
- Комментарии для каждой переменной
- Безопасные дефолты

### Задача 1.3: Создать postgres/init.sql
**Оценка**: 15 минут
- Создание схемы
- Расширения
- Комментарии

### Задача 1.4: Создать redis/redis.conf
**Оценка**: 15 минут
- Persistence настройки
- Memory limits
- Security

### Задача 1.5: Создать README.md
**Оценка**: 30 минут
- Инструкции по запуску
- Troubleshooting
- Примеры команд

### Задача 1.6: Тестирование
**Оценка**: 15 минут
- Запустить стек
- Проверить все healthchecks
- Проверить connectivity между сервисами

---

## Acceptance Criteria

- ✅ `docker-compose up -d` запускает все сервисы
- ✅ Все healthchecks проходят
- ✅ Auth service доступен на :8080
- ✅ Data layer доступен на :8090
- ✅ PostgreSQL доступен на :5432
- ✅ Redis доступен на :6379
- ✅ Логи не содержат ошибок
- ✅ README содержит все инструкции

---

## Зависимости

**Блокирует**:
- Server Data реализацию
- Server Auth реализацию
- Client приложения

**Зависит от**:
- Ничего (можно начинать сразу)

---

## Статус

- [ ] Задача 1.1: docker-compose.yml
- [ ] Задача 1.2: .env.example
- [ ] Задача 1.3: postgres/init.sql
- [ ] Задача 1.4: redis/redis.conf
- [ ] Задача 1.5: README.md
- [ ] Задача 1.6: Тестирование
