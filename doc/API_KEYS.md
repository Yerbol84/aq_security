# API Keys Management

Полная система управления API ключами для сервисов, workers и внешних интеграций.

## Возможности

✅ **Генерация ключей с префиксами**
- `aq_live_` — production ключи
- `aq_test_` — development/testing ключи

✅ **Безопасное хранение**
- Raw ключ показывается только один раз при создании
- В БД хранится только SHA-256 hash
- Префикс (первые 14 символов) для идентификации в логах

✅ **Lifecycle управление**
- Создание с permissions
- Ротация (создание нового + отзыв старого)
- Отзыв (revoke)
- Expiration support

✅ **Tracking**
- `lastUsedAt` обновляется при каждой валидации
- История изменений (LoggedStorable)

## API Endpoints

### Создание API ключа

```http
POST /auth/api-keys
Authorization: Bearer <access_token>
Content-Type: application/json

{
  "name": "Worker Production Key",
  "permissions": ["runs:*", "graphs:read", "knowledge:read"],
  "isTest": false,
  "expiresAt": 1735689600  // optional, Unix timestamp
}
```

**Response:**
```json
{
  "id": "uuid",
  "userId": "user_id",
  "tenantId": "tenant_id",
  "name": "Worker Production Key",
  "keyPrefix": "aq_live_a1b2c3",
  "keyHash": "sha256_hash",
  "permissions": ["runs:*", "graphs:read", "knowledge:read"],
  "isActive": true,
  "createdAt": 1704067200,
  "key": "aq_live_a1b2c3d4e5f6..." // ← показывается ТОЛЬКО ОДИН РАЗ!
}
```

⚠️ **ВАЖНО:** Поле `key` содержит raw ключ и показывается только при создании. Сохраните его в безопасном месте!

### Список API ключей

```http
GET /auth/api-keys
Authorization: Bearer <access_token>
```

**Response:**
```json
{
  "keys": [
    {
      "id": "uuid",
      "name": "Worker Production Key",
      "keyPrefix": "aq_live_a1b2c3",
      "permissions": ["runs:*"],
      "isActive": true,
      "createdAt": 1704067200,
      "lastUsedAt": 1704153600
    }
  ]
}
```

### Ротация API ключа

```http
POST /auth/api-keys/{id}/rotate
Authorization: Bearer <access_token>
```

**Response:**
```json
{
  "id": "new_uuid",
  "name": "Worker Production Key (rotated)",
  "keyPrefix": "aq_live_x9y8z7",
  "permissions": ["runs:*", "graphs:read"],
  "isActive": true,
  "createdAt": 1704240000,
  "key": "aq_live_x9y8z7w6v5u4..." // ← новый ключ, показывается ТОЛЬКО ОДИН РАЗ!
}
```

Старый ключ автоматически отзывается (`isActive: false`).

### Отзыв API ключа

```http
DELETE /auth/api-keys/{id}
Authorization: Bearer <access_token>
```

**Response:** `204 No Content`

## Использование в коде

### Dart/Flutter Worker

```dart
import 'package:http/http.dart' as http;

Future<void> runWorker() async {
  final apiKey = Platform.environment['API_KEY']!; // aq_live_...

  final response = await http.post(
    Uri.parse('https://api.example.com/runs'),
    headers: {
      'Authorization': 'Bearer $apiKey',
      'Content-Type': 'application/json',
    },
    body: jsonEncode({'graph_id': 'graph_123'}),
  );

  if (response.statusCode == 200) {
    print('Run started: ${response.body}');
  }
}
```

### Python Worker

```python
import os
import requests

api_key = os.environ['API_KEY']  # aq_live_...

response = requests.post(
    'https://api.example.com/runs',
    headers={
        'Authorization': f'Bearer {api_key}',
        'Content-Type': 'application/json',
    },
    json={'graph_id': 'graph_123'}
)

if response.status_code == 200:
    print(f'Run started: {response.json()}')
```

### Node.js Service

