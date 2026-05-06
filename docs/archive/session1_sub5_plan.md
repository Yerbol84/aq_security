# Подсессия 5 — Фаза 3: Качество и безопасность

**Источник:** AQ_SECURITY_ARCHITECTURE_REPORT.md → Часть 4, Приоритет 3 (ТЗ-3.1, ТЗ-3.3, ТЗ-3.4) + остатки

---

## Цель

Финальная полировка: устранить security-риски, исправить организацию файлов,
убрать ложные защиты, переименовать файлы с опечатками.

---

## Предусловие

Подсессия 4 завершена, `dart analyze` → 0 errors.

---

## Задачи

### ТЗ-3.1: Убрать ложную SQL injection защиту
**Файл:** `aq_security/lib/src/client/aq_vault_security_protocol.dart`

Удалить метод `_containsSqlInjection()` и его вызов из `validateData()`.
Заменить комментарием: SQL injection prevention — ответственность ORM/query builder, не security layer.

### ТЗ-3.3: Исправить CORS header
**Файл:** `aq_security/lib/src/server/aq_auth_server.dart`

```dart
// Было:
'Access-Control-Allow-Origin': isAllowed ? origin : '',

// Стало: не добавлять заголовок если origin не разрешён
if (isAllowed) headers['Access-Control-Allow-Origin'] = origin;
```

### ТЗ-3.4: Перенести IUserRepository / IProfileRepository
**Файл источник:** `aq_schema/lib/security/interfaces/i_session_repository.dart`
**Создать:** `aq_schema/lib/security/interfaces/i_user_repository.dart`

Перенести `IUserRepository` и `IProfileRepository` в отдельный файл.
Обновить все импорты.

### Переименование файла с опечаткой
**Было:** `i_data_layer_as_clietn_secure_protocol.dart`
**Стало:** `i_vault_security_protocol.dart`

Обновить все импорты в обоих пакетах.

### Добавить register() в HttpAuthTransport
**Файл:** `aq_security/lib/src/client/http_auth_transport.dart`

Реализовать метод `register()` если он объявлен в `IAuthTransport` но не реализован.

---

## Критерий завершения

- [ ] `_containsSqlInjection` удалён
- [ ] CORS не возвращает пустую строку
- [ ] `IUserRepository` в отдельном файле
- [ ] Файл переименован, все импорты обновлены
- [ ] `register()` реализован
- [ ] `dart analyze` → 0 errors в обоих пакетах
- [ ] Заполнен `report.md`
- [ ] Финальный `dart analyze` — чистый результат зафиксирован в report.md
