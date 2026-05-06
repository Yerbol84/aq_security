# План миграции слоя безопасности

**Дата**: 2026-04-21  
**Пакет**: aq_security  
**Статус**: В ожидании ответа от дата-слоя

---

## Обзор

Миграция моделей безопасности на правильные типы хранения для обеспечения:
- Автоматической expiration временных сущностей
- Версионирования конфигураций безопасности
- Полного audit trail для compliance
- Возможности rollback после инцидентов

---

## Зависимости

### Блокер: Ответ от дата-слоя

**Документ**: `pkgs/dart_vault_package/other_layer_tasks/secure_layer/REQUIREMENTS_FOR_DATA_LAYER.md`

**Ожидаемые ответы**:
1. ✅ / ❌ TTL Support для LoggedStorable
2. ✅ / ❌ TTL Support для DirectStorable
3. ✅ / ❌ Подтверждение работы VersionedRepository для наших use cases
4. 📋 Инструкции по миграции DirectStorable → VersionedStorable

**Без ответа дата-слоя**: Миграция невозможна

---

## Фаза 0: Подготовка (без блокеров)

### Задача 0.1: Анализ текущего состояния

**Статус**: ✅ Завершено  
**Результат**: Документ `DATA_LAYER_ANALYSIS.md`

**Выводы**:
- AqSession (LoggedStorable) — требует TTL support
- AqApiKey (LoggedStorable) — требует TTL support
- AqUserRole (DirectStorable) — требует TTL support
- AqRole (DirectStorable) — требует миграцию на VersionedStorable
- AqPolicy (DirectStorable) — требует миграцию на VersionedStorable

### Задача 0.2: Инвентаризация репозиториев

**Статус**: ✅ Завершено

**Текущие репозитории**:
```
lib/src/server/repositories/
├── vault_security_repositories.dart
│   ├── VaultUserRepository (DirectRepository)
│   ├── VaultSessionRepository (LoggedRepository)
│   ├── VaultApiKeyRepository (LoggedRepository)
│   ├── VaultRoleRepository (DirectRepository) ← Требует миграции
│   ├── VaultTenantRepository (DirectRepository)
│   └── VaultProfileRepository (DirectRepository)
└── rbac_repositories.dart
    ├── RBACVaultRoleRepository (DirectRepository) ← Дубликат
    ├── VaultUserRoleRepository (DirectRepository)
    ├── VaultPolicyRepository (DirectRepository) ← Требует миграции
    ├── VaultAccessLogRepository (Direct)
    ├── VaultAlertRepository (Direct)
    └── VaultMetricsRepository (Direct)
```

**Проблемы**:
- Дублирование: `VaultRoleRepository` и `RBACVaultRoleRepository`
- Разные коллекции: `security_roles` vs `rbac_roles`

### Задача 0.3: Создать тестовые сценарии

**Статус**: 🔄 В процессе  
**Файл**: `test/integration/ttl_expiration_test.dart`

**Сценарии**:
1. Session expiration
2. API Key expiration
3. UserRole expiration
4. Role versioning
5. Policy versioning

---

## Фаза 1: Миграция на TTL Support (зависит от дата-слоя)

### Задача 1.1: Обновить StorableSession

**Блокер**: Ответ дата-слоя на TTL Support для LoggedStorable

**Файл**: `pkgs/aq_schema/lib/security/storable/security_storables.dart`

**Изменения**:
```dart
final class StorableSession implements LoggedStorable {
  StorableSession(this._session);
  final AqSession _session;
  AqSession get domain => _session;
  
  // ДОБАВИТЬ:
  @override
  int? get expiresAt => _session.expiresAt;
  
  @override
  StorableSession? onExpire() {
    return StorableSession(_session.copyWith(
      status: SessionStatus.expired,
    ));
  }
  
  @override
  Set<String> get trackedFields => {
    'status',
    'lastSeenAt',
    'revokedAt',
    'revokedReason',
  };
  
  // Existing...
}
```

**Тесты**:
```dart
test('Session auto-expires after expiresAt', () async {
  final session = AqSession(
    id: 'session_1',
    expiresAt: DateTime.now().add(Duration(seconds: 1)).millisecondsSinceEpoch ~/ 1000,
    status: SessionStatus.active,
    // ...
  );
  
  await sessionRepo.save(StorableSession(session), actorId: 'user_1');
  
  await Future.delayed(Duration(seconds: 2));
  
  final loaded = await sessionRepo.findById('session_1');
  expect(loaded?.domain.status, SessionStatus.expired);
  
  // Проверить log entry
  final history = await sessionRepo.getHistory('session_1');
  expect(history.last.actorId, 'system');
  expect(history.last.reason, 'auto_expired');
});
```

