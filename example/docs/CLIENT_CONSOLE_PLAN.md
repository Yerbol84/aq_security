# Client Console — Детальный план

**Компонент**: Console Client (Боевые тесты)  
**Приоритет**: Средний  
**Оценка**: 3 часа  
**Статус**: Планирование

---

## Цель

Создать консольное приложение для боевого тестирования всех auth flow:
- Проверка всех провайдеров
- Проверка token lifecycle
- Проверка RBAC
- Цветной вывод результатов (✅/❌)
- Можно запустить как smoke test

---

## Структура

```
client_console/
├── bin/
│   └── main.dart               # Точка входа
├── lib/
│   ├── config.dart             # Конфигурация
│   ├── test_runner.dart        # Запуск тестов
│   ├── tests/
│   │   ├── auth_tests.dart     # Auth flow тесты
│   │   ├── rbac_tests.dart     # RBAC тесты
│   │   └── token_tests.dart    # Token lifecycle тесты
│   └── utils/
│       ├── logger.dart         # Цветной вывод
│       └── assertions.dart     # Проверки
├── pubspec.yaml                # Зависимости
└── README.md                   # Документация
```

---

## bin/main.dart

```dart
import 'package:client_console/config.dart';
import 'package:client_console/test_runner.dart';

void main(List<String> args) async {
  print('🧪 AQ Security Console Test Runner\n');
  
  // Загрузить конфигурацию
  final config = ConsoleConfig.fromEnv();
  
  print('📋 Configuration:');
  print('   Auth Service: ${config.authServiceUrl}');
  print('   Test User: ${config.testEmail}');
  print('');
  
  // Запустить тесты
  final runner = TestRunner(config);
  final results = await runner.runAll();
  
  // Вывести результаты
  print('\n' + '=' * 60);
  print('📊 Test Results:');
  print('   Total: ${results.total}');
  print('   ✅ Passed: ${results.passed}');
  print('   ❌ Failed: ${results.failed}');
  print('   ⏭️  Skipped: ${results.skipped}');
  print('=' * 60);
  
  // Exit code
  if (results.failed > 0) {
    print('\n❌ Some tests failed');
    exit(1);
  } else {
    print('\n✅ All tests passed!');
    exit(0);
  }
}
```

---

## lib/config.dart

```dart
import 'dart:io';

final class ConsoleConfig {
  const ConsoleConfig({
    required this.authServiceUrl,
    required this.testEmail,
    required this.testPassword,
    required this.testApiKey,
  });
  
  final String authServiceUrl;
  final String testEmail;
  final String testPassword;
  final String testApiKey;
  
  factory ConsoleConfig.fromEnv() {
    return ConsoleConfig(
      authServiceUrl: Platform.environment['AUTH_SERVICE_URL'] ?? 
          'http://localhost:8080',
      testEmail: Platform.environment['TEST_EMAIL'] ?? 'admin@test.com',
      testPassword: Platform.environment['TEST_PASSWORD'] ?? 'admin123',
      testApiKey: Platform.environment['TEST_API_KEY'] ?? 
          'aq_test_1234567890abcdef',
    );
  }
}
```

---

## lib/test_runner.dart

```dart
import 'package:aq_security/aq_security.dart';
import 'config.dart';
import 'tests/auth_tests.dart';
import 'tests/rbac_tests.dart';
import 'tests/token_tests.dart';
import 'utils/logger.dart';

final class TestResults {
  TestResults({
    required this.total,
    required this.passed,
    required this.failed,
    required this.skipped,
  });
  
  final int total;
  final int passed;
  final int failed;
  final int skipped;
}

final class TestRunner {
  TestRunner(this.config);
  
  final ConsoleConfig config;
  late AQSecurityService service;
  
  Future<TestResults> runAll() async {
    final logger = Logger();
    int passed = 0;
    int failed = 0;
    int skipped = 0;
    
    // Инициализация клиента
    logger.section('Initialization');
    try {
      final client = await AQSecurityClient.init(config.authServiceUrl);
      service = client.service;
      logger.success('Client initialized');
    } catch (e) {
      logger.error('Failed to initialize client: $e');
      return TestResults(total: 1, passed: 0, failed: 1, skipped: 0);
    }
    
    // Auth Tests
    logger.section('Authentication Tests');
    final authTests = AuthTests(service, config, logger);
    final authResults = await authTests.runAll();
    passed += authResults.passed;
    failed += authResults.failed;
    skipped += authResults.skipped;
    
    // Token Tests
    logger.section('Token Lifecycle Tests');
    final tokenTests = TokenTests(service, config, logger);
    final tokenResults = await tokenTests.runAll();
    passed += tokenResults.passed;
    failed += tokenResults.failed;
    skipped += tokenResults.skipped;
    
    // RBAC Tests
    logger.section('RBAC Tests');
    final rbacTests = RBACTests(service, config, logger);
    final rbacResults = await rbacTests.runAll();
    passed += rbacResults.passed;
    failed += rbacResults.failed;
    skipped += rbacResults.skipped;
    
    final total = passed + failed + skipped;
    return TestResults(
      total: total,
      passed: passed,
      failed: failed,
      skipped: skipped,
    );
  }
}
```

