# Client Resource Server — Детальный план

**Компонент**: Resource Server (Защищённый Data Layer)  
**Приоритет**: Низкий  
**Оценка**: 4 часа  
**Статус**: Планирование

---

## Цель

Создать пример защищённого data layer, демонстрирующий:
- Как `aq_security` защищает другой сервис
- Introspection для проверки токенов
- RBAC middleware для проверки прав
- Audit logging доступа
- Dual-mode клиент (consumer + resource server)

---

## Структура

```
client_resource_server/
├── bin/
│   └── main.dart               # Точка входа
├── lib/
│   ├── config.dart             # Конфигурация
│   ├── server.dart             # HTTP сервер
│   ├── middleware/
│   │   ├── auth_middleware.dart    # Token introspection
│   │   └── rbac_middleware.dart    # Permission checks
│   ├── routes/
│   │   ├── projects_router.dart    # /api/projects
│   │   └── tasks_router.dart       # /api/tasks
│   ├── repositories/
│   │   ├── project_repository.dart
│   │   └── task_repository.dart
│   └── models/
│       ├── project.dart
│       └── task.dart
├── Dockerfile                  # Контейнеризация
├── pubspec.yaml                # Зависимости
└── README.md                   # Документация
```

---

## bin/main.dart

```dart
import 'dart:io';
import 'package:client_resource_server/config.dart';
import 'package:client_resource_server/server.dart';

void main(List<String> args) async {
  // Загрузить конфигурацию
  final config = ResourceServerConfig.fromEnv();
  
  print('🚀 Starting Resource Server (Protected Data Layer)...');
  print('   Port: ${config.port}');
  print('   Auth Service: ${config.authServiceUrl}');
  print('   Data Layer: ${config.dataServiceUrl}');
  
  // Создать и запустить сервер
  final server = ResourceServer(config);
  await server.start();
  
  print('✅ Resource Server running on http://localhost:${config.port}');
  print('   Projects: http://localhost:${config.port}/api/projects');
  print('   Tasks: http://localhost:${config.port}/api/tasks');
  print('\n🔒 All endpoints protected by auth + RBAC');
  
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

final class ResourceServerConfig {
  const ResourceServerConfig({
    required this.port,
    required this.authServiceUrl,
    required this.dataServiceUrl,
  });
  
  final int port;
  final String authServiceUrl;
  final String dataServiceUrl;
  
  factory ResourceServerConfig.fromEnv() {
    return ResourceServerConfig(
      port: int.parse(Platform.environment['RESOURCE_SERVER_PORT'] ?? '8081'),
      authServiceUrl: Platform.environment['AUTH_SERVICE_URL'] ?? 
          'http://localhost:8080',
      dataServiceUrl: Platform.environment['DATA_SERVICE_URL'] ?? 
          'http://localhost:8090',
    );
  }
}
```

---

## lib/server.dart

```dart
import 'dart:io';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as io;
import 'package:shelf_router/shelf_router.dart';
import 'package:aq_security/aq_security.dart';
import 'config.dart';
import 'middleware/auth_middleware.dart';
import 'middleware/rbac_middleware.dart';
import 'routes/projects_router.dart';
import 'routes/tasks_router.dart';

final class ResourceServer {
  ResourceServer(this.config);
  
  final ResourceServerConfig config;
  HttpServer? _server;
  late IntrospectionClient introspectionClient;
  
  Future<void> start() async {
    // Создать introspection client
    introspectionClient = IntrospectionClient(
      introspectionEndpoint: '${config.authServiceUrl}/api/introspect',
    );
    
    // Создать HTTP сервер
    final handler = _createHandler();
    _server = await io.serve(handler, InternetAddress.anyIPv4, config.port);
  }
  
  Handler _createHandler() {
    final router = Router();
    
    // Health check (без auth)
    router.get('/health', (Request request) {
      return Response.ok('OK');
    });
    
    // Protected routes
    final projectsRouter = ProjectsRouter();
    final tasksRouter = TasksRouter();
    
    router.mount('/api/projects', projectsRouter.handler);
    router.mount('/api/tasks', tasksRouter.handler);
    
    // Middleware pipeline
    final pipeline = Pipeline()
        .addMiddleware(logRequests())
        .addMiddleware(authMiddleware(introspectionClient))
        .addMiddleware(rbacMiddleware())
        .addHandler(router);
    
    return pipeline;
  }
  
  Future<void> stop() async {
    await _server?.close(force: true);
  }
}
```

