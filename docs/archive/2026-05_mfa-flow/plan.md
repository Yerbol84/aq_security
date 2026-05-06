# Plan: MFA Flow

**Дата:** 2026-05-05

---

## Шаги

1. ✅ analysis.md
2. [ ] `AqSession` + `mfaVerified: bool` (default false)
3. [ ] `AqTokenClaims` + `mfaVerified: bool` (default false)
4. [ ] `IMfaService` порт в aq_schema + модели
5. [ ] `MfaService` в aq_security — TOTP
6. [ ] `TokenIssuer` — `mfaVerified` из сессии в claims
7. [ ] `SessionService.markMfaVerified(sessionId)`
8. [ ] dart analyze 0 errors

## Критерии готовности

- После `MfaService.verify()` → `session.mfaVerified == true`
- После refresh → `claims.mfaVerified == true`
- `AccessControlEngine` получает `mfaVerified` из claims через `AccessContext`
- 0 errors в dart analyze
