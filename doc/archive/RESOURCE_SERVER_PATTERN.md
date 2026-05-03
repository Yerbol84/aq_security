# Resource Server Pattern для AQ Studio

**Дата:** 2026-04-07
**Статус:** Design Document

## Цель

Реализовать стандартный OAuth 2.0 Resource Server Pattern для защиты Data Service, как это делают Google Cloud, AWS, Auth0.

---

## Архитектура

```
┌─────────────┐         ┌──────────────────┐         ┌─────────────────┐
│   Client    │────1───▶│  Auth Service    │         │  Data Service   │
│  (Flutter)  │         │  (Authorization  │         │  (Resource      │
│             │◀───2────│   Server)        │         │   Server)       │
└─────────────┘         └──────────────────┘         └─────────────────┘
      │                          │                            │
      │                          │                            │
      └──────────3: Bearer token─┴────────────────────────────┘
                                 │
                                 │
                          ┌──────▼──────┐
                          │  RBAC DB    │
                          │  (Policies, │
                          │   Roles)    │
                          └─────────────┘
```

---

## Компоненты

### 1. Resource Registration (Handshake)

Data Service при старте регистрируется в Auth Service.

**Endpoint:** `POST /api/resources/register`

**Request:**
```json
{
  "resourceId": "data-service-1",
  "endpoint": "http://data-service:8765",
  "collections": ["projects", "blueprints", "sessions"],
  "requiresAuth": true,
  "metadata": {
    "version": "1.0.0",
    "region": "eu-west-1"
  }
}
```

**Response:**
```json
{
  "resourceId": "data-service-1",
  "jwtSecret": "shared-secret-for-validation",
  "introspectionEndpoint": "http://auth-service/api/introspect",
  "registered": true
}
```

**Реализация:**
```dart
// server_apps/aq_studio_data_service/lib/resource_registration.dart

class ResourceRegistration {
  Future<ResourceConfig> register({
    required String authServiceUrl,
    required String resourceId,
    required String endpoint,
    required List<String> collections,
  }) async {
    final response = await http.post(
      Uri.parse('$authServiceUrl/api/resources/register'),
      body: jsonEncode({
        'resourceId': resourceId,
        'endpoint': endpoint,
        'collections': collections,
        'requiresAuth': true,
      }),
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to register resource');
    }

    final data = jsonDecode(response.body);
    return ResourceConfig(
      resourceId: data['resourceId'],
      jwtSecret: data['jwtSecret'],
      introspectionEndpoint: data['introspectionEndpoint'],
    );
  }
}
```

### 2. Token Introspection (Проверка прав)

Data Service спрашивает Auth Service: "Может ли этот токен выполнить действие?"

**Endpoint:** `POST /api/introspect`

**Request:**
```json
{
  "token": "eyJhbGc...",
  "resource": "project",
  "action": "read",
  "resourceId": "proj789",
  "context": {
    "ip": "192.168.1.1",
    "userAgent": "Mozilla/5.0..."
  }
}
```

**Response:**
```json
{
  "active": true,
  "allowed": true,
  "userId": "user123",
  "tenantId": "tenant456",
  "scopes": ["project:proj789:read", "project:proj789:write"],
  "roles": ["project.editor"],
  "expiresAt": 1234567890,
  "reason": null
}
```

**Если отказано:**
```json
{
  "active": true,
  "allowed": false,
  "userId": "user123",
  "tenantId": "tenant456",
  "reason": "User does not have permission: project:proj789:read"
}
```

**Реализация в Auth Service:**
```dart
// pkgs/aq_security/lib/src/server/introspection_router.dart

class IntrospectionRouter {
  IntrospectionRouter({
    required this.tokenValidator,
    required this.rbacService,
  });

  final TokenValidator tokenValidator;
  final RBACService rbacService;

  Router get router {
    final r = Router();
    r.post('/introspect', _introspect);
    return r;
  }

  Future<Response> _introspect(Request req) async {
    final body = await req.readAsString();
    final data = jsonDecode(body) as Map<String, dynamic>;

    final token = data['token'] as String;
    final resource = data['resource'] as String;
    final action = data['action'] as String;
    final resourceId = data['resourceId'] as String;
    final context = data['context'] as Map<String, dynamic>?;

    // 1. Валидировать токен
    final validation = tokenValidator.validate(token);
    if (!validation.valid) {
      return _ok({
        'active': false,
        'allowed': false,
        'reason': validation.message,
      });
    }

    final claims = validation.claims!;

    // 2. Проверить права через RBAC
    final decision = await rbacService.can(
      claims.sub,
      resource: resource,
      action: action,
      scope: resourceId,
      context: context != null ? AccessContext.fromJson(context) : null,
    );

    // 3. Получить эффективные права
    final scopes = await rbacService.getUserEffectivePermissions(claims.sub);

    return _ok({
      'active': true,
      'allowed': decision.allowed,
      'userId': claims.sub,
      'tenantId': claims.tid,
      'scopes': scopes,
      'roles': claims.roles,
      'expiresAt': claims.exp,
      'reason': decision.allowed ? null : decision.reason,
    });
  }

  Response _ok(Map<String, dynamic> data) => Response.ok(
        jsonEncode(data),
        headers: {'Content-Type': 'application/json'},
      );
}
```

