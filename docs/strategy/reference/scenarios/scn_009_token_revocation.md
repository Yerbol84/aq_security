# SCN-009: Отзыв токена — повторный запрос отклонён

**ID:** SCN-009  
**Тип:** Backend Flow  
**Субъект:** Аутентифицированный пользователь  
**Покрывает:** `TokenRevocationService`, `InMemoryRevokedTokenRepository`, `TokenValidator`

---

## Описание

Пользователь выходит из системы. Его access token отзывается. Повторный запрос с тем же токеном отклоняется, даже если токен ещё не истёк по времени.

---

## Предусловия

```dart
// Пользователь залогинен, имеет валидный токен
final claims = AqTokenClaims(
  sub: 'user-1',
  tid: 'tenant-1',
  email: 'alice@example.com',
  type: TokenType.access,
  iat: nowSeconds,
  exp: nowSeconds + 900,  // истекает через 15 минут
  jti: 'jti-unique-123',  // ← уникальный ID токена
  sid: 'session-1',
);
```

---

## Шаги

```dart
// 1. До отзыва — токен валиден
final revokedRepo = InMemoryRevokedTokenRepository();
final isRevoked1 = await revokedRepo.isRevoked(claims.jti);
assert(isRevoked1 == false);

// 2. Пользователь выходит → токен отзывается
await revokedRepo.revoke(AqRevokedToken(
  jti: claims.jti,
  userId: claims.sub,
  revokedAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
  expiresAt: claims.exp,  // хранить до истечения, потом можно удалить
));

// 3. После отзыва — токен невалиден
final isRevoked2 = await revokedRepo.isRevoked(claims.jti);
assert(isRevoked2 == true);

// 4. Попытка использовать отозванный токен
// В auth middleware: TokenValidator проверяет revocation list
final validator = TokenValidator(revokedTokenRepository: revokedRepo);
final validationResult = await validator.validate(encodedToken);
assert(validationResult.isValid == false);
assert(validationResult.error == 'Token has been revoked');

// 5. Другой токен того же пользователя — не затронут
final otherClaims = AqTokenClaims(
  sub: 'user-1',
  jti: 'jti-other-456',  // ← другой jti
  // ...
);
final isOtherRevoked = await revokedRepo.isRevoked(otherClaims.jti);
assert(isOtherRevoked == false);  // другой токен не отозван
```

---

## Ожидаемый результат

| Токен | Статус | Результат |
|---|---|---|
| `jti-unique-123` (до отзыва) | активен | ✅ валиден |
| `jti-unique-123` (после отзыва) | отозван | ❌ невалиден |
| `jti-other-456` (другой токен) | активен | ✅ валиден |

---

## Проверка

Отзыв работает по `jti` (уникальный ID токена), не по `userId`.  
Отзыв одного токена не влияет на другие токены того же пользователя.  
`AqRevokedToken.expiresAt` позволяет очищать устаревшие записи из хранилища.
