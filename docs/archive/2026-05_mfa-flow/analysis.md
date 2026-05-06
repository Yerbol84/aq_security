# Analysis: MFA Flow

**Дата:** 2026-05-05

---

## Текущее состояние

- `AccessContext.mfaVerified: bool` — есть, Policy Engine его проверяет
- `AccessControlEngine._evaluateUserAttributeCondition` — умеет проверять `mfaVerified`
- `AqSession` — нет поля `mfaVerified`
- `AqTokenClaims` — нет поля `mfaVerified`
- Нет `IMfaService`, нет `MfaService`, нет механики верификации

## Проблема

Policy Engine умеет требовать MFA (`mfaVerified == true`), но:
- Сессия не хранит был ли пройден MFA
- Токен не несёт `mfaVerified`
- Нет способа пройти MFA — нет сервиса

## Решение

### Поток

```
1. Пользователь логинится → сессия создаётся с mfaVerified = false
2. Клиент вызывает MfaService.initiate(sessionId) → получает challenge (TOTP secret / QR)
3. Клиент вводит код → MfaService.verify(sessionId, code) → true/false
4. При успехе: SessionService.markMfaVerified(sessionId)
5. При следующем refresh токена: TokenIssuer включает mfaVerified=true из сессии
6. AccessControlEngine получает mfaVerified=true в AccessContext → политики проходят
```

### Что меняем

**aq_schema:**
- `AqSession` + поле `mfaVerified: bool`
- `AqTokenClaims` + поле `mfaVerified: bool`
- `IMfaService` порт + модели `MfaChallenge`, `MfaVerifyResult`

**aq_security:**
- `MfaService` — TOTP: генерация secret, QR URI, верификация кода (6-digit, 30s window)
- `TokenIssuer.issue/reissue` — брать `mfaVerified` из сессии
- `SessionService.markMfaVerified(sessionId)` — обновить сессию

### Что НЕ делаем сейчас

- HTTP endpoint — это задача сервера, не механики
- SMS/Email OTP — только TOTP (RFC 6238)
- Хранение MFA secret в БД — in-memory pending store достаточно для механики
