# Server Auth — Детальный план

**Компонент**: Auth Service  
**Приоритет**: Высокий  
**Оценка**: 4 часа  
**Статус**: Планирование

---

## Цель

Создать полноценный auth-сервер с:
- Всеми провайдерами (Google OAuth, Email/Password, API Keys)
- RBAC системой
- Token management
- Introspection endpoint
- Seed данными для тестирования

---

## Структура

```
server_auth/
├── bin/
│   └── main.dart               # Точка входа
├── lib/
│   ├── config.dart             # Конфигурация
│   ├── server.dart             # HTTP сервер
│   ├── seed_data.dart          # Тестовые данные
│   └── middleware/
│       └── error_handler.dart  # Error handling
├── Dockerfile                  # Контейнеризация
├── pubspec.yaml                # Зависимости
└── README.md                   # Документация
```

---

## bin/main.dart

```dart
import 'dart:io';
import 'package:server_auth/config.dart';
import 'package:server_auth/server.dart';
import 'package:server_auth/seed_data.dart';

void main(List<String> args) async {
  // Загрузить конфигурацию
  final config = AuthServiceConfig.fromEnv();
  
  print('🚀 Starting AQ Security Auth Service...');
  print('   Port: ${config.port}');
  print('   Data Layer: ${config.dataServiceUrl}');
  print('   JWT Secret: ${config.jwtSecret.substring(0, 8)}...');
  
  // Создать и запустить сервер
  final server = AuthServiceServer(config);
  await server.start();
  
  print('✅ Auth Service running on http://localhost:${config.port}');
  print('   Health: http://localhost:${config.port}/health');
  print('   Auth: http://localhost:${config.port}/auth/*');
  print('   RBAC: http://localhost:${config.port}/rbac/*');
  print('   Introspect: http://localhost:${config.port}/api/introspect');
  
  // Seed данные (только в dev режиме)
  if (config.isDev) {
    print('\n🌱 Seeding test data...');
    await seedTestData(server.authServer);
    print('✅ Test data seeded');
  }
  
  // Graceful shutdown
  ProcessSignal.sigint.watch().listen((_) async {
    print('\n🛑 Shutting down...');
    await server.stop();
    exit(0);
  });
}
```

---

## lib/config.dart

```dart
import 'dart:io';

final class AuthServiceConfig {
  const AuthServiceConfig({
    required this.port,
    required this.dataServiceUrl,
    required this.jwtSecret,
    required this.googleClientId,
    required this.googleClientSecret,
    required this.googleRedirectUri,
    required this.redisUrl,
    required this.allowedOrigins,
    required this.isDev,
  });
  
  final int port;
  final String dataServiceUrl;
  final String jwtSecret;
  final String? googleClientId;
  final String? googleClientSecret;
  final String? googleRedirectUri;
  final String redisUrl;
  final List<String> allowedOrigins;
  final bool isDev;
  
  factory AuthServiceConfig.fromEnv() {
    final originsStr = Platform.environment['ALLOWED_ORIGINS'] ?? 
        'http://localhost:3000,http://localhost:8081';
    
    return AuthServiceConfig(
      port: int.parse(Platform.environment['AUTH_SERVICE_PORT'] ?? '8080'),
      dataServiceUrl: Platform.environment['AUTH_DATA_SERVICE_URL'] ?? 
          'http://localhost:8090',
      jwtSecret: Platform.environment['AUTH_JWT_SECRET'] ?? 
          throw Exception('AUTH_JWT_SECRET is required'),
      googleClientId: Platform.environment['GOOGLE_CLIENT_ID'],
      googleClientSecret: Platform.environment['GOOGLE_CLIENT_SECRET'],
      googleRedirectUri: Platform.environment['GOOGLE_REDIRECT_URI'],
      redisUrl: Platform.environment['REDIS_URL'] ?? 'redis://localhost:6379',
      allowedOrigins: originsStr.split(',').map((s) => s.trim()).toList(),
      isDev: Platform.environment['ENV'] != 'production',
    );
  }
  
  bool get hasGoogleOAuth => 
      googleClientId != null && 
      googleClientSecret != null && 
      googleRedirectUri != null;
}
```

---

## lib/server.dart