**Оценка**: 2 часа (после ответа дата-слоя)

### Задача 1.2: Обновить StorableApiKey

**Блокер**: Ответ дата-слоя на TTL Support для LoggedStorable

**Файл**: `pkgs/aq_schema/lib/security/storable/security_storables.dart`

**Изменения**:
```dart
final class StorableApiKey implements LoggedStorable {
  StorableApiKey(this._key);
  final AqApiKey _key;
  AqApiKey get domain => _key;
  
  // ДОБАВИТЬ:
  @override
  int? get expiresAt => _key.expiresAt;
  
  @override
  StorableApiKey? onExpire() {
    return StorableApiKey(_key.copyWith(
      isActive: false,
    ));
  }
  
  @override
  Set<String> get trackedFields => {'isActive', 'lastUsedAt'};
  
  // Existing...
}
```

**Оценка**: 1 час (после ответа дата-слоя)

### Задача 1.3: Обновить StorableUserRole

**Блокер**: Ответ дата-слоя на TTL Support для DirectStorable

**Файл**: `pkgs/aq_schema/lib/security/storable/security_storables.dart`

**Изменения**:
```dart
final class StorableUserRole implements DirectStorable {
  StorableUserRole(this._userRole);
  final AqUserRole _userRole;
  AqUserRole get domain => _userRole;
  
  // ДОБАВИТЬ:
  @override
  int? get expiresAt => _userRole.expiresAt;
  
  // onExpire не нужен - дата-слой просто удалит запись
  
  // Existing...
}
```

**Оценка**: 30 минут (после ответа дата-слоя)

### Задача 1.4: Удалить ручную expiration логику

**Файл**: `lib/src/server/repositories/vault_security_repositories.dart`

**Удалить**:
```dart
// УДАЛИТЬ весь метод:
Future<int> purgeExpired() async {
  // Больше не нужен - дата-слой делает это автоматически
}
```

**Файл**: `lib/src/server/session_service.dart`

**Удалить**:
```dart
// УДАЛИТЬ вызовы purgeExpired():
// await _repo.purgeExpired();
```

**Оценка**: 1 час

---

## Фаза 2: Миграция AqRole на VersionedStorable (зависит от дата-слоя)

### Задача 2.1: Объединить дублирование ролей

**Проблема**: Роли хранятся в двух местах:
- `security_roles` (через `SecurityCollections.roles`)
- `rbac_roles` (через `AqRole.kCollection`)

**Решение**: Использовать только `security_roles`

**Файлы**:
- `pkgs/aq_schema/lib/security/storable/security_storables.dart`
- `pkgs/aq_schema/lib/security/storable/storable_rbac.dart`

**Изменения**:
1. Удалить `StorableAqRole` из `storable_rbac.dart`
2. Использовать только `StorableRole` из `security_storables.dart`
3. Обновить `AqRole.kCollection = 'security_roles'`

**Оценка**: 2 часа

### Задача 2.2: Мигрировать StorableRole на VersionedStorable

**Блокер**: Ответ дата-слоя + Задача 2.1

**Файл**: `pkgs/aq_schema/lib/security/storable/security_storables.dart`

**Изменения**:
```dart
// БЫЛО:
final class StorableRole implements DirectStorable {
  // ...
}

// СТАЛО:
final class StorableRole implements VersionedStorable {
  StorableRole(this._role);
  final AqRole _role;
  AqRole get domain => _role;
  
  @override
  String get id => _role.id;
  
  @override
  String get entityId => _role.id; // Все версии одной роли
  
  @override
  String get ownerId => _role.tenantId ?? 'platform';
  
  @override
  List<String> get sharedWith => _role.tenantId == null
    ? ['*'] // System roles видны всем
    : [_role.tenantId!]; // Tenant roles только своему tenant
  
  @override
  Map<String, dynamic> toMap() => _role.toJson();
  
  @override
  Map<String, dynamic> get indexFields => {
    'name': _role.name,
    'tenantId': _role.tenantId ?? '',
    'isSystem': _role.isSystem,
  };
  
  @override
  String get collectionName => SecurityCollections.roles;
}
```