---

## lib/middleware/auth_middleware.dart

```dart
import 'dart:convert';
import 'package:shelf/shelf.dart';
import 'package:aq_security/aq_security.dart';

/// Middleware для проверки токенов через introspection
Middleware authMiddleware(IntrospectionClient introspectionClient) {
  return (Handler handler) {
    return (Request request) async {
      // Пропустить health check
      if (request.url.path == 'health') {
        return handler(request);
      }
      
      // Извлечь токен из Authorization header
      final authHeader = request.headers['authorization'];
      if (authHeader == null || !authHeader.startsWith('Bearer ')) {
        return Response.unauthorized(
          jsonEncode({'error': 'Missing or invalid Authorization header'}),
          headers: {'Content-Type': 'application/json'},
        );
      }
      
      final token = authHeader.substring(7); // Remove "Bearer "
      
      // Проверить токен через introspection
      try {
        final result = await introspectionClient.introspect(
          token: token,
          resource: _extractResource(request),
          action: _extractAction(request),
        );
        
        if (!result.active) {
          return Response.forbidden(
            jsonEncode({'error': 'Token is not active'}),
            headers: {'Content-Type': 'application/json'},
          );
        }
        
        if (!result.allowed) {
          return Response.forbidden(
            jsonEncode({'error': 'Permission denied'}),
            headers: {'Content-Type': 'application/json'},
          );
        }
        
        // Добавить user info в request context
        final updatedRequest = request.change(context: {
          'userId': result.userId,
          'tenantId': result.tenantId,
          'permissions': result.permissions,
        });
        
        return handler(updatedRequest);
      } catch (e) {
        return Response.internalServerError(
          body: jsonEncode({'error': 'Auth check failed: $e'}),
          headers: {'Content-Type': 'application/json'},
        );
      }
    };
  };
}

String _extractResource(Request request) {
  // /api/projects/123 -> projects
  final segments = request.url.pathSegments;
  if (segments.length >= 2 && segments[0] == 'api') {
    return segments[1];
  }
  return 'unknown';
}

String _extractAction(Request request) {
  // GET -> read, POST -> write, PUT -> write, DELETE -> delete
  switch (request.method) {
    case 'GET':
      return 'read';
    case 'POST':
      return 'write';
    case 'PUT':
      return 'write';
    case 'DELETE':
      return 'delete';
    default:
      return 'unknown';
  }
}
```

---

## lib/middleware/rbac_middleware.dart

```dart
import 'dart:convert';
import 'package:shelf/shelf.dart';

/// Middleware для дополнительных RBAC проверок
Middleware rbacMiddleware() {
  return (Handler handler) {
    return (Request request) async {
      // Пропустить health check
      if (request.url.path == 'health') {
        return handler(request);
      }
      
      // Получить user info из context (добавлен auth_middleware)
      final userId = request.context['userId'] as String?;
      final permissions = request.context['permissions'] as List<String>?;
      
      if (userId == null || permissions == null) {
        return Response.forbidden(
          jsonEncode({'error': 'Missing user context'}),
          headers: {'Content-Type': 'application/json'},
        );
      }
      
      // Дополнительные проверки (например, scope)
      // Здесь можно добавить логику для проверки ownership:
      // - projects:write:own -> только свои проекты
      // - projects:write:* -> все проекты
      
      // Audit logging
      print('🔒 Access: user=$userId, path=${request.url.path}, method=${request.method}');
      
      return handler(request);
    };
  };
}
```

---

## lib/routes/projects_router.dart

