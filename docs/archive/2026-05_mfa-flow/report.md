# Report: MFA Flow

**Дата:** 2026-05-05  
**Статус:** ✅ Завершено

---

## Что сделано

### aq_schema

| Файл | Изменение |
|---|---|
| `models/aq_session.dart` | `mfaVerified: bool` (default false, в copyWith/fromJson/toJson) |
| `models/aq_token_claims.dart` | `mfaVerified: bool` (default false, в fromJson/toJson) |
| `interfaces/i_mfa_service.dart` | Новый порт `IMfaService` + модели `MfaChallenge`, `MfaVerifyResult`, `MfaMethod` |

### aq_security

| Файл | Изменение |
|---|---|
| `server/mfa_service.dart` | Новый `MfaService` — TOTP RFC 6238, in-memory pending store, ±1 window |
| `server/token_issuer.dart` | `issue()` и `reissue()` берут `mfaVerified` из сессии |
| `server/session_service.dart` | `markMfaVerified(sessionId)` — обновляет сессию |

## Поток

```
1. MfaService.initiate(sessionId, userId, email) → MfaChallenge (totpUri для QR)
2. Клиент сканирует QR, вводит код
3. MfaService.verify(sessionId, code) → MfaVerifyResult
4. При success: SessionService.markMfaVerified(sessionId)
5. При следующем refresh: TokenIssuer включает mfaVerified=true в claims
6. AccessControlEngine получает mfaVerified=true через AccessContext → политики проходят
```

## Проверка

- `dart analyze lib/security/` в aq_schema — **0 errors**
- `dart analyze lib/` в aq_security — **0 errors**

## Что НЕ сделано (намеренно)

- HTTP endpoint — задача сервера, не механики
- SMS/Email OTP — только TOTP
- Хранение MFA secret в БД — in-memory достаточно для механики (при рестарте сервера pending сбрасывается)
