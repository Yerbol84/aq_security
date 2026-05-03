# Client Flutter — Детальный план

**Компонент**: Flutter Client (UI Demo)  
**Приоритет**: Средний  
**Оценка**: 6 часов  
**Статус**: Планирование

---

## Цель

Создать Flutter приложение, демонстрирующее:
- UI для всех auth провайдеров
- Login/Logout flow
- Profile management
- RBAC проверки в UI
- Session management

---

## Структура

```
client_flutter/
├── lib/
│   ├── main.dart               # Точка входа
│   ├── app.dart                # MaterialApp
│   ├── config.dart             # Конфигурация
│   ├── providers/
│   │   ├── auth_provider.dart  # Riverpod auth provider
│   │   └── config_provider.dart
│   ├── screens/
│   │   ├── login_screen.dart   # Выбор провайдера
│   │   ├── email_login_screen.dart
│   │   ├── google_login_screen.dart
│   │   ├── api_key_screen.dart
│   │   ├── home_screen.dart    # После логина
│   │   ├── profile_screen.dart
│   │   └── sessions_screen.dart
│   ├── widgets/
│   │   ├── auth_button.dart
│   │   ├── permission_badge.dart
│   │   └── session_card.dart
│   └── router.dart             # go_router
├── pubspec.yaml
└── README.md
```

---

## lib/main.dart

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app.dart';

void main() {
  runApp(
    const ProviderScope(
      child: AQSecurityDemoApp(),
    ),
  );
}
```

---

## lib/app.dart

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'router.dart';

class AQSecurityDemoApp extends ConsumerWidget {
  const AQSecurityDemoApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    
    return MaterialApp.router(
      title: 'AQ Security Demo',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      routerConfig: router,
    );
  }
}
```

---

## lib/config.dart

```dart
import 'package:flutter/foundation.dart';

final class AppConfig {
  const AppConfig({
    required this.authServiceUrl,
  });
  
  final String authServiceUrl;
  
  static AppConfig get current {
    // В production читать из environment
    return const AppConfig(
      authServiceUrl: kDebugMode
          ? 'http://localhost:8080'
          : 'https://auth.example.com',
    );
  }
}
```

---

## lib/providers/auth_provider.dart

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:aq_security/aq_security.dart';
import 'config_provider.dart';

// Security Service Provider
final securityServiceProvider = FutureProvider<AQSecurityService>((ref) async {
  final config = ref.watch(configProvider);
  final client = await AQSecurityClient.init(config.authServiceUrl);
  return client.service;
});

// Auth State Provider
final authStateProvider = StreamProvider<SecurityState>((ref) {
  final service = ref.watch(securityServiceProvider).value;
  if (service == null) {
    return Stream.value(SecurityState.unauthenticated());
  }
  return service.stateStream;
});

// Current User Provider
final currentUserProvider = Provider<AqUser?>((ref) {
  final authState = ref.watch(authStateProvider).value;
  return authState?.user;
});

// Is Authenticated Provider
final isAuthenticatedProvider = Provider<bool>((ref) {
  final authState = ref.watch(authStateProvider).value;
  return authState?.isAuthenticated ?? false;
});
```

---

## lib/screens/login_screen.dart

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class LoginScreen extends ConsumerWidget {
  const LoginScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('AQ Security Demo'),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(
                  Icons.security,
                  size: 80,
                  color: Colors.blue,
                ),
                const SizedBox(height: 32),
                const Text(
                  'Choose Login Method',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 48),
                
                // Email/Password
                ElevatedButton.icon(
                  onPressed: () => context.go('/login/email'),
                  icon: const Icon(Icons.email),
                  label: const Text('Email / Password'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.all(16),
                  ),
                ),
                const SizedBox(height: 16),
                
                // Google OAuth
                ElevatedButton.icon(
                  onPressed: () => context.go('/login/google'),
                  icon: const Icon(Icons.g_mobiledata),
                  label: const Text('Google OAuth'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.all(16),
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                  ),
                ),
                const SizedBox(height: 16),
                
                // API Key
                ElevatedButton.icon(
                  onPressed: () => context.go('/login/apikey'),
                  icon: const Icon(Icons.key),
                  label: const Text('API Key'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.all(16),
                    backgroundColor: Colors.orange,
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
```

---

## lib/screens/email_login_screen.dart

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../providers/auth_provider.dart';

class EmailLoginScreen extends ConsumerStatefulWidget {
  const EmailLoginScreen({super.key});

  @override
  ConsumerState<EmailLoginScreen> createState() => _EmailLoginScreenState();
}