```dart
import 'dart:convert';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import '../models/project.dart';
import '../repositories/project_repository.dart';

final class ProjectsRouter {
  ProjectsRouter() {
    _repository = ProjectRepository();
  }
  
  late final ProjectRepository _repository;
  
  Handler get handler {
    final router = Router();
    
    // GET /api/projects
    router.get('/', (Request request) async {
      final userId = request.context['userId'] as String;
      final tenantId = request.context['tenantId'] as String;
      
      final projects = await _repository.findAll(
        userId: userId,
        tenantId: tenantId,
      );
      
      return Response.ok(
        jsonEncode(projects.map((p) => p.toJson()).toList()),
        headers: {'Content-Type': 'application/json'},
      );
    });
    
    // GET /api/projects/:id
    router.get('/<id>', (Request request, String id) async {
      final userId = request.context['userId'] as String;
      
      final project = await _repository.findById(id);
      
      if (project == null) {
        return Response.notFound(
          jsonEncode({'error': 'Project not found'}),
          headers: {'Content-Type': 'application/json'},
        );
      }
      
      // Проверка ownership (если нужно)
      // if (project.ownerId != userId && !hasPermission('projects:read:*')) {
      //   return Response.forbidden(...);
      // }
      
      return Response.ok(
        jsonEncode(project.toJson()),
        headers: {'Content-Type': 'application/json'},
      );
    });
    
    // POST /api/projects
    router.post('/', (Request request) async {
      final userId = request.context['userId'] as String;
      final tenantId = request.context['tenantId'] as String;
      
      final body = await request.readAsString();
      final data = jsonDecode(body) as Map<String, dynamic>;
      
      final project = Project(
        id: 'proj_${DateTime.now().millisecondsSinceEpoch}',
        name: data['name'] as String,
        ownerId: userId,
        tenantId: tenantId,
        createdAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      );
      
      await _repository.create(project);
      
      return Response.ok(
        jsonEncode(project.toJson()),
        headers: {'Content-Type': 'application/json'},
      );
    });
    
    // DELETE /api/projects/:id
    router.delete('/<id>', (Request request, String id) async {
      await _repository.delete(id);
      
      return Response.ok(
        jsonEncode({'message': 'Project deleted'}),
        headers: {'Content-Type': 'application/json'},
      );
    });
    
    return router;
  }
}
```

---

## lib/models/project.dart

```dart
final class Project {
  const Project({
    required this.id,
    required this.name,
    required this.ownerId,
    required this.tenantId,
    required this.createdAt,
    this.description,
  });
  
  final String id;
  final String name;
  final String? description;
  final String ownerId;
  final String tenantId;
  final int createdAt;
  
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    if (description != null) 'description': description,
    'ownerId': ownerId,
    'tenantId': tenantId,
    'createdAt': createdAt,
  };
  
  factory Project.fromJson(Map<String, dynamic> json) => Project(
    id: json['id'] as String,
    name: json['name'] as String,
    description: json['description'] as String?,
    ownerId: json['ownerId'] as String,
    tenantId: json['tenantId'] as String,
    createdAt: json['createdAt'] as int,
  );
}
```

---

## lib/repositories/project_repository.dart

```dart
import '../models/project.dart';

/// In-memory repository для демонстрации
/// В реальности использовал бы dart_vault
final class ProjectRepository {
  final _projects = <String, Project>{};
  
  Future<List<Project>> findAll({
    required String userId,
    required String tenantId,
  }) async {
    // Фильтр по tenant
    return _projects.values
        .where((p) => p.tenantId == tenantId)
        .toList();
  }
  
  Future<Project?> findById(String id) async {
    return _projects[id];
  }
  
  Future<void> create(Project project) async {
    _projects[project.id] = project;
  }
  
  Future<void> delete(String id) async {
    _projects.remove(id);
  }
}
```

---

## pubspec.yaml

```yaml
name: client_resource_server
description: Protected Resource Server Demo
version: 1.0.0

environment:
  sdk: ^3.3.0

dependencies:
  shelf: ^1.4.0
  shelf_router: ^1.1.0
  aq_security:
    path: ../..

dev_dependencies:
  lints: ^3.0.0
```

