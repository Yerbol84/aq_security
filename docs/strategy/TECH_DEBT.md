# Tech Debt — aq_security

**Обновлено:** 2026-05-05  
**Проверено по коду:** ✅

---

## 🔴 HIGH — Ручная purgeExpired вместо TTL data layer

**Файлы:**
- `lib/src/server/session_service.dart` — вызывает `repo.purgeExpired()`
- `lib/src/server/repositories/vault_security_repositories.dart` — реализует `purgeExpired()`
- `lib/src/testing/in_memory_repositories.dart` — in-memory версия

**Проблема:** Истечение сессий, API ключей и временных ролей управляется вручную через периодический `purgeExpired()`. Если job не запустился — устаревшие записи остаются активными.

**Решение:** Добавить `expiresAt` и `onExpire()` в `StorableSession`, `StorableApiKey`, `StorableUserRole`. Data layer обрабатывает истечение автоматически. После — удалить `purgeExpired()`.

**Требование к data layer:** `aq_schema/tech_debt/for_data_layer/TD-4_ttl-support/`

---

## 🟠 MEDIUM — StorableRole и StorablePolicy на DirectStorable вместо VersionedStorable

**Файлы:**
- `aq_schema/lib/security/storable/security_storables.dart` — `StorableRole implements DirectStorable`
- `aq_schema/lib/security/storable/storable_rbac.dart` — `StorableAqPolicy implements DirectStorable`

**Проблема:** Изменения ролей и политик не версионируются. Нет истории изменений, нет rollback при инциденте.

**Решение:** Мигрировать на `VersionedStorable` — использовать `VersionedRepository` вместо `DirectRepository`. Добавить методы `createDraft`, `publish`, `rollback` в репозитории.

**Требование к data layer:** `aq_schema/tech_debt/for_data_layer/TD-5_versioned-repository/`

---

## ✅ Все актуальные долги закрыты или переданы в data layer (TD-4, TD-5).