**Оценка**: 3 часа

### Задача 2.3: Обновить VaultRoleRepository

**Блокер**: Задача 2.2

**Файл**: `lib/src/server/repositories/vault_security_repositories.dart`

**Изменения**:
```dart
// БЫЛО:
final class VaultRoleRepository implements IRoleRepository {
  VaultRoleRepository(VaultStorage s)
      : _repo = DirectRepositoryImpl<StorableRole>(...);
  
  final DirectRepository<StorableRole> _repo;
  
  // ...
}

// СТАЛО:
final class VaultRoleRepository implements IRoleRepository {
  VaultRoleRepository(VaultStorage s)
      : _repo = VersionedRepositoryImpl<StorableRole>(...);
  
  final VersionedRepository<StorableRole> _repo;
  
  @override
  Future<List<AqRole>> findByUser(String userId, String tenantId) async {
    // Получить назначения ролей
    final assignments = await _urRepo.findAll(
      query: VaultQuery()
          .where('userId', VaultOperator.equals, userId)
          .where('tenantId', VaultOperator.equals, tenantId),
    );
    
    final roles = <AqRole>[];
    for (final a in assignments) {
      // ИЗМЕНЕНО: Получить CURRENT версию роли
      final node = await _repo.getCurrent(a.domain.roleId);
      if (node != null) {
        final roleData = await _repo.getEntityData(node.id);
        if (roleData != null) {
          roles.add(roleData.domain);
        }
      }
    }
    return roles;
  }
  
  @override
  Future<AqRole?> findByName(String name, {String? tenantId}) async {
    // ИЗМЕНЕНО: Искать среди CURRENT версий
    final nodes = await _repo.findNodes(
      query: VaultQuery()
          .where('name', VaultOperator.equals, name)
          .where('status', VaultOperator.equals, 'current'),
    );
    
    if (nodes.isEmpty) return null;
    
    final roleData = await _repo.getEntityData(nodes.first.id);
    return roleData?.domain;
  }
  
  @override
  Future<AqRole> create(AqRole role) async {
    // ИЗМЕНЕНО: Создать entity (draft)
    final node = await _repo.createEntity(StorableRole(role));
    
    // Сразу опубликовать как v1.0.0
    await _repo.publishDraft(node.id, increment: IncrementType.major);
    
    return role;
  }
  
  // НОВЫЕ МЕТОДЫ для версионирования:
  
  Future<VersionNode> createRoleDraft(AqRole role) async {
    return await _repo.createEntity(StorableRole(role));
  }
  
  Future<VersionNode> updateRolePermissions(
    String roleId,
    List<String> newPermissions,
  ) async {
    final current = await _repo.getCurrent(roleId);
    if (current == null) throw Exception('Role not found');
    
    final roleData = await _repo.getEntityData(current.id);
    if (roleData == null) throw Exception('Role data not found');
    
    final updatedRole = roleData.domain.copyWith(
      permissions: newPermissions,
      updatedAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
    );
    
    // Создать draft с новыми правами
    final draft = await _repo.createDraftFrom(
      current.id,
      StorableRole(updatedRole),
    );
    
    return draft;
  }
  
  Future<void> publishRoleDraft(String nodeId) async {
    await _repo.publishDraft(nodeId, increment: IncrementType.minor);
  }
  
  Future<List<VersionNode>> getRoleHistory(String roleId) async {
    return await _repo.getVersionHistory(roleId);
  }
  
  Future<void> rollbackRole(String roleId, String toNodeId) async {
    // Получить данные старой версии
    final oldData = await _repo.getEntityData(toNodeId);
    if (oldData == null) throw Exception('Version not found');
    
    // Создать draft из старой версии
    final draft = await _repo.createDraftFrom(toNodeId, oldData);
    
    // Опубликовать как patch
    await _repo.publishDraft(draft.id, increment: IncrementType.patch);
  }
}
```

**Оценка**: 6 часов

### Задача 2.4: Обновить RBACService

**Блокер**: Задача 2.3

**Файл**: `lib/src/rbac/rbac_service.dart`

**Изменения**:
- Использовать `VaultRoleRepository` вместо `RBACVaultRoleRepository`
- Удалить `RBACVaultRoleRepository` из `rbac_repositories.dart`
- Обновить методы для работы с версиями

**Оценка**: 4 часа

### Задача 2.5: Миграция данных

**Блокер**: Задача 2.2

