# AQ Security Data Layer

Изолированный Vault server для хранения auth данных.

## Назначение

Этот сервер предоставляет изолированный data layer для auth service. Он хранит все security данные (users, sessions, roles, permissions) и доступен только auth service через Docker network.

## Архитектура безопасности

### Изоляция

```
┌─────────────────────────────────────────┐
│         Docker Network (internal)       │
│                                         │
│  ┌──────────────┐    ┌──────────────┐  │
│  │  PostgreSQL  │◄───│  Data Layer  │  │
│  └──────────────┘    └──────────────┘  │
│                             ▲           │
│                             │           │
│                      ┌──────────────┐   │
│                      │ Auth Service │   │
│                      └──────────────┘   │
│                             ▲           │
└─────────────────────────────┼───────────┘
                              │
                         Public access
```

### Принципы безопасности

1. **Сетевая изоляция**: Доступен только внутри Docker network
2. **Без аутентификации**: Auth service — доверенный клиент
3. **Без авторизации**: Все запросы от auth service разрешены
4. **Audit logging**: Все запросы логируются

## Зарегистрированные домены

### DirectStorable (простые CRUD)
- `security_users` — пользователи
- `security_tenants` — тенанты
- `security_profiles` — профили пользователей
- `security_roles` — роли
- `security_user_roles` — назначения ролей
- `rbac_policies` — политики доступа

### LoggedStorable (с audit trail)
- `security_sessions` — сессии (с логом изменений статуса)
- `security_api_keys` — API ключи (с логом активации/деактивации)
- `rbac_access_logs` — логи доступа
- `rbac_audit_trail` — audit trail

## Запуск локально

### Требования

- Dart SDK 3.3+
- PostgreSQL 15+
- Переменные окружения

### Установка зависимостей

```bash
dart pub get
```

### Настройка переменных окружения

```bash
export DATA_SERVICE_PORT=8090
export POSTGRES_HOST=localhost
export POSTGRES_PORT=5432
export POSTGRES_DB=aq_security
export POSTGRES_USER=aq_security_user
export POSTGRES_PASSWORD=secure_password
```

### Запуск

```bash
dart run bin/main.dart
```

## Запуск в Docker

### Сборка образа

```bash
docker build -t aq_security_data .
```

### Запуск контейнера

```bash
docker run -p 8090:8090 \
  -e POSTGRES_HOST=postgres \
  -e POSTGRES_PORT=5432 \
  -e POSTGRES_DB=aq_security \
  -e POSTGRES_USER=aq_security_user \
  -e POSTGRES_PASSWORD=secure_password \
  aq_security_data
```

## Endpoints

### Health Check

```bash
GET /health
```

Возвращает `OK` если сервер работает.

### Info

```bash
GET /info
```

Возвращает информацию о зарегистрированных коллекциях.

### Vault API

Автоматически предоставляется `dart_vault`:

- `POST /api/collections/{collection}/save` — сохранить запись
- `GET /api/collections/{collection}/find/{id}` — найти по ID
- `POST /api/collections/{collection}/query` — запрос с фильтрами
- `DELETE /api/collections/{collection}/delete/{id}` — удалить
- `GET /api/collections/{collection}/history/{id}` — история (для LoggedStorable)

## Примеры использования

### Сохранить пользователя

```bash
curl -X POST http://localhost:8090/api/collections/security_users/save \
  -H "Content-Type: application/json" \
  -d '{
    "id": "user_123",
    "email": "test@example.com",
    "tenantId": "tenant_1",
    "authProvider": "email",
    "userType": "regular",
    "isActive": true
  }'
```

### Найти пользователя

```bash
curl http://localhost:8090/api/collections/security_users/find/user_123
```

### Запрос с фильтром

```bash
curl -X POST http://localhost:8090/api/collections/security_users/query \
  -H "Content-Type: application/json" \
  -d '{
    "filters": {
      "tenantId": "tenant_1",
      "isActive": true
    }
  }'
```

## Мониторинг

### Логи

Все запросы логируются в stdout:

```
2026-04-22T14:45:00.000Z INFO GET /health 200 2ms
2026-04-22T14:45:01.000Z INFO POST /api/collections/security_users/save 200 15ms
```

### Health Check

```bash
curl http://localhost:8090/health
```

Должен вернуть `OK` и статус 200.

## Troubleshooting

### Проблема: Не может подключиться к PostgreSQL

**Симптомы**: `Failed to connect to PostgreSQL`

**Решение**:
1. Проверить, что PostgreSQL запущен
2. Проверить переменные окружения
3. Проверить сетевую доступность

```bash
# Проверить подключение
psql -h localhost -U aq_security_user -d aq_security
```

### Проблема: Коллекция не найдена

**Симптомы**: `Collection not registered`

**Решение**:
Проверить, что коллекция зарегистрирована в `vault_registry.dart`.

### Проблема: Порт занят

**Симптомы**: `Address already in use`

**Решение**:
```bash
# Найти процесс
lsof -i :8090

# Изменить порт
export DATA_SERVICE_PORT=8091
```

## Production Deployment

### Важные изменения

1. **Сетевая изоляция**:
   - Убрать `ports:` из docker-compose (не публиковать наружу)
   - Доступ только через internal network

2. **Мониторинг**:
   - Добавить Prometheus metrics
   - Настроить алерты на ошибки подключения

3. **Backup**:
   - Настроить автоматический backup PostgreSQL
   - Тестировать restore регулярно

4. **Логирование**:
   - Отправлять логи в centralized system
   - Настроить retention policy

## Связанные компоненты

- **Auth Service**: `../server_auth/` — использует этот data layer
- **Docker Stack**: `../stack/` — оркестрация всех сервисов
- **Схемы данных**: `../../aq_schema/` — модели и storable

## Лицензия

См. корневой README пакета `aq_security`.
