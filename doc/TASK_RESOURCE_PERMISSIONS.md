# Задание: Реализация IResourcePermissionService

## Контекст

Data Layer (`dart_vault_package`) требует сервис для управления правами доступа на уровне ресурсов (Resource-Level Access Control).

Интерфейс уже определен в `aq_schema`: `IResourcePermissionService`

Текущая реализация в `AqVaultSecurityProtocol` — это заглушка `_NoOpResourcePermissionService`, которая ничего не делает.

## Требования к реализации

### 1. Создать класс `ResourcePermissionService`

**Файл:** `pkgs/aq_security/lib/src/server/resource_permission_service.dart`

**Интерфейс:** Реализует `IResourcePermissionService` из `aq_schema`

**Зависимости:**
- Репозиторий для хранения прав (см. п.2)
- Кэш для оптимизации (TTL 30-60 сек)
- Audit service для логирования операций

### 2. Создать репозиторий для хранения прав

**Интерфейс:** `pkgs/aq_schema/lib/security/interfaces/i_resource_permission_repository.dart`

```dart
/// Репозиторий для хранения прав доступа на ресурсы.
///
/// Data Layer требует только эти методы для работы с правами.
/// Реализация должна быть в aq_security.
abstract interface class IResourcePermissionRepository {
  /// Сохранить право доступа (insert or update).
  ///
  /// Если право уже существует для (resourceId, userId) — обновить уровень.
  Future<void> save(AqResourcePermission permission);

  /// Удалить право доступа.
  Future<void> delete({
    required String resourceId,
    required String userId,
  });

  /// Получить все права на ресурс.
  ///
  /// Возвращает только активные права (не истёкшие).
  Future<List<AqResourcePermission>> findByResource(String resourceId);

  /// Получить все ресурсы пользователя.
  ///
  /// Опционально фильтровать по минимальному уровню доступа.
  Future<List<String>> findResourcesByUser({
    required String userId,
    AccessLevel? minimumLevel,
  });

  /// Проверить наличие права.
  Future<bool> exists({
    required String resourceId,
    required String userId,
    required AccessLevel minimumLevel,
  });

  /// Удалить все права на ресурс.
  Future<void> deleteAllByResource(String resourceId);
}
```

**Реализация:** `pkgs/aq_security/lib/src/server/repositories/resource_permission_repository.dart`

### 3. Схема БД

**Таблица:** `resource_permissions`

```sql
CREATE TABLE resource_permissions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  resource_id TEXT NOT NULL,
  user_id TEXT NOT NULL,
  level TEXT NOT NULL CHECK (level IN ('read', 'write', 'admin')),
  granted_by TEXT NOT NULL,
  granted_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  expires_at TIMESTAMPTZ,
  
  UNIQUE(resource_id, user_id)
);

CREATE INDEX idx_resource_permissions_resource ON resource_permissions(resource_id);
CREATE INDEX idx_resource_permissions_user ON resource_permissions(user_id);
CREATE INDEX idx_resource_permissions_expires ON resource_permissions(expires_at) WHERE expires_at IS NOT NULL;
```

### 4. Модель данных

Модель `AqResourcePermission` уже существует в `aq_schema/lib/security/models/aq_resource_permission.dart`.

Проверить, что она содержит все необходимые поля:
- `id` (UUID)
- `resourceId` (String)
- `userId` (String)
- `level` (AccessLevel: read, write, admin)
- `grantedBy` (String)
- `grantedAt` (DateTime)
- `expiresAt` (DateTime?)

### 5. Кэширование

Реализовать кэш с TTL 30-60 секунд:

```dart
class _PermissionCache {
  final Map<String, _CachedPermissions> _cache = {};
  
  List<AqResourcePermission>? get(String resourceId) {
    final cached = _cache[resourceId];
    if (cached == null || cached.isExpired) return null;
    return cached.permissions;
  }
  
  void set(String resourceId, List<AqResourcePermission> permissions) {
    _cache[resourceId] = _CachedPermissions(
      permissions: permissions,
      cachedAt: DateTime.now(),
    );
  }
  
  void invalidate(String resourceId) {
    _cache.remove(resourceId);
  }
}

class _CachedPermissions {
  final List<AqResourcePermission> permissions;
  final DateTime cachedAt;
  
  bool get isExpired {
    return DateTime.now().difference(cachedAt) > Duration(seconds: 30);
  }
}
```

