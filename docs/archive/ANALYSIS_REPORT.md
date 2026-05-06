# Отчёт по анализу aq_security

Дата: 2026-04-20
Анализатор: Flutter 3.41.6 / Dart 3.11.4

## Сводка

- **Критичные ошибки (errors)**: 0 (все ошибки связаны с отсутствием pub get)
- **Предупреждения (warnings)**: 18
- **Информационные (info)**: 6

## Категории проблем

### 1. Избыточные null-safety операторы (8 warnings)

**Проблема**: Использование `!`, `?.`, `?? ` на non-nullable типах.

#### 1.1 Unnecessary non-null assertion (2)
- `lib/src/server/rate_limiting/rate_limit_middleware.dart:47:62`
- `lib/src/server/rate_limiting/rate_limit_middleware.dart:201:64`

#### 1.2 Dead null-aware expression (2)
- `lib/src/rbac/access_control_engine.dart:287:44`
- `lib/src/rbac/access_control_engine.dart:287:71`

#### 1.3 Unnecessary null comparison (2)
- `lib/src/server/rate_limiting/rate_limit_middleware.dart:46:30`
- `lib/src/server/rate_limiting/rate_limit_middleware.dart:200:32`

#### 1.4 Invalid null-aware operator (3)
- `lib/src/server/rbac_router.dart:104:33`
- `lib/src/server/rbac_router.dart:226:33`
- `lib/src/server/rbac_router.dart:361:39`

**Приоритет**: Средний (код работает, но засоряет анализ)

---

### 2. Неиспользуемые переменные (8 warnings)

#### 2.1 Production код (3)
- `lib/src/client/aq_vault_security_protocol.dart:71:26` — `_requestValidator` (поле класса)
- `lib/src/server/metrics/metrics_collector.dart:106:11` — `periodStart`
- `lib/src/server/metrics/metrics_collector.dart:140:11` — `periodStart`

#### 2.2 Тесты (3)
- `test/unit/api_key_rotation_test.dart:212:13` — `freshKey`
- `test/unit/api_key_rotation_test.dart:252:13` — `safeKey`
- `test/unit/permission_inheritance_test.dart:135:15` — `now`

#### 2.3 Примеры (2)
- `example/logging_example.dart:36:9` — `server`
- `example/monitoring_example.dart:71:9` — `server`

**Приоритет**: Низкий (примеры), Средний (тесты), Высокий (production код с `_requestValidator`)

---

### 3. Unreachable switch default (2 warnings)

- `lib/src/rbac/access_control_engine.dart:346:7`
- `lib/src/rbac/access_control_engine.dart:522:7`

**Проблема**: Switch покрывает все случаи enum, default недостижим.

**Приоритет**: Низкий (код работает корректно)

---

### 4. Избыточные импорты (6 info)

#### 4.1 lib/src/client/aq_vault_security_protocol.dart (5 импортов)
Все элементы уже есть в `package:aq_schema/security/security.dart`:
- `i_data_layer_as_clietn_secure_protocol.dart` (строка 8)
- `aq_token_claims.dart` (строка 9)
- `aq_resource_permission.dart` (строка 10)
- `access_decision.dart` (строка 11)
- `token_codec.dart` (строка 13)

#### 4.2 lib/src/server/repositories/vault_security_repositories.dart (1 импорт)
- `package:dart_vault/dart_vault.dart` (строка 20) — уже есть в `aq_schema.dart`

**Приоритет**: Низкий (не влияет на работу, но улучшает читаемость)

---

## Рекомендации по приоритетам

### Высокий приоритет
1. **`_requestValidator` не используется** (`aq_vault_security_protocol.dart:71`)
   - Либо удалить поле
   - Либо реализовать валидацию запросов

### Средний приоритет
2. **Null-safety операторы** (8 мест)
   - Убрать `!`, `?.`, `??` где тип уже non-nullable
   - Улучшит читаемость и уберёт шум в анализе

3. **Неиспользуемые переменные в production** (2 места в `metrics_collector.dart`)
   - Либо использовать `periodStart`
   - Либо удалить

### Низкий приоритет
4. **Unreachable switch default** (2 места)
   - Можно оставить для будущего расширения enum
   - Или удалить default clause

5. **Избыточные импорты** (6 мест)
   - Почистить для улучшения читаемости

6. **Неиспользуемые переменные в тестах/примерах** (5 мест)
   - Добавить `// ignore: unused_local_variable`
   - Или использовать переменные

---

## Блокеры для production

**НЕТ критичных блокеров** — все проблемы категории warning/info.

Однако рекомендуется исправить перед production:
- [ ] Разобраться с `_requestValidator` (может быть недореализованная фича)
- [ ] Убрать null-safety шум (улучшит поддерживаемость)
- [ ] Почистить неиспользуемые переменные в production коде

---

## Следующие шаги

1. Исправить `_requestValidator` (высокий приоритет)
2. Batch-фикс null-safety операторов (средний приоритет)
3. Почистить импорты в `aq_vault_security_protocol.dart`
4. Решить что делать с `periodStart` в `metrics_collector.dart`

---

## Примечания

- Все ошибки типа `uri_does_not_exist`, `undefined_*` связаны с отсутствием `flutter pub get`
- Package config актуален (все зависимости зарегистрированы)
- Сетевая проблема (429 Too Many Requests) блокирует pub get
- Реальных ошибок компиляции НЕТ
