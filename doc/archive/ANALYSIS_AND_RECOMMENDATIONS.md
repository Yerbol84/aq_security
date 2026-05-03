# Анализ и рекомендации по системе безопасности AQ Studio

**Дата:** 2026-04-07
**Автор:** Claude (Sonnet 4)
**Статус:** Готово к реализации

---

## 🎯 Executive Summary

После детального изучения проекта могу констатировать:

### ✅ Хорошие новости
1. **Архитектура уже правильная** — принцип тонкого клиента соблюден
2. **Модели готовы на 90%** — все основные сущности реализованы
3. **Клиент-сервер разделение работает** — exports правильно организованы
4. **dart_vault интеграция продумана** — все готово для подключения
5. **Базовая функциональность есть** — JWT, OAuth2, sessions, API keys

### ⚠️ Что требует внимания
1. **Data Service не подключен** — нужна интеграция с PostgreSQL
2. **Docker stack неполный** — отсутствует auth service в compose
3. **RBAC базовый** — нужны wildcards, иерархия, временные роли
4. **Нет тестов** — критично для production
5. **Нет документации** — нужна для команды

### 🚀 Оценка готовности
- **Архитектура:** 95% ✅
- **Код:** 70% ⚠️
- **Тесты:** 0% ❌
- **Документация:** 20% ⚠️
- **Production Ready:** 60% ⚠️

**Вывод:** Система на правильном пути, но требует 2-3 недели доработки до production.

---

## 📊 Детальный анализ

### 1. Архитектура ✅ Отлично

**Что сделано правильно:**

```
✅ Принцип тонкого клиента соблюден
✅ Разделение client/server exports
✅ Единое окно: AQSecurityClient.init() → AQSecurityService
✅ Интеграция с dart_vault через RemoteVaultStorage
✅ Multi-tenancy на уровне данных
✅ JWT + Refresh tokens
✅ Stream<SecurityState> для реактивности
```

**Архитектурные решения соответствуют лучшим практикам:**
- Auth0/Okta паттерн (разделение auth/data services)
- AWS IAM паттерн (resource-based permissions)
- Stripe паттерн (API keys с префиксами)
- Google Cloud паттерн (service accounts)

**Рекомендация:** Архитектура не требует изменений, только доработки.

---

### 2. Модели (aq_schema/security) ✅ Почти готово

**Что есть:**
```dart
✅ AqUser — пользователи (человек/сервис)
✅ AqTenant — организации/компании
✅ AqProfile — расширенные профили
✅ AqSession — сессии с lifecycle
✅ AqTokenClaims — JWT payload
✅ AqRole — роли с permissions
✅ AqUserRole — назначение ролей
✅ AqApiKey — API ключи с hash
```

**Что нужно добавить:**

#### 2.1. Система Credentials (полиморфная)
```dart
// Базовый интерфейс
abstract class Credentials {
  String get type; // discriminator для JSON
  Map<String, dynamic> toJson();
}

// Реализации
class EmailPasswordCredentials extends Credentials {
  final String email;
  final String password;
  String get type => 'email_password';
}

class GoogleOAuthCredentials extends Credentials {
  final String code;
  final String redirectUri;
  String get type => 'google_oauth';
}

class ApiKeyCredentials extends Credentials {
  final String apiKey;
  String get type => 'api_key';
}

class TokenCredentials extends Credentials {
  final String token; // для service accounts
  String get type => 'token';
}
```

**Зачем:** Единый интерфейс для всех способов аутентификации. Сервер получает Credentials и сам определяет тип по discriminator.

#### 2.2. Модель Permission (опционально)
```dart
class AqPermission {
  final String id;
  final String resource;  // 'projects', 'users', 'agents'
  final String action;    // 'read', 'write', 'delete', '*'
  final String? scope;    // 'tenant', 'project', null

  String get key => scope != null
    ? '$resource:$action:$scope'
    : '$resource:$action';
}
```

