# Анализ дублирования: i_security_service.dart vs aq_security_service.dart

## Обзор

**Файл 1**: `aq_schema/lib/security/interfaces/i_security_service.dart` (544 строки)
**Файл 2**: `aq_security/lib/src/client/aq_security_service.dart` (289 строк)

## Ключевые различия

### 1. Назначение файлов

**i_security_service.dart (aq_schema)**:
- **Роль**: Интерфейс (контракт) для всей системы безопасности
- **Содержит**: 
  - Абстрактный интерфейс `ISecurityService` (abstract interface class)
  - Определения состояний `SecurityState` (sealed class)
  - Модель `AuthResponse`
  - Singleton pattern с `setSecurityServiceInstance()`
  - Подсервисы: `IRoleManagementService`, `IPolicyService`, `IAuditService`
- **Зависимости**: Только модели из `aq_schema`
- **Используется**: UI пакетами через `ISecurityService.instance`

**aq_security_service.dart (aq_security)**:
- **Роль**: Конкретная реализация клиентской части
- **Содержит**:
  - Конкретный класс `AQSecurityService` (final class)
  - Дублирует определения `SecurityState` (!)
  - Реализует только базовые auth методы
  - НЕ реализует `ISecurityService` интерфейс (!)
- **Зависимости**: `HttpAuthTransport`, `LocalSessionStore`, `TokenValidator`
- **Используется**: Через `AQSecurityClient.init()`

### 2. Дублирование кода

#### SecurityState (100% дублирование)

**Обе файлы содержат идентичный код:**
```dart
sealed class SecurityState { const SecurityState(); }
final class SecurityStateUnauthenticated extends SecurityState { ... }
final class SecurityStateAuthenticated extends SecurityState { ... }
final class SecurityStateLoading extends SecurityState { ... }
final class SecurityStateError extends SecurityState { ... }
```

**Проблема**: Нарушение DRY принципа. Изменения нужно делать в двух местах.

### 3. API различия

#### Методы в интерфейсе (i_security_service.dart), но НЕ в реализации:

**Auth методы:**
- ❌ `register()` — регистрация нового пользователя
- ❌ `refreshTokens()` — публичный метод обновления токенов
- ❌ `getActiveSessions()` — список активных сессий
- ❌ `revokeAllOtherSessions()` — отзыв всех сессий кроме текущей

**Permission checks:**
- ❌ `hasPermission()` — проверка одного права
- ❌ `hasRole()` — проверка роли
- ❌ `hasPermissions()` — проверка нескольких прав
- ❌ `hasRoles()` — проверка нескольких ролей
- ❌ `getResourcePermissions()` — получить права на ресурс (большой метод с документацией)

**API Keys:**
- ❌ `getApiKeys()` — список API ключей
- ❌ `createApiKey()` — создание ключа
- ❌ `rotateApiKey()` — ротация ключа
- ❌ `revokeApiKey()` — отзыв ключа

**Profile management:**
- ❌ `updateProfile()` — обновление профиля
- ❌ `changePassword()` — смена пароля
- ❌ `requestPasswordReset()` — запрос сброса пароля
- ❌ `resetPassword()` — сброс пароля с кодом

**Email verification:**
- ❌ `sendVerificationCode()` — отправка кода
- ❌ `verifyEmail()` — верификация email

**Tenant management:**
- ❌ `getAvailableTenants()` — список тенантов
- ❌ `switchTenant()` — переключение тенанта

**Подсервисы:**
- ❌ `roleManagement` — IRoleManagementService
- ❌ `policies` — IPolicyService
- ❌ `audit` — IAuditService

#### Методы в реализации, но НЕ в интерфейсе:

- ✅ `listSessions()` — есть в реализации (но в интерфейсе `getActiveSessions()`)
- ✅ `validateToken()` — есть в реализации (в интерфейсе тоже есть, но другая сигнатура)

### 4. Архитектурные проблемы

#### Проблема 1: AQSecurityService НЕ реализует ISecurityService

```dart
// Должно быть:
final class AQSecurityService implements ISecurityService { ... }

// Сейчас:
final class AQSecurityService { ... }
```

**Последствия:**
- Нарушение контракта
- UI пакеты не могут использовать `ISecurityService.instance`
- Невозможно подменить реализацию для тестов

#### Проблема 2: Дублирование SecurityState

**Текущая ситуация:**
- `SecurityState` определён в `aq_schema` (интерфейс)
- `SecurityState` определён в `aq_security` (реализация)
- Это разные типы! Несовместимы между собой

**Правильно:**
- `SecurityState` должен быть только в `aq_schema`
- `aq_security` должен импортировать и использовать его

#### Проблема 3: Неполная реализация

`AQSecurityService` реализует только ~20% методов из `ISecurityService`:
- Есть: login, logout, restore, validate
- Нет: permissions, roles, API keys, profile, email verification, tenants, подсервисы

### 5. Зависимости

**i_security_service.dart:**
```dart
import '../models/aq_user.dart';
import '../models/aq_tenant.dart';
import '../models/aq_session.dart';
import '../models/aq_token_claims.dart';
import '../models/aq_api_key.dart';
import '../models/credentials.dart';
import 'i_role_management_service.dart';
import 'i_policy_service.dart';
import 'i_audit_service.dart';
```

**aq_security_service.dart:**
```dart
import 'package:aq_schema/security/security.dart';
import 'http_auth_transport.dart';
import 'local_session_store.dart';
```

## Рекомендации по объединению

### Вариант 1: Полная реализация интерфейса (рекомендуется)

**Шаги:**
1. Удалить дублирование `SecurityState` из `aq_security_service.dart`
2. Импортировать `SecurityState` из `aq_schema`
3. Добавить `implements ISecurityService` к `AQSecurityService`
4. Реализовать все недостающие методы (или выбросить `UnimplementedError`)
5. Зарегистрировать через `setSecurityServiceInstance()`

**Преимущества:**
- Соответствие контракту
- UI пакеты работают через `ISecurityService.instance`
- Легко тестировать (mock интерфейс)

**Недостатки:**
- Много работы (реализовать ~30 методов)

### Вариант 2: Адаптер (промежуточное решение)

**Шаги:**
1. Создать `AQSecurityServiceAdapter implements ISecurityService`
2. Адаптер делегирует вызовы в `AQSecurityService`
3. Недостающие методы выбрасывают `UnimplementedError` с TODO

**Преимущества:**
- Быстро реализовать
- Соответствие контракту
- Постепенная миграция

**Недостатки:**
- Дополнительный слой абстракции

### Вариант 3: Упростить интерфейс (радикальный)

**Шаги:**
1. Удалить из `ISecurityService` методы, которые не нужны сейчас
2. Оставить только базовые: login, logout, permissions, roles
3. Подсервисы сделать опциональными

**Преимущества:**
- Меньше работы
- Проще поддерживать

**Недостатки:**
- Потеря функциональности
- Нарушение архитектурного плана

## Критичность проблемы

**Высокая** — это архитектурная проблема, которая блокирует:
- Использование UI пакетов (они ожидают `ISecurityService.instance`)
- Тестирование (нельзя подменить реализацию)
- Расширение функциональности (нет контракта)

## Следующие шаги

1. **Немедленно**: Удалить дублирование `SecurityState`
2. **Высокий приоритет**: Реализовать `ISecurityService` в `AQSecurityService`
3. **Средний приоритет**: Реализовать недостающие методы
4. **Низкий приоритет**: Добавить подсервисы (roleManagement, policies, audit)
