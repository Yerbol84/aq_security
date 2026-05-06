# Plan: Refresh Token Rotation + Reuse Detection

**Дата:** 2026-05-05

---

## Шаги

### 1. `AuthRouter` — добавить `TokenRevocationService`
- Добавить `revocationService` в конструктор (опциональный — для обратной совместимости)
- В `_refresh`: проверить revocation → rotation → reuse detection

### 2. `_refresh` handler — новая логика
```
incoming refresh token
  → validateRefresh() — подпись + срок
  → isRevoked(jti)?
      → если да: проверить причину
          → если 'token_refreshed': revokeAllSessionTokens() → 401 reuse_detected
          → иначе: 401 token_revoked
      → если нет: продолжить
  → revokeFromClaims(oldRefreshClaims, reason: 'token_refreshed')
  → tokenIssuer.reissue() → новая пара
  → вернуть новые токены
```

### 3. `AQAuthServer` — передать `TokenRevocationService`
- Создать `TokenRevocationService` из `IRevokedTokenRepository`
- Передать в `AuthRouter`

### 4. Проверка — dart analyze 0 errors

## Критерии готовности

- Старый refresh token отзывается при каждом `/refresh`
- Повторное использование отозванного refresh token → 401 + отзыв всей сессии
- 0 errors в dart analyze
