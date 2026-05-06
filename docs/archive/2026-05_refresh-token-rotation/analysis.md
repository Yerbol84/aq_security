# Analysis: Refresh Token Rotation + Reuse Detection

**Дата:** 2026-05-05

---

## Текущее состояние

`POST /auth/refresh` в `auth_router.dart`:

```dart
Future<Response> _refresh(Request req) async {
  // 1. Валидирует refresh token (подпись + срок)
  // 2. Проверяет сессию
  // 3. Выдаёт новую пару токенов через tokenIssuer.reissue()
  // ❌ НЕ отзывает старый refresh token
  // ❌ НЕ проверяет был ли refresh token уже использован
}
```

`TokenRevocationService` уже реализован полностью:
- `revokeFromClaims(claims, reason)` — отозвать конкретный token
- `revokeAllSessionTokens(sessionId, reason)` — отозвать все токены сессии
- `isRevoked(jti)` — проверить статус

`TokenValidator.validateRefresh()` проверяет подпись и срок, но **не проверяет revocation list**.

`AuthRouter` не получает `TokenRevocationService` в конструкторе.

---

## Проблема

Если refresh token утёк:
- Атакующий может использовать его неограниченно пока не истечёт срок
- Легитимный пользователь тоже использует тот же токен — оба получают новые access tokens
- Нет способа обнаружить что токен используется дважды

---

## Решение

### Refresh Token Rotation

При каждом успешном `/refresh`:
1. Проверить что refresh token не в revocation list
2. Отозвать старый refresh token (`reason: token_refreshed`)
3. Выдать новую пару (access + refresh)

### Reuse Detection

Если refresh token уже отозван с причиной `token_refreshed` — значит кто-то пытается использовать старый токен. Это признак компрометации:
1. Отозвать ВСЕ токены сессии
2. Вернуть 401 с кодом `token_reuse_detected`

---

## Что нужно изменить

1. `AuthRouter` — добавить `TokenRevocationService` в конструктор
2. `_refresh` handler — добавить rotation + reuse detection логику
3. `TokenValidator` — добавить проверку revocation в `validateRefresh()` (опционально, можно в handler)
4. `AQAuthServer` — передать `TokenRevocationService` в `AuthRouter`
5. `InMemoryVaultSecurityProtocol` — добавить `IRevokedTokenRepository` для тестов

---

## Что уже есть и не нужно создавать

- ✅ `TokenRevocationService` — полная реализация
- ✅ `IRevokedTokenRepository` с `revokeAllForSession()`
- ✅ `RevocationReasons.tokenRefreshed` — константа
- ✅ `AqRevokedToken` модель
- ✅ `InMemoryRevokedTokenRepository` для тестов