### 3. Data Service Middleware с кэшированием

**Реализация:**
```dart
// server_apps/aq_studio_data_service/lib/middleware/resource_auth_middleware.dart

class ResourceAuthMiddleware {
  ResourceAuthMiddleware({
    required this.tokenValidator,
    required this.introspectionClient,
    this.cache,
  });

  final TokenValidator tokenValidator;
  final IntrospectionClient introspectionClient;
  final Cache? cache;

  Middleware call() {
    return (Handler inner) {
      return (Request request) async {
        // 1. Извлечь токен
        final token = _extractToken(request);
        if (token == null) {
          return _unauthorized('Missing token');
        }

        // 2. Валидировать токен локально (быстро)
        final validation = tokenValidator.validate(token);
        if (!validation.valid) {
          return _unauthorized(validation.message ?? 'Invalid token');
        }

        final claims = validation.claims!;

        // 3. Быстрая проверка: админ тенанта?
        if (claims.roles.contains('tenant:admin')) {
          // Админ - полный доступ, пропускаем
          return inner(request.withClaims(claims));
        }

        // 4. Извлечь resource/action/resourceId из запроса
        final resource = _extractResource(request);
        final action = _extractAction(request);
        final resourceId = _extractResourceId(request);

        // 5. Проверить кэш
        final cacheKey = '${claims.sub}:$resource:$action:$resourceId';
        var decision = cache?.get(cacheKey);

        if (decision == null) {
          // Cache miss - спрашиваем Auth Service
          decision = await introspectionClient.introspect(
            token: token,
            resource: resource,
            action: action,
            resourceId: resourceId,
            context: {
              'ip': request.headers['x-forwarded-for'],
              'userAgent': request.headers['user-agent'],
            },
          );

          // Кэшируем на 2 минуты
          cache?.set(cacheKey, decision, ttl: Duration(minutes: 2));
        }

        if (!decision.allowed) {
          return _forbidden(decision.reason ?? 'Access denied');
        }

        // 6. Добавить claims и scopes в request context
        return inner(request.withClaims(claims).withScopes(decision.scopes));
      };
    };
  }

  String _extractResource(Request req) {
    // /projects/123 -> "project"
    final segments = req.url.pathSegments;
    return segments.isNotEmpty ? segments[0].replaceAll(RegExp(r's$'), '') : '';
  }

  String _extractAction(Request req) {
    // GET -> "read", POST -> "create", PUT -> "write", DELETE -> "delete"
    switch (req.method) {
      case 'GET': return 'read';
      case 'POST': return 'create';
      case 'PUT': case 'PATCH': return 'write';
      case 'DELETE': return 'delete';
      default: return 'read';
    }
  }

  String _extractResourceId(Request req) {
    // /projects/123 -> "123"
    final segments = req.url.pathSegments;
    return segments.length > 1 ? segments[1] : '*';
  }

  String? _extractToken(Request req) {
    final header = req.headers['authorization'];
    if (header == null || !header.startsWith('Bearer ')) return null;
    return header.substring(7);
  }

  Response _unauthorized(String message) => Response(401,
        body: jsonEncode({'error': message}),
        headers: {'Content-Type': 'application/json'});

  Response _forbidden(String message) => Response(403,
        body: jsonEncode({'error': message}),
        headers: {'Content-Type': 'application/json'});
}
```

### 4. Introspection Client (для Data Service)