**Скрипт**: `scripts/migrate_roles_to_versioned.dart`

**Логика**:
1. Прочитать все роли из `security_roles` (DirectStorable)
2. Для каждой роли:
   - Создать entity через VersionedRepository
   - Опубликовать как v1.0.0
   - Сохранить mapping старый ID → новый nodeId
3. Обновить все `UserRole` записи с новыми roleId
4. Удалить старые записи из `security_roles`

**Оценка**: 8 часов

---

## Фаза 3: Миграция AqPolicy на VersionedStorable (зависит от дата-слоя)

### Задача 3.1: Мигрировать StorablePolicy на VersionedStorable

**Блокер**: Ответ дата-слоя

**Файл**: `pkgs/aq_schema/lib/security/storable/storable_rbac.dart`

**Изменения**: Аналогично StorableRole

**Оценка**: 3 часа

### Задача 3.2: Обновить VaultPolicyRepository

**Блокер**: Задача 3.1

**Файл**: `lib/src/server/repositories/rbac_repositories.dart`

**Изменения**: Аналогично VaultRoleRepository

**Оценка**: 6 часов

### Задача 3.3: Миграция данных

**Блокер**: Задача 3.1

**Скрипт**: `scripts/migrate_policies_to_versioned.dart`

**Оценка**: 6 часов

---

## Фаза 4: Тестирование и документация

### Задача 4.1: Integration тесты

**Файлы**:
- `test/integration/session_ttl_test.dart`
- `test/integration/api_key_ttl_test.dart`
- `test/integration/user_role_ttl_test.dart`
- `test/integration/role_versioning_test.dart`
- `test/integration/policy_versioning_test.dart`

**Оценка**: 12 часов

### Задача 4.2: Обновить документацию

**Файлы**:
- `doc/RBAC_STRATEGY.md` — добавить раздел о версионировании
- `doc/API_KEYS.md` — добавить раздел о TTL
- `README.md` — обновить примеры использования

**Оценка**: 4 часа

### Задача 4.3: Обновить примеры

**Файлы**:
- `example/role_versioning_example.dart` — новый
- `example/policy_versioning_example.dart` — новый
- `example/ttl_expiration_example.dart` — новый

**Оценка**: 3 часа

---

## Оценка времени

### По фазам

| Фаза | Задачи | Оценка | Блокеры |
|------|--------|--------|---------|
| Фаза 0 | Подготовка | ✅ 0 часов | Нет |
| Фаза 1 | TTL Support | 4.5 часа | Ответ дата-слоя |
| Фаза 2 | AqRole → Versioned | 23 часа | Ответ дата-слоя |
| Фаза 3 | AqPolicy → Versioned | 15 часов | Ответ дата-слоя |
| Фаза 4 | Тесты + Docs | 19 часов | Фазы 1-3 |
| **Итого** | | **61.5 часов** | |

### По приоритетам

**Высокий приоритет** (Фаза 1 + Фаза 2):
- TTL Support для сессий и ключей
- Версионирование ролей
- **Оценка**: 27.5 часов

**Средний приоритет** (Фаза 3):
- Версионирование политик
- **Оценка**: 15 часов

**Низкий приоритет** (Фаза 4):
- Тесты и документация
- **Оценка**: 19 часов

---

## Риски

### Риск 1: Дата-слой не поддерживает TTL

**Вероятность**: Средняя  
**Влияние**: Высокое

**Митигация**:
- Альтернатива 1: Реализовать TTL в aq_security через background job
- Альтернатива 2: Использовать Redis TTL для временных сущностей

### Риск 2: Миграция данных приводит к downtime

**Вероятность**: Высокая  
**Влияние**: Критическое

**Митигация**:
- Blue-green deployment
- Миграция в несколько этапов
- Rollback план

### Риск 3: VersionedRepository не поддерживает наши use cases

**Вероятность**: Низкая  
**Влияние**: Высокое

**Митигация**:
- Детальное обсуждение с дата-слоем перед началом
- Proof of concept на тестовых данных

---

## Следующие шаги

1. ✅ Отправить требования дата-слою
2. ⏳ Ожидать ответ от дата-слоя (1-3 дня)
3. 📋 Уточнить детали реализации
4. 🚀 Начать Фазу 1 после подтверждения

---

## Контакты

**Ответственный**: Security Layer Team  
**Дата создания**: 2026-04-21  
**Последнее обновление**: 2026-04-21
