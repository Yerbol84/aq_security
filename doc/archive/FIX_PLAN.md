# План исправления ошибок компиляции

## Изученные API

### 1. AccessDecision (aq_schema)
```dart
class AccessDecision {
  AccessDecision({
    required this.allowed,
    this.reason,
    this.appliedPolicies = const [],
    this.effectivePermissions = const [],  // ✅ ЕСТЬ!
  });

  factory AccessDecision.allow({
    String? reason,
    List<String>? appliedPolicies,
    List<String>? effectivePermissions,  // ✅ ЕСТЬ!
  });

  factory AccessDecision.deny({
    required String reason,
    List<String>? appliedPolicies,
    // ❌ НЕТ effectivePermissions в deny!
  });
}
```

### 2. VaultQuery API (aq_schema)
```dart
// ✅ ПРАВИЛЬНО - Fluent API с методом .where()
final q = VaultQuery()
    .where('userId', VaultOperator.equals, userId)
    .where('timestamp', VaultOperator.greaterThan, startTime)
    .orderBy('timestamp', descending: true)
    .page(limit: 100, offset: 0);

// VaultFilter - positional parameters
VaultFilter(String field, VaultOperator operator, dynamic value)

// VaultOperator - enum с правильными именами
enum VaultOperator {
  equals, notEquals, contains, startsWith,
  greaterThan, greaterOrEqual,  // ✅ greaterOrEqual (не greaterThanOrEqual)
  lessThan, lessOrEqual,        // ✅ lessOrEqual (не lessThanOrEqual)
  isNull, isNotNull, inList, notInList
}

// VaultSort - single sort, not List
VaultSort(field: 'timestamp', descending: true)
```

### 3. Repository API (dart_vault)
```dart
// Используется DirectRepositoryImpl с методом findAll()
final results = await _repo.findAll(
  query: VaultQuery()
      .where('userId', VaultOperator.equals, userId)
      .page(limit: 100, offset: 0),
);
```

## Ошибки и исправления

### Ошибка 1: Неправильное использование VaultFilter
**Текущий код:**
```dart
VaultFilter(field: 'userId', operator: VaultOperator.equals, value: userId)
```

**Правильно:**
```dart
// VaultFilter использует positional parameters
VaultFilter('userId', VaultOperator.equals, userId)
```

**Но лучше использовать fluent API:**
```dart
VaultQuery().where('userId', VaultOperator.equals, userId)
```

### Ошибка 2: Неправильные константы VaultOperator
**Текущий код:**
```dart
VaultOperator.greaterThanOrEqual  // ❌ Не существует
VaultOperator.lessThanOrEqual     // ❌ Не существует
```

**Правильно:**
```dart
VaultOperator.greaterOrEqual  // ✅
VaultOperator.lessOrEqual     // ✅
```

### Ошибка 3: VaultSort как List
**Текущий код:**
```dart
sort: [VaultSort(field: 'timestamp', descending: true)]
```

**Правильно:**
```dart
// VaultQuery.sort - это VaultSort?, не List
// Используем метод .orderBy()
VaultQuery()
    .where(...)
    .orderBy('timestamp', descending: true)
```

### Ошибка 4: AccessDecision.deny с effectivePermissions
**Текущий код:**
```dart
AccessDecision.deny(
  reason: 'Permission denied',
  effectivePermissions: [...],  // ❌ Параметр не существует в deny
)
```

**Правильно:**
```dart
// deny() не принимает effectivePermissions
AccessDecision.deny(
  reason: 'Permission denied',
  appliedPolicies: [...],
)

// Или использовать основной конструктор
AccessDecision(
  allowed: false,
  reason: 'Permission denied',
  effectivePermissions: [...],  // ✅ Есть в основном конструкторе
)
```

### Ошибка 5: Конфликт VaultRoleRepository
Класс определён в двух файлах:
- `vault_security_repositories.dart`
- `rbac_repositories.dart`

**Решение:** Переименовать класс в `rbac_repositories.dart` в `RBACVaultRoleRepository`

### Ошибка 6: Неправильный API репозиториев
**Текущий код:**
```dart
await vault.query(collection, VaultQuery(...))
await vault.save(collection, id, data)
await vault.delete(collection, id)
```

**Правильно - использовать DirectRepositoryImpl:**
```dart
final repo = DirectRepositoryImpl<MyModel>(
  storage: vault,
  collection: 'my_collection',
  fromMap: MyModel.fromMap,
);

// Затем использовать методы репозитория
await repo.findAll(query: VaultQuery()...)
await repo.save(model)
await repo.delete(id)
```

## План действий

1. ✅ **Изучить API** - ЗАВЕРШЕНО
2. **Исправить rbac_repositories.dart:**
   - Переименовать VaultRoleRepository → RBACVaultRoleRepository
   - Заменить все vault.query() на использование DirectRepositoryImpl
   - Исправить VaultOperator константы
   - Убрать List<VaultSort>, использовать .orderBy()
3. **Исправить access_control_engine.dart:**
   - Исправить AccessDecision.deny() - убрать effectivePermissions
   - Использовать основной конструктор где нужны effectivePermissions
4. **Проверить компиляцию:**
   - dart analyze
   - Исправить оставшиеся ошибки
5. **Обновить RBACRouter:**
   - Добавить endpoints для метрик и оповещений

## Приоритет исправлений

1. **HIGH**: Конфликт VaultRoleRepository (блокирует компиляцию)
2. **HIGH**: API VaultQuery/VaultFilter (80+ ошибок)
3. **MEDIUM**: AccessDecision параметры (3 ошибки)
4. **LOW**: Добавить endpoints в RBACRouter