**Зачем:** Гранулярное управление правами. Сейчас permissions — это просто List<String>, что работает, но менее структурировано.

**Рекомендация:** Можно оставить как есть (List<String>), но добавить валидацию формата.

#### 2.3. Модель Resource (опционально)
```dart
class AqResource {
  final String id;
  final String type;      // 'project', 'workflow', 'agent'
  final String ownerId;
  final String tenantId;
  final List<AqResourceGrant> grants;
}

class AqResourceGrant {
  final String userId;
  final List<String> permissions;
  final int? expiresAt;
}
```

**Зачем:** Управление доступом к конкретным ресурсам (проектам, workflow и т.д.).

**Рекомендация:** Можно отложить на Phase 2, сейчас не критично.

---

### 3. RBAC система ⚠️ Требует расширения

**Что работает:**
```dart
✅ Базовые роли (AqRole)
✅ Назначение ролей (AqUserRole)
✅ Permissions как List<String>
✅ Проверка hasPermission() с wildcard
```

**Что нужно добавить:**

#### 3.1. Иерархия ролей
```dart
class AqRole {
  // ... существующие поля
  final String? parentRoleId;  // наследование от другой роли
  final RoleLevel level;       // platform/tenant/project
}

enum RoleLevel {
  platform,  // tenantId = null, глобальные роли
  tenant,    // tenantId != null, роли внутри тенанта
  project,   // привязаны к конкретному проекту
}
```

#### 3.2. Временные роли
```dart
class AqUserRole {
  // ... существующие поля
  final int? expiresAt;  // ✅ УЖЕ ЕСТЬ!
}
```

**Отлично!** Временные роли уже поддерживаются.

#### 3.3. Улучшенная проверка permissions
```dart
// В TokenIssuer при создании JWT
Future<List<String>> _flattenPermissions(List<String> roleIds) async {
  final perms = <String>{};

  for (final roleId in roleIds) {
    final role = await _roles.findById(roleId);
    if (role == null) continue;

    // Добавить permissions роли
    perms.addAll(role.permissions);

    // Рекурсивно добавить permissions родительских ролей
    if (role.parentRoleId != null) {
      final parentPerms = await _flattenPermissions([role.parentRoleId!]);
      perms.addAll(parentPerms);
    }
  }

  return perms.toList();
}
```

**Рекомендация:** Реализовать иерархию ролей и кэширование permissions в JWT.

---

### 4. API ключи ⚠️ Требует доработки

**Что работает:**
```dart
✅ Модель AqApiKey
✅ Хранение hash (SHA-256)
✅ Prefix для UI
✅ Permissions для ключей
✅ isActive флаг
```

**Что нужно добавить:**

#### 4.1. Генерация с префиксами
```dart
class ApiKeyService {
  String generateKey({required KeyEnvironment env}) {
    final prefix = env == KeyEnvironment.live ? 'aq_live_' : 'aq_test_';
    final random = _generateSecureRandom(32); // 32 bytes = 64 hex chars
    return '$prefix$random';
  }
}

enum KeyEnvironment { live, test }
```

#### 4.2. Показ raw ключа только при создании
```dart
class CreateApiKeyResponse {
  final AqApiKey apiKey;      // без raw ключа
  final String rawKey;         // показывается только один раз
  final String warning;        // "Save this key now. You won't see it again."
}
```

#### 4.3. Ротация ключей
```dart
Future<CreateApiKeyResponse> rotateApiKey(String oldKeyId) async {
  // 1. Создать новый ключ с теми же permissions
  // 2. Деактивировать старый ключ (не удалять!)
  // 3. Вернуть новый raw ключ
}
```

#### 4.4. Tracking lastUsedAt
```dart
// В AuthMiddleware при валидации API ключа
Future<void> _trackApiKeyUsage(String keyHash) async {
  final key = await _apiKeys.findByHash(keyHash);
  if (key != null) {
    await _apiKeys.save(
      key.copyWith(lastUsedAt: DateTime.now().millisecondsSinceEpoch ~/ 1000),
      actorId: 'system',
    );
  }
}
```