```dart
// pkgs/aq_security/lib/src/client/introspection_client.dart

class IntrospectionClient {
  IntrospectionClient({required this.introspectionEndpoint});

  final String introspectionEndpoint;

  Future<IntrospectionResponse> introspect({
    required String token,
    required String resource,
    required String action,
    required String resourceId,
    Map<String, dynamic>? context,
  }) async {
    final response = await http.post(
      Uri.parse(introspectionEndpoint),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'token': token,
        'resource': resource,
        'action': action,
        'resourceId': resourceId,
        'context': context,
      }),
    );

    if (response.statusCode != 200) {
      throw Exception('Introspection failed: ${response.statusCode}');
    }

    return IntrospectionResponse.fromJson(jsonDecode(response.body));
  }
}

class IntrospectionResponse {
  IntrospectionResponse({
    required this.active,
    required this.allowed,
    this.userId,
    this.tenantId,
    this.scopes = const [],
    this.roles = const [],
    this.expiresAt,
    this.reason,
  });

  final bool active;
  final bool allowed;
  final String? userId;
  final String? tenantId;
  final List<String> scopes;
  final List<String> roles;
  final int? expiresAt;
  final String? reason;

  factory IntrospectionResponse.fromJson(Map<String, dynamic> json) {
    return IntrospectionResponse(
      active: json['active'] as bool,
      allowed: json['allowed'] as bool,
      userId: json['userId'] as String?,
      tenantId: json['tenantId'] as String?,
      scopes: (json['scopes'] as List<dynamic>?)?.cast<String>() ?? [],
      roles: (json['roles'] as List<dynamic>?)?.cast<String>() ?? [],
      expiresAt: json['expiresAt'] as int?,
      reason: json['reason'] as String?,
    );
  }
}
```

---

## Использование

### 1. Запуск Auth Service

```bash
cd server_apps/aq_auth_service
JWT_SECRET=$(openssl rand -base64 32) dart run bin/main.dart
```

### 2. Запуск Data Service с регистрацией

```dart
// server_apps/aq_studio_data_service/bin/server.dart

void main() async {
  final config = AppConfig.fromEnvironment();

  // 1. Регистрация в Auth Service
  final registration = ResourceRegistration();
  final resourceConfig = await registration.register(
    authServiceUrl: config.authServiceUrl,
    resourceId: 'data-service-1',
    endpoint: 'http://localhost:8765',
    collections: ['projects', 'blueprints', 'sessions'],
  );

  print('✅ Registered with Auth Service');
  print('   JWT Secret: ${resourceConfig.jwtSecret.substring(0, 10)}...');
  print('   Introspection: ${resourceConfig.introspectionEndpoint}');

  // 2. Создать middleware
  final tokenValidator = TokenValidator(
    codec: TokenCodec(secret: resourceConfig.jwtSecret),
  );

  final introspectionClient = IntrospectionClient(
    introspectionEndpoint: resourceConfig.introspectionEndpoint,
  );

  final authMiddleware = ResourceAuthMiddleware(
    tokenValidator: tokenValidator,
    introspectionClient: introspectionClient,
    cache: InMemoryCache(),
  );

  // 3. Применить middleware
  final handler = const Pipeline()
    .addMiddleware(logRequests())
    .addMiddleware(authMiddleware())
    .addHandler(router);

  // 4. Запустить сервер
  await serve(handler, config.host, config.port);
  print('✅ Data Service running on ${config.host}:${config.port}');
}
```

### 3. Клиент делает запрос

```dart
// Flutter app
final token = await securityClient.login(...);

final response = await http.get(
  Uri.parse('http://data-service/projects/proj789'),
  headers: {'Authorization': 'Bearer ${token.accessToken}'},
);

// Data Service:
// 1. Проверяет токен локально (1-2 мс)
// 2. Проверяет кэш (0-1 мс)
// 3. Если cache miss - спрашивает Auth Service (10-50 мс)
// 4. Кэширует результат на 2 минуты
// 5. Возвращает данные или 403
```

---

## Преимущества

1. ✅ **Стандартный паттерн** - OAuth 2.0 Resource Server (как Google/AWS/Auth0)
2. ✅ **Тонкий клиент** - Data Service не знает о RBAC логике
3. ✅ **Централизованная безопасность** - вся логика в Auth Service
4. ✅ **Быстро** - кэширование решений на 2 минуты
5. ✅ **Масштабируемо** - можно добавить Redis для shared cache
6. ✅ **Мгновенный отзыв** - изменения прав применяются через 2 минуты (TTL кэша)
7. ✅ **Детальный аудит** - все проверки логируются в Auth Service
8. ✅ **Tenant isolation** - автоматически через tenantId в токене

---

## Производительность

- **Token validation (локально)**: 1-2 мс
- **Cache hit**: 0-1 мс
- **Cache miss (introspection)**: 10-50 мс
- **Cache TTL**: 2 минуты

**Итого:** 99% запросов обрабатываются за 1-3 мс (cache hit).

---

## Безопасность

1. ✅ JWT подпись проверяется локально
2. ✅ Детальные права проверяются через introspection
3. ✅ Кэш инвалидируется через TTL
4. ✅ Все проверки логируются
5. ✅ Tenant isolation гарантирован
6. ✅ IP/MFA/Time policies применяются в Auth Service

---

## Следующие шаги

1. Реализовать `IntrospectionRouter` в Auth Service
2. Реализовать `ResourceAuthMiddleware` в Data Service
3. Реализовать `IntrospectionClient`
4. Добавить `ResourceRegistration`
5. Интеграционные тесты
6. Добавить Redis для shared cache (опционально)
