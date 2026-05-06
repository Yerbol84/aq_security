# SCN-010: Batch проверка прав + шифрование полей

**ID:** SCN-010  
**Тип:** Backend Flow  
**Субъект:** Data layer при записи чувствительных данных  
**Покрывает:** `AccessControlEngine.canBatch`, `AqVaultSecurityProtocol.encryptSensitiveFields`, `FieldEncryptionService`

---

## Описание

UI запрашивает сразу несколько прав одним вызовом (batch). Data layer при записи пользовательских данных шифрует чувствительные поля перед сохранением.

---

## Часть 1: Batch проверка прав

### Предусловия

```dart
// Пользователь с ролью editor
// editor: ['projects:read', 'projects:write', 'graphs:read', 'graphs:write']
```

### Шаги

```dart
// UI запрашивает все нужные права одним вызовом
final results = await engine.canBatch(
  'user-1',
  [
    'projects:read',
    'projects:write',
    'projects:delete',
    'graphs:read',
    'users:manage',
  ],
);

// Проверить результаты
assert(results['projects:read'] == true);    // есть у editor
assert(results['projects:write'] == true);   // есть у editor
assert(results['projects:delete'] == false); // нет у editor
assert(results['graphs:read'] == true);      // есть у editor
assert(results['users:manage'] == false);    // нет у editor

// Роли загружаются ОДИН РАЗ для всего batch — не N раз
// Это ключевое преимущество canBatch vs N вызовов canAsync
```

---

## Часть 2: Шифрование чувствительных полей

### Предусловия

```dart
final protocol = AqVaultSecurityProtocol(
  introspectionEndpoint: 'http://auth:8080/introspect',
  encryptionKey: 'test-key-32-bytes-exactly-here!!',
  encryptionConfigs: {
    'users': EncryptionConfig(
      encryptedFields: ['phone', 'ssn', 'address'],
    ),
  },
);
```

### Шаги

```dart
final rawData = {
  'id': 'user-1',
  'email': 'alice@example.com',  // не шифруется
  'phone': '+1-555-0100',        // шифруется
  'ssn': '123-45-6789',          // шифруется
  'address': '123 Main St',      // шифруется
};

// 1. Шифрование перед записью
final encrypted = await protocol.encryptSensitiveFields(
  claims: claims,
  collection: 'users',
  data: rawData,
);

assert(encrypted['email'] == 'alice@example.com');  // не изменилось
assert(encrypted['phone'] != '+1-555-0100');         // зашифровано
assert(encrypted['ssn'] != '123-45-6789');           // зашифровано
assert(encrypted['phone'] is String);                // base64 строка

// 2. Расшифровка при чтении
final decrypted = await protocol.decryptSensitiveFields(
  claims: claims,
  collection: 'users',
  data: encrypted,
);

assert(decrypted['phone'] == '+1-555-0100');   // восстановлено
assert(decrypted['ssn'] == '123-45-6789');     // восстановлено

// 3. Коллекция без конфига — данные не трогаются
final unchanged = await protocol.encryptSensitiveFields(
  claims: claims,
  collection: 'projects',  // нет EncryptionConfig для projects
  data: rawData,
);
assert(unchanged == rawData);  // данные не изменились
```

---

## Ожидаемый результат

### Batch:
| Право | Результат |
|---|---|
| `projects:read` | ✅ true |
| `projects:write` | ✅ true |
| `projects:delete` | ❌ false |
| `graphs:read` | ✅ true |
| `users:manage` | ❌ false |

### Шифрование:
| Поле | После encrypt | После decrypt |
|---|---|---|
| `email` | без изменений | без изменений |
| `phone` | зашифровано (AES-256-GCM) | `+1-555-0100` |
| `ssn` | зашифровано | `123-45-6789` |

---

## Проверка

`canBatch` загружает роли и права один раз — эффективнее N вызовов `canAsync`.  
`FieldEncryptionService` использует AES-256-GCM. Коллекции без `EncryptionConfig` не затрагиваются.