**Рекомендация:** Реализовать все 4 пункта для production-ready API keys.

---

### 5. Data Service интеграция ❌ Критично

**Текущее состояние:**
```
❌ aq_auth_data_service существует, но не подключен к PostgreSQL
❌ Нет регистрации security доменов в VaultRegistry
❌ Нет Dockerfile
❌ Не добавлен в docker-compose
```

**Что нужно сделать:**

#### 5.1. Обновить bin/main.dart
```dart
// server_apps/aq_auth_data_service/bin/main.dart
import 'package:postgres/postgres.dart';
import 'package:dart_vault/server.dart';
import 'package:aq_schema/security/security.dart';

void main() async {
  // 1. Подключиться к PostgreSQL
  final connection = await Connection.open(
    Endpoint(
      host: Platform.environment['PG_HOST'] ?? 'localhost',
      database: Platform.environment['PG_DB'] ?? 'aq_auth',
      username: Platform.environment['PG_USER'] ?? 'aq',
      password: Platform.environment['PG_PASSWORD'] ?? 'aq_secret',
    ),
  );

  // 2. Создать VaultRegistry
  final registry = VaultRegistry(
    storageFactory: (tenantId) => PostgresVaultStorage(
      connection: connection,
      tenantId: tenantId,
    ),
    deployer: PostgresSchemaDeployer(pool: connection),
  );

  // 3. Зарегистрировать security домены
  for (final domain in AqSecurityDomains.all) {
    registry.register(DomainRegistration(
      collection: domain.collection,
      mode: domain.mode,
      fromMap: domain.fromMap,
      indexes: domain.indexes,
    ));
  }

  // 4. Deploy схемы
  await registry.deploy();

  // 5. Запустить HTTP сервер
  final handler = createVaultHandler(registry);
  await io.serve(handler, '0.0.0.0', 8090);

  print('✅ Auth Data Service running on :8090');
}
```

#### 5.2. Создать Dockerfile
```dockerfile
FROM dart:stable AS build
WORKDIR /app
COPY pubspec.yaml pubspec.lock ./
COPY pkgs/ ./pkgs/
RUN dart pub get
COPY server_apps/aq_auth_data_service/ ./server_apps/aq_auth_data_service/
RUN dart compile exe server_apps/aq_auth_data_service/bin/main.dart -o server

FROM scratch
COPY --from=build /runtime/ /
COPY --from=build /app/server /app/server
EXPOSE 8090
ENTRYPOINT ["/app/server"]
```

#### 5.3. Обновить docker-compose.yml
```yaml
services:
  postgres:
    # ... существующая конфигурация

  auth_data_service:
    build:
      context: ../..
      dockerfile: server_apps/aq_auth_data_service/Dockerfile
    container_name: aq_auth_data_service
    depends_on:
      postgres:
        condition: service_healthy
    environment:
      PG_HOST: postgres
      PG_PORT: 5432
      PG_DB: ${POSTGRES_DB:-aq_auth}
      PG_USER: ${POSTGRES_USER:-aq}
      PG_PASSWORD: ${POSTGRES_PASSWORD:-aq_secret}
      PORT: 8090
    ports:
      - "8090:8090"
    networks:
      - aq_auth_network

  auth_service:
    build:
      context: ../..
      dockerfile: server_apps/aq_auth_service/Dockerfile
    container_name: aq_auth_service
    depends_on:
      - auth_data_service
    environment:
      AUTH_DATA_SERVICE_URL: http://auth_data_service:8090
      AUTH_ENDPOINT: http://localhost:8080
      JWT_SECRET: ${JWT_SECRET:-your-secret-key-change-in-production}
      GOOGLE_CLIENT_ID: ${GOOGLE_CLIENT_ID}
      GOOGLE_CLIENT_SECRET: ${GOOGLE_CLIENT_SECRET}
      PORT: 8080
    ports:
      - "8080:8080"
    networks:
      - aq_auth_network
```