---

## lib/tests/auth_tests.dart

```dart
import 'package:aq_security/aq_security.dart';
import '../config.dart';
import '../utils/logger.dart';
import '../utils/assertions.dart';

final class AuthTests {
  AuthTests(this.service, this.config, this.logger);
  
  final AQSecurityService service;
  final ConsoleConfig config;
  final Logger logger;
  
  Future<TestResults> runAll() async {
    int passed = 0;
    int failed = 0;
    int skipped = 0;
    
    // Test 1: Email/Password Login
    try {
      logger.test('Email/Password Login');
      await service.loginWithEmail(
        email: config.testEmail,
        password: config.testPassword,
      );
      
      Assert.isTrue(service.isAuthenticated, 'Should be authenticated');
      Assert.isNotNull(service.currentUser, 'Should have current user');
      Assert.equals(
        service.currentUser?.email,
        config.testEmail,
        'Email should match',
      );
      
      logger.success('Email/Password Login');
      passed++;
    } catch (e) {
      logger.error('Email/Password Login: $e');
      failed++;
    }
    
    // Test 2: Logout
    try {
      logger.test('Logout');
      await service.logout();
      
      Assert.isFalse(service.isAuthenticated, 'Should not be authenticated');
      Assert.isNull(service.currentUser, 'Should not have current user');
      
      logger.success('Logout');
      passed++;
    } catch (e) {
      logger.error('Logout: $e');
      failed++;
    }
    
    // Test 3: API Key Login
    try {
      logger.test('API Key Login');
      await service.loginWithApiKey(apiKey: config.testApiKey);
      
      Assert.isTrue(service.isAuthenticated, 'Should be authenticated');
      
      logger.success('API Key Login');
      passed++;
    } catch (e) {
      logger.error('API Key Login: $e');
      failed++;
    }
    
    // Test 4: Invalid Credentials
    try {
      logger.test('Invalid Credentials (should fail)');
      
      try {
        await service.loginWithEmail(
          email: 'invalid@test.com',
          password: 'wrong',
        );
        
        // Если дошли сюда - тест провален
        logger.error('Invalid Credentials: Should have thrown');
        failed++;
      } catch (e) {
        // Ожидаем ошибку
        logger.success('Invalid Credentials (correctly rejected)');
        passed++;
      }
    } catch (e) {
      logger.error('Invalid Credentials test: $e');
      failed++;
    }
    
    return TestResults(passed: passed, failed: failed, skipped: skipped);
  }
}
```

---

## lib/tests/token_tests.dart