```javascript
const axios = require('axios');

const apiKey = process.env.API_KEY; // aq_live_...

async function startRun() {
  const response = await axios.post(
    'https://api.example.com/runs',
    { graph_id: 'graph_123' },
    {
      headers: {
        'Authorization': `Bearer ${apiKey}`,
        'Content-Type': 'application/json',
      }
    }
  );

  console.log('Run started:', response.data);
}
```

## Best Practices

### 1. Используйте разные ключи для разных окружений

```bash
# Production
API_KEY=aq_live_abc123...

# Development
API_KEY=aq_test_xyz789...
```

### 2. Ротируйте ключи регулярно

Рекомендуется ротировать production ключи каждые 90 дней:

```bash
# Создать новый ключ через API
curl -X POST https://api.example.com/auth/api-keys/{old_key_id}/rotate \
  -H "Authorization: Bearer $ACCESS_TOKEN"

# Обновить переменные окружения
export API_KEY=aq_live_new_key...

# Перезапустить сервисы
systemctl restart worker
```

### 3. Храните ключи в секретах

**Kubernetes:**
```yaml
apiVersion: v1
kind: Secret
metadata:
  name: worker-api-key
type: Opaque
stringData:
  api-key: aq_live_abc123...
```

**Docker Compose:**
```yaml
services:
  worker:
    environment:
      - API_KEY=${API_KEY}
    secrets:
      - api_key

secrets:
  api_key:
    file: ./secrets/api_key.txt
```

**GitHub Actions:**
```yaml
- name: Run worker
  env:
    API_KEY: ${{ secrets.API_KEY }}
  run: dart run bin/worker.dart
```

### 4. Минимальные permissions

Давайте ключам только необходимые права:

```json
{
  "name": "Read-only Worker",
  "permissions": ["runs:read", "graphs:read"]
}
```

### 5. Мониторинг использования

Проверяйте `lastUsedAt` для выявления неиспользуемых ключей:

```bash
curl https://api.example.com/auth/api-keys \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  | jq '.keys[] | select(.lastUsedAt < (now - 2592000)) | .name'
```

## Безопасность

### Что хранится в БД

```sql
SELECT id, name, key_prefix, key_hash, is_active, last_used_at
FROM security_api_keys;

-- id: uuid
-- name: "Worker Production Key"
-- key_prefix: "aq_live_a1b2c3"  ← первые 14 символов для логов
-- key_hash: "sha256_hash..."     ← SHA-256 hash полного ключа
-- is_active: true
-- last_used_at: 1704153600
```

Raw ключ **никогда** не хранится в БД!

### Валидация

1. Проверка префикса (`aq_live_` или `aq_test_`)
2. Вычисление SHA-256 hash
3. Поиск по hash в БД
4. Проверка `isActive`
5. Проверка `expiresAt`
6. Обновление `lastUsedAt`

### Audit Trail

Все изменения API ключей логируются (LoggedStorable):

```sql
SELECT * FROM security_api_keys__log
WHERE entity_id = 'key_uuid'
ORDER BY logged_at DESC;
```

## Troubleshooting

### Ключ не работает

1. Проверьте префикс: `aq_live_` или `aq_test_`
2. Проверьте что ключ активен: `isActive: true`
3. Проверьте expiration: `expiresAt` не истек
4. Проверьте permissions для операции

### Ключ был скомпрометирован

Немедленно отзовите ключ:

```bash
curl -X DELETE https://api.example.com/auth/api-keys/{key_id} \
  -H "Authorization: Bearer $ACCESS_TOKEN"
```

Создайте новый ключ и обновите все сервисы.

### Потерян raw ключ

Raw ключ показывается только один раз при создании. Если потеряли — создайте новый через ротацию:

```bash
curl -X POST https://api.example.com/auth/api-keys/{old_key_id}/rotate \
  -H "Authorization: Bearer $ACCESS_TOKEN"
```

## Тестирование

Unit тесты: `test/unit/api_key_service_test.dart`

```bash
cd pkgs/aq_security
flutter test test/unit/api_key_service_test.dart
```

Все 13 тестов должны пройти успешно ✅