### 6. Аудит

Все операции должны логироваться через `IAuditService`:

```dart
await auditService.logAccess(
  userId: grantedBy,
  userEmail: '', // Получить из контекста
  tenantId: '', // Получить из контекста
  resource: resourceId,
  action: 'grant_access',
  allowed: true,
  metadata: {
    'targetUserId': userId,
    'level': level.name,
  },
);
```

### 7. Интеграция в `AqVaultSecurityProtocol`

Обновить конструктор:

```dart
final class AqVaultSecurityProtocol implements IVaultSecurityProtocol {
  AqVaultSecurityProtocol({
    required String introspectionEndpoint,
    required String encryptionKey,
    required IResourcePermissionRepository permissionRepository, // НОВОЕ
    required IAuditService auditService, // НОВОЕ
    RateLimitConfig? rateLimitConfig,
    RequestValidationConfig? validationConfig,
    Map<String, EncryptionConfig>? encryptionConfigs,
  })  : _introspectionClient = IntrospectionClient(...),
        _encryptionService = FieldEncryptionService(...),
        _rateLimiter = RateLimiter(...),
        _requestValidator = RequestValidator(...),
        _encryptionConfigs = encryptionConfigs ?? {},
        _resourcePermissionService = ResourcePermissionService(
          repository: permissionRepository,
          auditService: auditService,
        );

  final IResourcePermissionService _resourcePermissionService;

  @override
  IResourcePermissionService get resourcePermissions => _resourcePermissionService;
}
```

## Что НЕ нужно делать

❌ **НЕ создавать** кастомные воркфлоу или бизнес-логику  
❌ **НЕ добавлять** дополнительные методы в интерфейс без согласования  
❌ **НЕ менять** сигнатуры методов в `IResourcePermissionService`  
❌ **НЕ добавлять** зависимости от других пакетов (кроме `aq_schema`)  

## Что нужно сделать

✅ Создать интерфейс `IResourcePermissionRepository` в `aq_schema`  
✅ Реализовать `ResourcePermissionService` в `aq_security`  
✅ Реализовать `ResourcePermissionRepository` в `aq_security`  
✅ Создать миграцию БД для таблицы `resource_permissions`  
✅ Добавить кэширование с TTL 30-60 сек  
✅ Интегрировать аудит через `IAuditService`  
✅ Обновить `AqVaultSecurityProtocol` для использования реального сервиса  
✅ Написать unit-тесты для всех методов  
✅ Написать integration-тесты с реальной БД  

## Критерии приёмки

1. Все методы `IResourcePermissionService` работают корректно
2. Права сохраняются в БД и корректно читаются
3. Кэш работает (повторные запросы не идут в БД)
4. Все операции логируются в audit trail
5. Истёкшие права (expiresAt < now) не возвращаются в `list()` и `hasAccess()`
6. Unit-тесты покрывают все методы (coverage > 90%)
7. Integration-тесты проверяют работу с реальной PostgreSQL

## Примеры использования

### Выдача права

```dart
final service = IVaultSecurityProtocol.instance!.resourcePermissions;

await service.grant(
  resourceId: 'project-123',
  userId: 'user-456',
  level: AccessLevel.write,
  grantedBy: 'admin-789',
);
```

### Проверка права

```dart
final hasAccess = await service.hasAccess(
  resourceId: 'project-123',
  userId: 'user-456',
  minimumLevel: AccessLevel.read,
);
```

### Получение списка прав

```dart
final grants = await service.list('project-123');
for (final grant in grants) {
  print('${grant.userId} has ${grant.level.name} access');
}
```

## Вопросы?

Если что-то неясно — задавайте вопросы в issue или обсуждайте в команде.

**Важно:** Это задание касается только протокола и хранения данных. Никакой бизнес-логики, воркфлоу или UI.