```dart
import 'dart:io';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as io;
import 'package:aq_security/aq_security_server.dart';
import 'config.dart';
import 'middleware/error_handler.dart';

final class AuthServiceServer {
  AuthServiceServer(this.config);
  
  final AuthServiceConfig config;
  HttpServer? _server;
  late AQAuthServer authServer;
  
  Future<void> start() async {
    // Создать SecurityConfig
    final securityConfig = SecurityConfig(
      jwtSecret: config.jwtSecret,
      dataServiceUrl: config.dataServiceUrl,
      googleOAuth: config.hasGoogleOAuth
          ? GoogleOAuthConfig(
              clientId: config.googleClientId!,
              clientSecret: config.googleClientSecret!,
              redirectUri: config.googleRedirectUri!,
            )
          : null,
      rateLimitConfig: RateLimitConfig(
        maxRequests: 100,
        windowSeconds: 60,
      ),
      corsConfig: CorsConfig(
        allowedOrigins: config.allowedOrigins,
      ),
    );
    
    // Создать AQAuthServer
    authServer = AQAuthServer(securityConfig);
    await authServer.initialize();
    
    // Создать HTTP сервер
    final handler = _createHandler();
    _server = await io.serve(handler, InternetAddress.anyIPv4, config.port);
  }
  
  Handler _createHandler() {
    // Middleware pipeline
    final pipeline = Pipeline()
        .addMiddleware(logRequests())
        .addMiddleware(errorHandlerMiddleware())
        .addHandler(authServer.handler);
    
    return pipeline;
  }
  
  Future<void> stop() async {
    await _server?.close(force: true);
    await authServer.dispose();
  }
}
```

---

## lib/seed_data.dart

```dart
import 'package:aq_security/aq_security_server.dart';
import 'package:aq_schema/security/security.dart';

/// Создать тестовые данные для примеров
Future<void> seedTestData(AQAuthServer server) async {
  // 1. Создать тестовый tenant
  final tenant = AqTenant(
    id: 'tenant_test',
    slug: 'test-company',
    name: 'Test Company',
    plan: TenantPlan.pro,
    isActive: true,
    createdAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
  );
  
  // 2. Создать тестовых пользователей
  final users = [
    AqUser(
      id: 'user_admin',
      email: 'admin@test.com',
      tenantId: tenant.id,
      authProvider: AuthProvider.email,
      userType: UserType.admin,
      isActive: true,
      createdAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
    ),
    AqUser(
      id: 'user_developer',
      email: 'developer@test.com',
      tenantId: tenant.id,
      authProvider: AuthProvider.email,
      userType: UserType.regular,
      isActive: true,
      createdAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
    ),
    AqUser(
      id: 'user_viewer',
      email: 'viewer@test.com',
      tenantId: tenant.id,
      authProvider: AuthProvider.email,
      userType: UserType.regular,
      isActive: true,
      createdAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
    ),
  ];
  
  // 3. Создать роли
  final roles = [
    AqRole(
      id: 'role_admin',
      name: 'Admin',
      tenantId: tenant.id,
      permissions: ['*:*:*'], // Полный доступ
      isSystem: false,
      createdAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
    ),
    AqRole(
      id: 'role_developer',
      name: 'Developer',
      tenantId: tenant.id,
      permissions: [
        'projects:read:*',
        'projects:write:own',
        'tasks:*:own',
      ],
      isSystem: false,
      createdAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
    ),
    AqRole(
      id: 'role_viewer',
      name: 'Viewer',
      tenantId: tenant.id,
      permissions: [
        'projects:read:*',
        'tasks:read:*',
      ],
      isSystem: false,
      createdAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
    ),
  ];
  
  // 4. Назначить роли пользователям
  final userRoles = [
    AqUserRole(
      userId: users[0].id,
      roleId: roles[0].id,
      tenantId: tenant.id,
      grantedAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
    ),
    AqUserRole(
      userId: users[1].id,
      roleId: roles[1].id,
      tenantId: tenant.id,
      grantedAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
    ),
    AqUserRole(
      userId: users[2].id,
      roleId: roles[2].id,
      tenantId: tenant.id,
      grantedAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
    ),
  ];
  
  // 5. Создать тестовый API ключ
  final apiKey = AqApiKey(
    id: 'key_test',
    userId: users[0].id,
    tenantId: tenant.id,
    name: 'Test API Key',
    keyHash: 'hash_of_test_key', // В реальности будет SHA-256
    prefix: 'aq_test_',
    isActive: true,
    createdAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
  );
  
  // Сохранить всё через repositories
  // TODO: Реализовать через server.repositories
  
  print('✅ Created:');
  print('   - 1 tenant: ${tenant.slug}');
  print('   - ${users.length} users');
  print('   - ${roles.length} roles');
  print('   - ${userRoles.length} role assignments');
  print('   - 1 API key');
  print('\n📝 Test credentials:');
  print('   Email: admin@test.com / Password: admin123');
  print('   Email: developer@test.com / Password: dev123');
  print('   Email: viewer@test.com / Password: view123');
  print('   API Key: aq_test_1234567890abcdef');
}
```

---

## lib/middleware/error_handler.dart