**Рекомендация:** Это критический приоритет. Без этого система не работает.

---

### 6. Интеграция с Data Layer ❌ Критично

**Проблема:** Основной data layer (aq_studio_data_service) не защищен.

**Решение:** Добавить AuthMiddleware в dart_vault.

#### 6.1. Создать AuthMiddleware для VaultRegistry
```dart
// pkgs/dart_vault_package/lib/src/server/auth_middleware.dart
class VaultAuthMiddleware {
  VaultAuthMiddleware({
    required this.authServiceUrl,
    required this.publicCollections,
  });

  final String authServiceUrl;
  final List<String> publicCollections;

  Future<Handler> wrap(Handler handler) async {
    return (Request request) async {
      // Пропустить публичные коллекции
      final collection = request.url.queryParameters['collection'];
      if (collection != null && publicCollections.contains(collection)) {
        return handler(request);
      }

      // Извлечь токен
      final authHeader = request.headers['authorization'];
      if (authHeader == null || !authHeader.startsWith('Bearer ')) {
        return Response.unauthorized('Missing or invalid token');
      }

      final token = authHeader.substring(7);

      // Валидировать через auth service
      final response = await http.post(
        Uri.parse('$authServiceUrl/auth/validate'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'token': token}),
      );

      if (response.statusCode != 200) {
        return Response.unauthorized('Invalid token');
      }

      final result = ValidateTokenResponse.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>,
      );

      if (!result.valid || result.claims == null) {
        return Response.unauthorized('Token validation failed');
      }

      // Добавить claims в request context
      return handler(
        request.change(context: {'claims': result.claims}),
      );
    };
  }
}
```

#### 6.2. Использовать в VaultRegistry
```dart
// В createVaultHandler
Handler createVaultHandler(
  VaultRegistry registry, {
  VaultAuthMiddleware? authMiddleware,
}) {
  var handler = _buildHandler(registry);

  if (authMiddleware != null) {
    handler = authMiddleware.wrap(handler);
  }

  return handler;
}
```

#### 6.3. Автоматическая фильтрация по tenantId
```dart
// В VaultRegistry.dispatch
Future<dynamic> dispatch({
  required String collection,
  required String operation,
  required Map<String, dynamic> args,
  required String tenantId,
  AqTokenClaims? claims, // из middleware
}) async {
  // Если есть claims, использовать tenantId из токена
  final effectiveTenantId = claims?.tid ?? tenantId;

  // Проверить permissions
  if (claims != null) {
    final requiredPerm = _getRequiredPermission(collection, operation);
    if (!claims.hasPermission(requiredPerm)) {
      throw Exception('Permission denied: $requiredPerm');
    }
  }

  // ... остальная логика
}
```

**Рекомендация:** Реализовать после завершения auth service.

---

### 7. Тесты ❌ Критично

**Текущее состояние:** Тестов нет вообще.

**Что нужно:**

#### 7.1. Unit тесты моделей
```dart
// test/models/aq_user_test.dart
test('AqUser serialization', () {
  final user = AqUser(...);
  final json = user.toJson();
  final restored = AqUser.fromJson(json);
  expect(restored, equals(user));
});
```

#### 7.2. Интеграционные тесты auth service
```dart
// test/integration/auth_service_test.dart
group('Auth Service', () {
  test('login with Google OAuth', () async {
    final response = await authService.loginWithGoogle(...);
    expect(response.user, isNotNull);
    expect(response.tokens.accessToken, isNotEmpty);
  });

  test('token refresh', () async {
    final newTokens = await authService.refresh(refreshToken);
    expect(newTokens.accessToken, isNotEmpty);
  });
});
```

