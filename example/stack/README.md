# AQ Security Stack

Docker Compose стек для запуска полного auth-сервера с изолированным data layer.

## Архитектура

```
┌─────────────────────────────────────────────────────────────┐
│                     Docker Network                          │
│                                                             │
│  ┌──────────────┐    ┌──────────────┐    ┌──────────────┐ │
│  │  PostgreSQL  │◄───│  Server Data │◄───│  Server Auth │ │
│  │   :5432      │    │   :8090      │    │   :8080      │ │
│  └──────────────┘    └──────────────┘    └──────────────┘ │
│                                                ▲            │
│  ┌──────────────┐                             │            │
│  │    Redis     │─────────────────────────────┘            │
│  │   :6379      │                                          │
│  └──────────────┘                                          │
│                                                             │
└─────────────────────────────────────────────────────────────┘
                           ▲
                           │
                    Clients connect here
                    (Console, Flutter, etc.)
```

## Компоненты

### 1. PostgreSQL (postgres:15-alpine)
- **Порт**: 5432
- **Назначение**: Хранение всех security данных
- **Схема**: `security`
- **Коллекции**: users, sessions, roles, permissions, etc.

### 2. Redis (redis:7-alpine)
- **Порт**: 6379
- **Назначение**: Rate limiting, token blacklist, caching
- **Конфигурация**: `redis/redis.conf`

### 3. Server Data (Vault Server)
- **Порт**: 8090
- **Назначение**: Изолированный data layer для auth данных
- **Защита**: Доступен только внутри Docker network
- **Репозитории**: DirectRepository, LoggedRepository

### 4. Server Auth (Auth Service)
- **Порт**: 8080
- **Назначение**: Полноценный auth-сервер
- **Провайдеры**: Google OAuth, Email/Password, API Keys
- **Endpoints**: `/auth/*`, `/rbac/*`, `/api/introspect`

## Быстрый старт

### 1. Подготовка

```bash
# Скопировать .env.example в .env
cp .env.example .env

# Отредактировать .env (ОБЯЗАТЕЛЬНО изменить секреты!)
nano .env
```

**Минимальные требования в .env**:
- `POSTGRES_PASSWORD` — пароль для PostgreSQL
- `AUTH_JWT_SECRET` — JWT секрет (минимум 32 символа)

### 2. Запуск

```bash
# Запустить весь стек
docker-compose up -d

# Проверить статус
docker-compose ps

# Проверить логи
docker-compose logs -f
```

### 3. Проверка

```bash
# Health checks
curl http://localhost:8090/health  # Data Layer
curl http://localhost:8080/health  # Auth Service

# PostgreSQL
docker-compose exec postgres psql -U aq_security_user -d aq_security -c "\dt security.*"

# Redis
docker-compose exec redis redis-cli ping
```

## Endpoints

### Auth Service (http://localhost:8080)

**Authentication**:
- `POST /auth/login` — Email/Password login
- `POST /auth/register` — Регистрация
- `GET /auth/google` — Google OAuth redirect
- `GET /auth/google/callback` — Google OAuth callback
- `POST /auth/refresh` — Refresh tokens
- `POST /auth/logout` — Logout

**RBAC**:
- `GET /rbac/roles` — Список ролей
- `POST /rbac/roles` — Создать роль
- `GET /rbac/permissions` — Проверить права

**Introspection**:
- `POST /api/introspect` — Проверить токен (для resource servers)

### Data Layer (http://localhost:8090)

**Внимание**: Доступен только внутри Docker network!

- `GET /health` — Health check
- Vault API endpoints (автоматически)

## Тестовые данные

В режиме `ENV=development` автоматически создаются:

**Tenant**:
- Slug: `test-company`

**Users**:
- `admin@test.com` / `admin123` (роль: Admin)
- `developer@test.com` / `dev123` (роль: Developer)
- `viewer@test.com` / `view123` (роль: Viewer)

**API Key**:
- `aq_test_1234567890abcdef`

## Управление

### Остановка

```bash
# Остановить все сервисы
docker-compose down

# Остановить и удалить volumes (УДАЛИТ ВСЕ ДАННЫЕ!)
docker-compose down -v
```

### Перезапуск

```bash
# Перезапустить все сервисы
docker-compose restart

# Перезапустить конкретный сервис
docker-compose restart server_auth
```

### Логи

```bash
# Все логи
docker-compose logs -f

# Логи конкретного сервиса
docker-compose logs -f server_auth

# Последние 100 строк
docker-compose logs --tail=100 server_auth
```

### Обновление

```bash
# Пересобрать образы
docker-compose build

# Пересобрать без кэша
docker-compose build --no-cache

# Пересобрать и перезапустить
docker-compose up -d --build
```

## Troubleshooting

### Проблема: Auth service не стартует

**Симптомы**: `server_auth` в статусе `unhealthy` или `restarting`

**Решение**:
```bash
# Проверить логи
docker-compose logs server_auth

# Проверить подключение к data layer
docker-compose exec server_auth curl http://server_data:8090/health

# Проверить переменные окружения
docker-compose exec server_auth env | grep AUTH
```

### Проблема: PostgreSQL не доступен

**Симптомы**: `server_data` не может подключиться к БД

**Решение**:
```bash
# Проверить статус PostgreSQL
docker-compose ps postgres

# Проверить логи
docker-compose logs postgres

# Проверить подключение
docker-compose exec postgres pg_isready -U aq_security_user
```

### Проблема: Redis не доступен

**Симптомы**: Rate limiting не работает

**Решение**:
```bash
# Проверить статус Redis
docker-compose ps redis

# Проверить подключение
docker-compose exec redis redis-cli ping

# Проверить конфигурацию
docker-compose exec redis redis-cli CONFIG GET maxmemory
```

### Проблема: Порты заняты

**Симптомы**: `Error: port is already allocated`

**Решение**:
```bash
# Найти процесс, занимающий порт
lsof -i :8080
lsof -i :8090
lsof -i :5432
lsof -i :6379

# Изменить порты в .env
# Например: AUTH_SERVICE_PORT=8081
```

## Production Deployment

### Важные изменения для production:

1. **Секреты**:
   - Использовать сильные пароли (минимум 32 символа)
   - Хранить в secure vault (AWS Secrets Manager, HashiCorp Vault)
   - Ротировать регулярно

2. **Сеть**:
   - Закрыть порты PostgreSQL и Redis (убрать из `ports:`)
   - Оставить только Auth Service доступным извне
   - Использовать reverse proxy (nginx, traefik)

3. **Volumes**:
   - Использовать named volumes с backup
   - Настроить автоматический backup PostgreSQL

4. **Мониторинг**:
   - Добавить Prometheus metrics
   - Настроить алерты
   - Логирование в centralized system

5. **SSL/TLS**:
   - Использовать HTTPS для Auth Service
   - Настроить SSL для PostgreSQL

## Дополнительная информация

- **Документация**: См. `../docs/`
- **Примеры клиентов**: См. `../client_*/`
- **Исходники серверов**: См. `../server_*/`

## Лицензия

См. корневой README пакета `aq_security`.