```dart
import 'package:aq_security/aq_security.dart';
import '../config.dart';
import '../utils/logger.dart';
import '../utils/assertions.dart';

final class TokenTests {
  TokenTests(this.service, this.config, this.logger);
  
  final AQSecurityService service;
  final ConsoleConfig config;
  final Logger logger;
  
  Future<TestResults> runAll() async {
    int passed = 0;
    int failed = 0;
    int skipped = 0;
    
    // Сначала залогиниться
    await service.loginWithEmail(
      email: config.testEmail,
      password: config.testPassword,
    );
    
    // Test 1: Token Refresh
    try {
      logger.test('Token Refresh');
      
      final oldToken = service.accessToken;
      await service.refreshTokens();
      final newToken = service.accessToken;
      
      Assert.isNotNull(newToken, 'Should have new token');
      Assert.notEquals(oldToken, newToken, 'Token should be different');
      
      logger.success('Token Refresh');
      passed++;
    } catch (e) {
      logger.error('Token Refresh: $e');
      failed++;
    }
    
    // Test 2: Token Validation
    try {
      logger.test('Token Validation');
      
      final isValid = await service.validateToken(service.accessToken!);
      Assert.isTrue(isValid, 'Token should be valid');
      
      logger.success('Token Validation');
      passed++;
    } catch (e) {
      logger.error('Token Validation: $e');
      failed++;
    }
    
    // Test 3: Invalid Token
    try {
      logger.test('Invalid Token (should fail)');
      
      final isValid = await service.validateToken('invalid_token');
      Assert.isFalse(isValid, 'Invalid token should not be valid');
      
      logger.success('Invalid Token (correctly rejected)');
      passed++;
    } catch (e) {
      logger.error('Invalid Token test: $e');
      failed++;
    }
    
    return TestResults(passed: passed, failed: failed, skipped: skipped);
  }
}
```

---

## lib/tests/rbac_tests.dart

```dart
import 'package:aq_security/aq_security.dart';
import '../config.dart';
import '../utils/logger.dart';
import '../utils/assertions.dart';

final class RBACTests {
  RBACTests(this.service, this.config, this.logger);
  
  final AQSecurityService service;
  final ConsoleConfig config;
  final Logger logger;
  
  Future<TestResults> runAll() async {
    int passed = 0;
    int failed = 0;
    int skipped = 0;
    
    // Залогиниться как admin
    await service.loginWithEmail(
      email: config.testEmail,
      password: config.testPassword,
    );
    
    // Test 1: Has Permission
    try {
      logger.test('Has Permission (admin should have all)');
      
      final hasPermission = await service.hasPermission('projects:read');
      Assert.isTrue(hasPermission, 'Admin should have projects:read');
      
      logger.success('Has Permission');
      passed++;
    } catch (e) {
      logger.error('Has Permission: $e');
      failed++;
    }
    
    // Test 2: Has Role
    try {
      logger.test('Has Role');
      
      final hasRole = await service.hasRole('Admin');
      Assert.isTrue(hasRole, 'User should have Admin role');
      
      logger.success('Has Role');
      passed++;
    } catch (e) {
      logger.error('Has Role: $e');
      failed++;
    }
    
    // Test 3: Get Resource Permissions
    try {
      logger.test('Get Resource Permissions');
      
      final perms = await service.getResourcePermissions('project/123');
      Assert.isNotEmpty(perms, 'Should have permissions');
      
      logger.success('Get Resource Permissions');
      passed++;
    } catch (e) {
      logger.error('Get Resource Permissions: $e');
      failed++;
    }
    
    return TestResults(passed: passed, failed: failed, skipped: skipped);
  }
}
```

---

## lib/utils/logger.dart

```dart
final class Logger {
  void section(String title) {
    print('\n${'─' * 60}');
    print('📦 $title');
    print('─' * 60);
  }
  
  void test(String name) {
    print('   🧪 Testing: $name...');
  }
  
  void success(String name) {
    print('   ✅ $name');
  }
  
  void error(String message) {
    print('   ❌ $message');
  }
  
  void skip(String name) {
    print('   ⏭️  Skipped: $name');
  }
  
  void info(String message) {
    print('   ℹ️  $message');
  }
}
```

---

## lib/utils/assertions.dart

```dart
final class Assert {
  static void isTrue(bool condition, String message) {
    if (!condition) {
      throw AssertionError('Expected true: $message');
    }
  }
  
  static void isFalse(bool condition, String message) {
    if (condition) {
      throw AssertionError('Expected false: $message');
    }
  }
  
  static void isNull(Object? value, String message) {
    if (value != null) {
      throw AssertionError('Expected null: $message');
    }
  }
  
  static void isNotNull(Object? value, String message) {
    if (value == null) {
      throw AssertionError('Expected not null: $message');
    }
  }
  
  static void equals(Object? actual, Object? expected, String message) {
    if (actual != expected) {
      throw AssertionError('Expected $expected, got $actual: $message');
    }
  }
  
  static void notEquals(Object? actual, Object? expected, String message) {
    if (actual == expected) {
      throw AssertionError('Expected not equal to $expected: $message');
    }
  }
  
  static void isNotEmpty(List list, String message) {
    if (list.isEmpty) {
      throw AssertionError('Expected not empty: $message');
    }
  }
}
```

