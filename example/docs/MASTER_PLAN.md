# Production-Ready Examples — Master Plan

**Дата создания**: 2026-04-22  
**Статус**: Планирование  
**Цель**: Создать production-ready примеры использования `aq_security`

---

## Обзор

Создаём полный стек примеров, демонстрирующих:
- Как поднять auth-сервер с изолированным data layer
- Как подключиться как consumer (console + Flutter)
- Как защитить свой ресурс (resource server)
- Все auth провайдеры (Google OAuth, Email/Password, API Keys)
- RBAC в действии
- Token lifecycle

---

## Структура примеров

```
example/
├── docs/                           # 📚 Документация (этот файл)
│   ├── MASTER_PLAN.md              # Общий план
│   ├── STACK_PLAN.md               # Docker stack
│   ├── SERVER_AUTH_PLAN.md         # Auth service
│   ├── SERVER_DATA_PLAN.md         # Data layer
│   ├── CLIENT_CONSOLE_PLAN.md      # Console client
│   ├── CLIENT_FLUTTER_PLAN.md      # Flutter client
│   └── CLIENT_RESOURCE_PLAN.md     # Resource server
│
├── stack/                          # 🐳 Docker Compose
├── server_auth/                    # 🔐 Auth Service
├── server_data/                    # 💾 Data Layer
├── client_console/                 # 🖥️  Console Client
├── client_flutter/                 # 📱 Flutter Client
└── client_resource_server/         # 🛡️  Resource Server
```

---

## Фазы реализации

### Фаза 0: Подготовка (1 час) ✅ ЗАВЕРШЕНО
- ✅ Создать структуру папок
- ✅ Создать документацию для каждого компонента
- ✅ Определить зависимости между компонентами
- ✅ Создать общий `.env.example`

### Фаза 1: Docker Stack (2 часа)
- Создать `docker-compose.yml`
- Настроить сети и volumes
- Создать PostgreSQL конфигурацию
- Создать Redis конфигурацию (для rate limiting)
- Документация по запуску

### Фаза 2: Server Data Layer (3 часа)
- Создать Vault server приложение
- Настроить PostgreSQL подключение
- Зарегистрировать security domains
- Создать Dockerfile
- Тесты подключения

### Фаза 3: Server Auth (4 часа)
- Создать auth-сервер приложение
- Настроить все провайдеры (Google, Email, API Keys)
- Подключить к data layer
- Настроить RBAC
- Создать Dockerfile
- Seed данные (тестовые пользователи, роли)

### Фаза 4: Client Console (3 часа)
- Создать консольное приложение
- Реализовать тесты всех auth flow
- Цветной вывод результатов
- Документация по запуску

### Фаза 5: Client Flutter (6 часов)
- Создать Flutter приложение
- UI для всех провайдеров
- Riverpod state management
- Навигация между экранами
- Документация

### Фаза 6: Client Resource Server (4 часа)
- Создать защищённый data layer
- Auth middleware
- RBAC проверки
- Audit logging
- Документация

### Фаза 7: Интеграция и тестирование (3 часа)
- Запустить весь стек
- Проверить все flow
- Исправить баги
- Финальная документация

---

## Оценка времени

| Фаза | Компонент | Часы | Приоритет |
|------|-----------|------|-----------|
| 0 | Подготовка | 1 | Высокий |
| 1 | Docker Stack | 2 | Высокий |
| 2 | Server Data | 3 | Высокий |
| 3 | Server Auth | 4 | Высокий |
| 4 | Client Console | 3 | Средний |
| 5 | Client Flutter | 6 | Средний |
| 6 | Client Resource | 4 | Низкий |
| 7 | Интеграция | 3 | Высокий |
| **Итого** | | **26 часов** | |

---

## Зависимости

```
Фаза 0 (Подготовка)
  ↓
Фаза 1 (Docker Stack) ← Фаза 2 (Server Data) ← Фаза 3 (Server Auth)
  ↓                                                    ↓
Фаза 4 (Console) ←──────────────────────────────────┘
  ↓
Фаза 5 (Flutter)
  ↓
Фаза 6 (Resource Server)
  ↓
Фаза 7 (Интеграция)
```

**Критический путь**: Фаза 0 → 1 → 2 → 3 → 7

---

## Технологический стек

### Backend
- **Dart**: 3.x
- **aq_security**: текущая версия
- **dart_vault_package**: текущая версия
- **shelf**: HTTP сервер
- **PostgreSQL**: 15+
- **Redis**: 7+ (для rate limiting)

### Frontend
- **Flutter**: 3.x
- **Riverpod**: State management
- **go_router**: Навигация
- **http**: HTTP клиент

### Infrastructure
- **Docker**: 24+
- **Docker Compose**: 2.x

---

## Переменные окружения

### Auth Service
```bash
AUTH_SERVICE_PORT=8080
AUTH_DATA_SERVICE_URL=http://server_data:8090
AUTH_JWT_SECRET=your_jwt_secret_here
GOOGLE_CLIENT_ID=...
GOOGLE_CLIENT_SECRET=...
GOOGLE_REDIRECT_URI=http://localhost:8080/auth/google/callback
REDIS_URL=redis://redis:6379
```

### Data Layer
```bash
DATA_SERVICE_PORT=8090
POSTGRES_HOST=postgres
POSTGRES_PORT=5432
POSTGRES_DB=aq_security
POSTGRES_USER=aq_security_user
POSTGRES_PASSWORD=secure_password
```

### Clients
```bash
AUTH_SERVICE_URL=http://localhost:8080
```

---

## Критерии успеха

### Функциональные
- ✅ Все auth провайдеры работают
- ✅ RBAC проверки работают
- ✅ Token lifecycle работает
- ✅ Resource server защищён
- ✅ Console client проходит все тесты
- ✅ Flutter client работает на iOS/Android/Web

### Нефункциональные
- ✅ Документация полная и понятная
- ✅ Примеры можно копировать и использовать
- ✅ Docker stack запускается одной командой
- ✅ Код чистый и читаемый
- ✅ Нет хардкода секретов

---

## Риски

### Риск 1: OAuth провайдеры требуют реальные credentials
**Вероятность**: Высокая  
**Влияние**: Среднее  
**Митигация**: 
- Документировать как получить credentials
- Предоставить mock режим для тестирования без OAuth

### Риск 2: Docker stack сложен для новичков
**Вероятность**: Средняя  
**Влияние**: Среднее  
**Митигация**:
- Подробная документация
- Скрипты для автоматизации
- Troubleshooting секция

### Риск 3: Flutter пример требует много времени
**Вероятность**: Высокая  
**Влияние**: Низкое  
**Митигация**:
- Минимальный UI
- Фокус на функциональности, не на дизайне

---

## Следующие шаги

1. ✅ Создать структуру документации
2. ⏳ Создать детальные планы для каждого компонента
3. ⏳ Начать с Фазы 0 (подготовка)
4. ⏳ Реализовать критический путь (Stack → Data → Auth)
5. ⏳ Добавить клиентские приложения
6. ⏳ Интеграционное тестирование

---

## Контакты

**Ответственный**: Security Layer Team  
**Дата создания**: 2026-04-22  
**Последнее обновление**: 2026-04-22
