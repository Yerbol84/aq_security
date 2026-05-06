# Report: Refresh Token Rotation + Reuse Detection

**Дата:** 2026-05-05  
**Статус:** ✅ Завершено

---

## Что сделано

### Новые файлы / классы

`InMemoryRevokedTokenRepository` в `in_memory_repositories.dart` — реализует `IRevokedTokenRepository` для тестов.

### Изменения

| Файл | Изменение |
|---|---|
| `auth_router.dart` | Добавлен `TokenRevocationService? revocationService`. `_refresh` — rotation + reuse detection |
| `aq_auth_server.dart` | `AuthServerRepos` + `revokedTokens: IRevokedTokenRepository`. `_revocationService` lazy field. Передаётся в `AuthRouter` |

### Логика `_refresh`

```
1. validateRefresh() — подпись + срок
2. isRevoked(jti)?
   → да + reason == 'token_refreshed' → revokeAllSessionTokens() + revoke session → 401 token_reuse_detected
   → да (другая причина) → 401 token_reuse_detected
3. sessionService.validate() — сессия активна
4. revokeFromClaims(oldClaims, reason: 'token_refreshed') — rotation
5. tokenIssuer.reissue() → новая пара
```

## Проверка

`dart analyze lib/` — **0 errors**

## Tech debt закрыт

TECH_DEBT.md пункт "Нет refresh token rotation / reuse detection" — **закрыт**.