---

## pubspec.yaml

```yaml
name: client_console
description: AQ Security Console Test Client
version: 1.0.0

environment:
  sdk: ^3.3.0

dependencies:
  aq_security:
    path: ../..
  http: ^1.1.0

dev_dependencies:
  lints: ^3.0.0
```

---

## README.md

```markdown
# AQ Security Console Client

Боевые тесты всех auth flow.

## Что тестируется

### Authentication
- ✅ Email/Password login
- ✅ Logout
- ✅ API Key login
- ✅ Invalid credentials (should fail)

### Token Lifecycle
- ✅ Token refresh
- ✅ Token validation
- ✅ Invalid token (should fail)

### RBAC
- ✅ Permission check
- ✅ Role check
- ✅ Resource permissions

## Запуск

```bash
# Установить зависимости
dart pub get

# Запустить (требуется запущенный auth-сервер)
dart run bin/main.dart
```

## Переменные окружения

```bash
export AUTH_SERVICE_URL=http://localhost:8080
export TEST_EMAIL=admin@test.com
export TEST_PASSWORD=admin123
export TEST_API_KEY=aq_test_1234567890abcdef
```

## Пример вывода

```
🧪 AQ Security Console Test Runner

📋 Configuration:
   Auth Service: http://localhost:8080
   Test User: admin@test.com

────────────────────────────────────────────────────────────
📦 Initialization
────────────────────────────────────────────────────────────
   ✅ Client initialized

────────────────────────────────────────────────────────────
📦 Authentication Tests
────────────────────────────────────────────────────────────
   🧪 Testing: Email/Password Login...
   ✅ Email/Password Login
   🧪 Testing: Logout...
   ✅ Logout
   🧪 Testing: API Key Login...
   ✅ API Key Login
   🧪 Testing: Invalid Credentials (should fail)...
   ✅ Invalid Credentials (correctly rejected)

────────────────────────────────────────────────────────────
📦 Token Lifecycle Tests
────────────────────────────────────────────────────────────
   🧪 Testing: Token Refresh...
   ✅ Token Refresh
   🧪 Testing: Token Validation...
   ✅ Token Validation
   🧪 Testing: Invalid Token (should fail)...
   ✅ Invalid Token (correctly rejected)

────────────────────────────────────────────────────────────
📦 RBAC Tests
────────────────────────────────────────────────────────────
   🧪 Testing: Has Permission (admin should have all)...
   ✅ Has Permission
   🧪 Testing: Has Role...
   ✅ Has Role
   🧪 Testing: Get Resource Permissions...
   ✅ Get Resource Permissions

============================================================
📊 Test Results:
   Total: 11
   ✅ Passed: 11
   ❌ Failed: 0
   ⏭️  Skipped: 0
============================================================

✅ All tests passed!
```
```

---

## Задачи реализации

### Задача 4.1: Создать структуру проекта
**Оценка**: 15 минут

### Задача 4.2: Реализовать utils (logger, assertions)
**Оценка**: 30 минут

### Задача 4.3: Реализовать auth_tests.dart
**Оценка**: 45 минут

### Задача 4.4: Реализовать token_tests.dart
**Оценка**: 30 минут

### Задача 4.5: Реализовать rbac_tests.dart
**Оценка**: 30 минут

### Задача 4.6: Реализовать test_runner.dart
**Оценка**: 20 минут

### Задача 4.7: Реализовать main.dart
**Оценка**: 10 минут

### Задача 4.8: Создать README.md
**Оценка**: 10 минут

### Задача 4.9: Тестирование
**Оценка**: 20 минут

---

## Acceptance Criteria

- ✅ Все тесты запускаются
- ✅ Цветной вывод работает
- ✅ Exit code корректный (0 = success, 1 = failure)
- ✅ README полный

---

## Статус

- [ ] Задача 4.1: Структура проекта
- [ ] Задача 4.2: Utils
- [ ] Задача 4.3: auth_tests.dart
- [ ] Задача 4.4: token_tests.dart
- [ ] Задача 4.5: rbac_tests.dart
- [ ] Задача 4.6: test_runner.dart
- [ ] Задача 4.7: main.dart
- [ ] Задача 4.8: README.md
- [ ] Задача 4.9: Тестирование