---

## README.md

```markdown
# Resource Server (Protected Data Layer)

Пример защищённого data layer с auth + RBAC.

## Архитектура

```
Client → Resource Server → Auth Service (introspection)
              ↓
         Data Layer (projects, tasks)
```

## Защита

### 1. Auth Middleware
- Извлекает токен из `Authorization: Bearer <token>`
- Проверяет через introspection endpoint
- Добавляет user context в request

### 2. RBAC Middleware
- Проверяет права доступа
- Проверяет ownership (own vs *)
- Логирует доступ

## Endpoints

### Projects
- `GET /api/projects` - Список проектов (требует `projects:read`)
- `GET /api/projects/:id` - Один проект (требует `projects:read`)
- `POST /api/projects` - Создать проект (требует `projects:write`)
- `DELETE /api/projects/:id` - Удалить проект (требует `projects:delete`)

### Tasks
- `GET /api/tasks` - Список задач (требует `tasks:read`)
- `POST /api/tasks` - Создать задачу (требует `tasks:write`)

## Запуск

```bash
# Установить зависимости
dart pub get

# Настроить переменные окружения
export RESOURCE_SERVER_PORT=8081
export AUTH_SERVICE_URL=http://localhost:8080
export DATA_SERVICE_URL=http://localhost:8090

# Запустить
dart run bin/main.dart
```

## Тестирование

```bash
# 1. Получить токен
curl -X POST http://localhost:8080/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email":"admin@test.com","password":"admin123"}'

# 2. Использовать токен
curl http://localhost:8081/api/projects \
  -H "Authorization: Bearer <access_token>"

# 3. Создать проект
curl -X POST http://localhost:8081/api/projects \
  -H "Authorization: Bearer <access_token>" \
  -H "Content-Type: application/json" \
  -d '{"name":"My Project","description":"Test"}'
```

## Dual-mode клиент

Этот сервер одновременно:
- **Consumer**: Использует auth-сервис для проверки токенов
- **Resource Server**: Защищает свои данные через introspection

## Что демонстрирует

- ✅ Token introspection
- ✅ RBAC middleware
- ✅ Permission checks
- ✅ Audit logging
- ✅ Tenant isolation
- ✅ Ownership checks (own vs *)
```

---

## Задачи реализации

### Задача 6.1: Создать структуру проекта
**Оценка**: 15 минут

### Задача 6.2: Реализовать config.dart
**Оценка**: 15 минут

### Задача 6.3: Реализовать auth_middleware.dart
**Оценка**: 60 минут

### Задача 6.4: Реализовать rbac_middleware.dart
**Оценка**: 30 минут

### Задача 6.5: Реализовать models
**Оценка**: 20 минут

### Задача 6.6: Реализовать repositories
**Оценка**: 30 минут

### Задача 6.7: Реализовать projects_router.dart
**Оценка**: 45 минут

### Задача 6.8: Реализовать server.dart и main.dart
**Оценка**: 30 минут

### Задача 6.9: Создать README.md
**Оценка**: 15 минут

### Задача 6.10: Тестирование
**Оценка**: 20 минут

---

## Acceptance Criteria

- ✅ Сервер запускается на порту 8081
- ✅ Auth middleware проверяет токены
- ✅ RBAC middleware проверяет права
- ✅ Все endpoints защищены
- ✅ Audit logging работает
- ✅ README полный

---

## Статус

- [ ] Задача 6.1: Структура проекта
- [ ] Задача 6.2: config.dart
- [ ] Задача 6.3: auth_middleware.dart
- [ ] Задача 6.4: rbac_middleware.dart
- [ ] Задача 6.5: Models
- [ ] Задача 6.6: Repositories
- [ ] Задача 6.7: projects_router.dart
- [ ] Задача 6.8: server.dart + main.dart
- [ ] Задача 6.9: README.md
- [ ] Задача 6.10: Тестирование