#### 7.3. E2E тесты
```dart
// test/e2e/full_flow_test.dart
test('Full auth flow', () async {
  // 1. Login
  final auth = await client.loginWithGoogle(...);

  // 2. Access protected resource
  final projects = await dataService.getProjects(auth.tokens.accessToken);
  expect(projects, isNotEmpty);

  // 3. Logout
  await client.logout();

  // 4. Verify token is invalid
  expect(() => dataService.getProjects(auth.tokens.accessToken), throwsA(isA<UnauthorizedException>()));
});
```

**Рекомендация:** Минимум 80% покрытие критичных путей.

---

### 8. Документация ⚠️ Требует внимания

**Что нужно:**

1. **SECURITY_ARCHITECTURE.md** — полная архитектура
2. **SECURITY_GUIDE.md** — руководство использования
3. **API_REFERENCE.md** — справочник API
4. **DEPLOYMENT.md** — инструкции по развертыванию
5. **BEST_PRACTICES.md** — лучшие практики

**Рекомендация:** Создать после завершения реализации.

---

## 🎯 Приоритеты реализации

### 🔴 Критический приоритет (Неделя 1)
1. **Интеграция aq_auth_data_service** — без этого ничего не работает
2. **Docker stack** — нужен для тестирования
3. **Базовые тесты** — для проверки работоспособности

### 🟡 Высокий приоритет (Неделя 2)
4. **Система Credentials** — для унификации аутентификации
5. **Расширение RBAC** — wildcards, иерархия
6. **Улучшение API ключей** — префиксы, ротация, tracking
7. **Интеграция с Data Layer** — защита основного слоя данных

### 🟢 Средний приоритет (Неделя 3)
8. **Полное тестирование** — 80%+ покрытие
9. **Документация** — для команды
10. **Production readiness** — security audit, monitoring

---

## 💡 Ключевые рекомендации

### 1. Архитектура
✅ **Оставить как есть** — архитектура правильная, не требует изменений.

### 2. Модели
⚠️ **Добавить Credentials** — критично для унификации.
✅ **Permission/Resource** — можно отложить на Phase 2.

### 3. RBAC
⚠️ **Добавить иерархию ролей** — важно для гибкости.
⚠️ **Кэшировать permissions в JWT** — важно для производительности.

### 4. API ключи
⚠️ **Реализовать префиксы и ротацию** — важно для production.

### 5. Data Service
🔴 **Критично** — без этого система не работает.

### 6. Data Layer защита
🔴 **Критично** — без этого данные не защищены.

### 7. Тесты
🔴 **Критично** — без тестов нельзя в production.

### 8. Документация
🟡 **Важно** — нужна для команды.

---

## 📈 Оценка трудозатрат

### Реалистичная оценка
- **Неделя 1:** Data Service + Docker + Базовые тесты (40 часов)
- **Неделя 2:** Credentials + RBAC + API keys + Data Layer (40 часов)
- **Неделя 3:** Тестирование + Документация + Production (40 часов)

**Итого:** 120 часов (3 недели full-time или 6 недель part-time)

### Минимальная версия (MVP)
Если нужно быстрее, можно сделать MVP за 1 неделю:
- Data Service интеграция
- Docker stack
- Базовые тесты
- Минимальная документация

Остальное доделать потом.

---

## ✅ Заключение

### Что хорошо
1. ✅ Архитектура правильная
2. ✅ Модели почти готовы
3. ✅ Клиент-сервер работает
4. ✅ Базовая функциональность есть

### Что нужно доделать
1. 🔴 Data Service интеграция (критично)
2. 🔴 Docker stack (критично)
3. 🔴 Тесты (критично)
4. 🟡 RBAC расширение (важно)
5. 🟡 API keys улучшение (важно)
6. 🟡 Документация (важно)

### Итоговая оценка
**Система на 70% готова к production.**

С учетом правильной архитектуры и хорошей базы, **2-3 недели работы** приведут систему к полной готовности.

**Рекомендую начать с критичных задач** (Data Service + Docker + Тесты), а затем двигаться по приоритетам.

---

**Готов приступить к реализации!** 🚀
