# Подсессия 4 — Фаза 2: Архитектурные улучшения

**Источник:** AQ_SECURITY_ARCHITECTURE_REPORT.md → Часть 4, Приоритет 2 (ТЗ-2.1 — ТЗ-2.4)

---

## Цель

Привести архитектуру к целевому состоянию: единый facade инициализации,
задекларировать два режима работы, унифицировать Session model, TTL из конфига.

---

## Предусловие

Подсессия 3 завершена, `dart analyze` → 0 errors.

---

## Задачи

### ТЗ-2.1: SecurityMode enum
**Создать файл:** `aq_schema/lib/security/models/security_mode.dart`

```dart
enum SecurityMode {
  /// Embedded: security и data layer в одном процессе.
  embedded,
  /// Distributed: security как отдельный HTTP сервис.
  distributed,
}
```

Использовать в `SecurityConfig`. Задокументировать оба режима.

### ТЗ-2.2: AqSecurity facade — единая инициализация
**Создать файл:** `aq_security/lib/src/client/aq_security.dart`

Единственная точка инициализации всех трёх синглтонов:
```dart
final class AqSecurity {
  static Future<AQSecurityService> init({
    required SecurityClientConfig config,
  }) async {
    // создать transport, store, service
    // установить все три синглтона:
    setSecurityServiceInstance(service);
    IAuthContext.initialize(AqAuthContext(service));
    IVaultSecurityProtocol.initialize(AqVaultSecurityProtocol(...));
    return service;
  }
}
```

**Правило RULE-5:** никакой код снаружи не должен вызывать синглтоны напрямую.

### ТЗ-2.3: SessionKind в AqSession
**Изменить файл:** `aq_schema/lib/security/models/aq_session.dart`

Добавить:
```dart
enum SessionKind { human, service, workflow, worker }
```
Добавить поле `SessionKind kind` в `AqSession`.

### ТЗ-2.4: rbacCacheTtl в SecurityConfig
**Изменить файл:** `aq_security/lib/src/shared/security_config.dart`

Добавить поле `final Duration rbacCacheTtl` (default: `Duration(minutes: 1)`).
Передавать в `AccessCache` при создании в `AQAuthServer`.

---

## Критерий завершения

- [ ] `AqSecurity.init()` инициализирует все три синглтона
- [ ] Прямые вызовы `IVaultSecurityProtocol.initialize()` снаружи facade — убраны
- [ ] `SecurityMode` enum существует и используется в `SecurityConfig`
- [ ] `AqSession` содержит поле `kind`
- [ ] `AccessCache` получает TTL из конфига
- [ ] `dart analyze` → 0 errors
- [ ] Заполнен `report.md`