class _EmailLoginScreenState extends ConsumerState<EmailLoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController(text: 'admin@test.com');
  final _passwordController = TextEditingController(text: 'admin123');
  bool _isLoading = false;
  String? _error;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;
    
    setState(() {
      _isLoading = true;
      _error = null;
    });
    
    try {
      final service = await ref.read(securityServiceProvider.future);
      await service.loginWithEmail(
        email: _emailController.text,
        password: _passwordController.text,
      );
      
      if (mounted) {
        context.go('/home');
      }
    } catch (e) {
      setState(() {
        _error = e.toString();
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Email / Password Login'),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextFormField(
                    controller: _emailController,
                    decoration: const InputDecoration(
                      labelText: 'Email',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.email),
                    ),
                    keyboardType: TextInputType.emailAddress,
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Please enter email';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _passwordController,
                    decoration: const InputDecoration(
                      labelText: 'Password',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.lock),
                    ),
                    obscureText: true,
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Please enter password';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 24),
                  
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Text(
                        _error!,
                        style: const TextStyle(color: Colors.red),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  
                  ElevatedButton(
                    onPressed: _isLoading ? null : _login,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.all(16),
                    ),
                    child: _isLoading
                        ? const CircularProgressIndicator()
                        : const Text('Login'),
                  ),
                  
                  const SizedBox(height: 16),
                  const Text(
                    'Test credentials:\nadmin@test.com / admin123',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
```

---

## lib/screens/home_screen.dart

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../providers/auth_provider.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('Home'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              final service = await ref.read(securityServiceProvider.future);
              await service.logout();
              if (context.mounted) {
                context.go('/');
              }
            },
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      children: [
                        const CircleAvatar(
                          radius: 40,
                          child: Icon(Icons.person, size: 40),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          user?.email ?? 'Unknown',
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Tenant: ${user?.tenantId ?? 'N/A'}',
                          style: const TextStyle(color: Colors.grey),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                
                ElevatedButton.icon(
                  onPressed: () => context.go('/profile'),
                  icon: const Icon(Icons.person),
                  label: const Text('Profile'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.all(16),
                  ),
                ),
                const SizedBox(height: 16),
                
                ElevatedButton.icon(
                  onPressed: () => context.go('/sessions'),
                  icon: const Icon(Icons.devices),
                  label: const Text('Active Sessions'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.all(16),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
```

---

## lib/router.dart

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'providers/auth_provider.dart';
import 'screens/login_screen.dart';
import 'screens/email_login_screen.dart';
import 'screens/home_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/sessions_screen.dart';

final routerProvider = Provider<GoRouter>((ref) {
  final isAuthenticated = ref.watch(isAuthenticatedProvider);
  
  return GoRouter(
    initialLocation: '/',
    redirect: (context, state) {
      if (!isAuthenticated && !state.matchedLocation.startsWith('/login')) {
        return '/';
      }
      if (isAuthenticated && state.matchedLocation == '/') {
        return '/home';
      }
      return null;
    },
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: '/login/email',
        builder: (context, state) => const EmailLoginScreen(),
      ),
      GoRoute(
        path: '/home',
        builder: (context, state) => const HomeScreen(),
      ),
      GoRoute(
        path: '/profile',
        builder: (context, state) => const ProfileScreen(),
      ),
      GoRoute(
        path: '/sessions',
        builder: (context, state) => const SessionsScreen(),
      ),
    ],
  );
});
```

---

## pubspec.yaml

```yaml
name: client_flutter
description: AQ Security Flutter Demo
version: 1.0.0

environment:
  sdk: ^3.3.0

dependencies:
  flutter:
    sdk: flutter
  flutter_riverpod: ^2.4.0
  go_router: ^13.0.0
  aq_security:
    path: ../..

dev_dependencies:
  flutter_test:
    sdk: flutter
  flutter_lints: ^3.0.0
```

---

## README.md

```markdown
# AQ Security Flutter Client

Flutter приложение, демонстрирующее все auth провайдеры.

## Экраны

- **Login Screen**: Выбор провайдера
- **Email Login**: Email/Password форма
- **Google Login**: OAuth redirect (TODO)
- **API Key**: Ввод API ключа (TODO)
- **Home**: Главный экран после логина
- **Profile**: Информация о пользователе
- **Sessions**: Активные сессии

## Запуск

```bash
# Установить зависимости
flutter pub get

# Запустить (требуется запущенный auth-сервер)
flutter run
```

## Тестовые credentials

- Email: `admin@test.com`
- Password: `admin123`

## TODO

- [ ] Google OAuth webview
- [ ] API Key screen
- [ ] Permissions UI
- [ ] Session revocation
- [ ] Profile editing
```

---

## Задачи реализации

### Задача 5.1: Создать структуру проекта
**Оценка**: 20 минут

### Задача 5.2: Настроить Riverpod providers
**Оценка**: 45 минут

### Задача 5.3: Реализовать router
**Оценка**: 30 минут

### Задача 5.4: Реализовать LoginScreen
**Оценка**: 30 минут

### Задача 5.5: Реализовать EmailLoginScreen
**Оценка**: 60 минут

### Задача 5.6: Реализовать HomeScreen
**Оценка**: 45 минут

### Задача 5.7: Реализовать ProfileScreen
**Оценка**: 45 минут

### Задача 5.8: Реализовать SessionsScreen
**Оценка**: 45 минут

### Задача 5.9: Создать README.md
**Оценка**: 15 минут

### Задача 5.10: Тестирование
**Оценка**: 45 минут

---

## Acceptance Criteria

- ✅ Приложение запускается
- ✅ Email login работает
- ✅ Logout работает
- ✅ Навигация работает
- ✅ Profile отображается
- ✅ README полный

---

## Статус

- [ ] Задача 5.1: Структура проекта
- [ ] Задача 5.2: Riverpod providers
- [ ] Задача 5.3: Router
- [ ] Задача 5.4: LoginScreen
- [ ] Задача 5.5: EmailLoginScreen
- [ ] Задача 5.6: HomeScreen
- [ ] Задача 5.7: ProfileScreen
- [ ] Задача 5.8: SessionsScreen
- [ ] Задача 5.9: README.md
- [ ] Задача 5.10: Тестирование
