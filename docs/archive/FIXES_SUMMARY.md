# Сводка исправлений aq_security

Дата: 2026-04-20

## Исправленные критичные ошибки

### 1. AuthProvider → IdentityProvider (6 файлов)
**Проблема**: Использовался несуществующий тип `AuthProvider` вместо `IdentityProvider` из `aq_schema`.

**Исправлено**:
- `lib/src/server/session_service.dart:30` — параметр `create()`
- `lib/src/server/user_service.dart:79` — Google OAuth
- `lib/src/server/user_service.dart:153` — GitHub OAuth
- `lib/src/server/user_service.dart:229` — Email/Password (2 места)
- `lib/src/server/user_service.dart:268` — проверка провайдера
- `lib/src/server/user_service.dart:398` — Magic Link

### 2. AccessContext API (rbac_router.dart:282-291)
**Проблема**: Несоответствие сигнатуры `AccessContext` из `aq_schema`.

**Исправлено**:
- Добавлен обязательный параметр `tenantId`
- Удалены несуществующие параметры: `scope`, `ip`, `resourceState`, `metadata`
- Добавлены правильные параметры: `userRoles`, `userPermissions`, `userScopes`, `ipAddress`, `userAgent`, `userAttributes`, `resourceAttributes`, `sessionId`, `requestId`

### 3. AccessDecision.effectivePermissions (rbac_router.dart:307)
**Проблема**: Поле `effectivePermissions` не существует в `AccessDecision`.

**Исправлено**: Заменено на `matchedRoles` и `matchedPermissions`.

### 4. AQPermission API
**Проблема**: Отсутствующий обязательный параметр `createdBy` в `createPolicy()`.

**Исправлено**: `lib/src/server/rbac_router.dart:343` — добавлен `createdBy: data['createdBy']`

**Проблема**: Неизвестный параметр `enabled` в `updatePolicy()`.

**Исправлено**: `lib/src/server/rbac_router.dart:403` — заменён на `isActive`

### 5. RBACMetrics API (rbac_repositories.dart)
**Проблема**: Поля `acknowledged`, `acknowledgedBy`, `acknowledgedAt` не существуют в `AccessAlert`.

**Исправлено**: Заменены на `resolved`, `resolvedBy`, `resolvedAt` (строки 323-325, 334)

**Проблема**: Поле `periodStart` не существует в `RBACMetrics`.

**Исправлено**: Заменено на `timestamp` (строки 350, 360, 362)

### 6. rbacService.can() сигнатура (rbac_router.dart:303)
**Проблема**: Метод требует 4 позиционных аргумента, передавалось 3.

**Исправлено**: Добавлен 4-й аргумент `scope` (по умолчанию `'own'`)

### 7. const → final для Uuid() (5 файлов)
**Проблема**: `Uuid()` не является compile-time константой.

**Исправлено**:
- `lib/src/server/session_service.dart:22`
- `lib/src/server/user_service.dart:28`
- `lib/src/server/token_issuer.dart:17`
- `lib/src/server/permission_inheritance_service.dart:71`
- `lib/src/server/resource_permission_service.dart:13`
- `lib/src/server/dos_protection/dos_protection_middleware.dart:18`

### 8. double → int в field_encryption_service.dart
**Проблема**: `Uint8List.setRange()` требует `int`, но получал `double`.

**Исправлено**: Явное приведение типов для `iv.length` и `ciphertext.length` (строки 161-164)

## Статистика

- **Всего исправлено**: 18 критичных ошибок
- **Затронуто файлов**: 9
- **Оставшиеся ошибки**: 2 (только в примерах, не в production коде)

## Оставшиеся некритичные проблемы

### Примеры (не блокируют production)
1. `example/monitoring_example.dart:48` — отсутствует `requestValidator`
2. `example/monitoring_example.dart:54` — некорректный вызов функции

### Warnings (18 шт.)
- Избыточные null-safety операторы (8 мест)
- Неиспользуемые переменные (8 мест)
- Unreachable switch default (2 места)

### Info (6 шт.)
- Избыточные импорты в `aq_vault_security_protocol.dart` (5 импортов)
- Избыточный импорт в `vault_security_repositories.dart` (1 импорт)

## Рекомендации

1. **Высокий приоритет**: Исправить примеры или добавить `// ignore_for_file` если они устарели
2. **Средний приоритет**: Почистить null-safety операторы и неиспользуемые переменные
3. **Низкий приоритет**: Удалить избыточные импорты

## Блокеры для production

**НЕТ** — все критичные ошибки исправлены. Пакет готов к использованию.