```dart
import 'dart:convert';
import 'package:shelf/shelf.dart';

Middleware errorHandlerMiddleware() {
  return (Handler handler) {
    return (Request request) async {
      try {
        return await handler(request);
      } catch (error, stackTrace) {
        print('❌ Error: $error');
        print('   Stack: $stackTrace');
        
        return Response.internalServerError(
          body: jsonEncode({
            'error': 'Internal Server Error',
            'message': error.toString(),
          }),
          headers: {'Content-Type': 'application/json'},
        );
      }
    };
  };
}
```

---

## Dockerfile

```dockerfile
FROM dart:3.3-sdk AS build

WORKDIR /app

# Копировать pubspec
COPY pubspec.yaml pubspec.lock ./

# Установить зависимости
RUN dart pub get

# Копировать исходники
COPY . .

# Скомпилировать
RUN dart compile exe bin/main.dart -o bin/server

# Runtime образ
FROM debian:bookworm-slim

# Установить runtime зависимости
RUN apt-get update && apt-get install -y \
    ca-certificates \
    curl \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Копировать скомпилированный бинарник
COPY --from=build /app/bin/server /app/bin/server

# Expose порт
EXPOSE 8080

# Health check
HEALTHCHECK --interval=10s --timeout=5s --retries=5 \
  CMD curl -f http://localhost:8080/health || exit 1

# Запуск
CMD ["/app/bin/server"]
```

---

## pubspec.yaml

```yaml
name: server_auth
description: AQ Security Auth Service
version: 1.0.0

environment:
  sdk: ^3.3.0

dependencies:
  shelf: ^1.4.0
  aq_security:
    path: ../..
  aq_schema:
    path: ../../../aq_schema

dev_dependencies:
  lints: ^3.0.0
```

---

## README.md

```markdown
# AQ Security Auth Service

Полноценный auth-сервер с OAuth, RBAC, и token management.

## Провайдеры

- ✅ Google OAuth
- ✅ Email/Password
- ✅ API Keys
- ⏳ GitHub OAuth (TODO)
- ⏳ Magic Links (TODO)

## Endpoints

### Auth
- `POST /auth/login` - Email/Password login
- `POST /auth/register` - Регистрация
- `GET /auth/google` - Google OAuth redirect
- `GET /auth/google/callback` - Google OAuth callback
- `POST /auth/refresh` - Refresh tokens
- `POST /auth/logout` - Logout

### RBAC
- `GET /rbac/roles` - Список ролей
- `POST /rbac/roles` - Создать роль
- `GET /rbac/permissions` - Проверить права

### Introspection
- `POST /api/introspect` - Проверить токен

## Запуск локально

```bash
# Установить зависимости
dart pub get

# Настроить переменные окружения
export AUTH_SERVICE_PORT=8080
export AUTH_DATA_SERVICE_URL=http://localhost:8090
export AUTH_JWT_SECRET=your_secret_min_32_chars
export GOOGLE_CLIENT_ID=your_google_client_id
export GOOGLE_CLIENT_SECRET=your_google_client_secret
export GOOGLE_REDIRECT_URI=http://localhost:8080/auth/google/callback
export REDIS_URL=redis://localhost:6379
export ALLOWED_ORIGINS=http://localhost:3000

# Запустить
dart run bin/main.dart
```

## Тестовые данные

В dev режиме автоматически создаются:
- Tenant: `test-company`
- Users: `admin@test.com`, `developer@test.com`, `viewer@test.com`
- Roles: Admin, Developer, Viewer
- API Key: `aq_test_1234567890abcdef`

Пароли: `admin123`, `dev123`, `view123`
```

---

## Задачи реализации

### Задача 3.1: Создать структуру проекта
**Оценка**: 15 минут

### Задача 3.2: Реализовать config.dart
**Оценка**: 30 минут

### Задача 3.3: Реализовать server.dart
**Оценка**: 45 минут

### Задача 3.4: Реализовать seed_data.dart
**Оценка**: 60 минут

### Задача 3.5: Реализовать main.dart
**Оценка**: 20 минут

### Задача 3.6: Создать Dockerfile
**Оценка**: 20 минут

### Задача 3.7: Создать README.md
**Оценка**: 20 минут

### Задача 3.8: Тестирование
**Оценка**: 30 минут

---

## Acceptance Criteria

- ✅ Сервер запускается на порту 8080
- ✅ Подключается к Data Layer
- ✅ Все auth endpoints работают
- ✅ RBAC endpoints работают
- ✅ Introspection endpoint работает
- ✅ Seed данные создаются
- ✅ Dockerfile собирается
- ✅ README полный

---

## Статус

- [ ] Задача 3.1: Структура проекта
- [ ] Задача 3.2: config.dart
- [ ] Задача 3.3: server.dart
- [ ] Задача 3.4: seed_data.dart
- [ ] Задача 3.5: main.dart
- [ ] Задача 3.6: Dockerfile
- [ ] Задача 3.7: README.md
- [ ] Задача 3.8: Тестирование
