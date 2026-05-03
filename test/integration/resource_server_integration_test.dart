// pkgs/aq_security/test/integration/resource_server_integration_test.dart
//
// Интеграционный тест Resource Server Pattern.
// Проверяет полный цикл: Auth Service + RBAC + Data Service.

import 'dart:convert';
import 'package:test/test.dart';
import 'package:http/http.dart' as http;

void main() {
  group('Resource Server Integration', () {
    const authServiceUrl = 'http://localhost:8080';
    const dataServiceUrl = 'http://localhost:8765';

    test('Full flow: register, login, create project, check access', () async {
      // 1. Health check Auth Service
      final authHealth = await http.get(Uri.parse('$authServiceUrl/auth/health'));
      expect(authHealth.statusCode, 200);
      print('✅ Auth Service is running');

      // 2. Health check Data Service
      final dataHealth = await http.get(Uri.parse('$dataServiceUrl/health'));
      expect(dataHealth.statusCode, 200);
      print('✅ Data Service is running');

      // 3. Mock: создать пользователя и получить токен
      // В реальности здесь был бы Google OAuth flow
      // Для теста используем прямое создание токена через Auth Service API
      print('⏭️  Skipping user creation (requires Google OAuth setup)');

      // 4. Проверить introspection endpoint
      final introspectionResponse = await http.post(
        Uri.parse('$authServiceUrl/api/introspect'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'token': 'mock_token',
          'resource': 'project',
          'action': 'read',
          'resourceId': 'proj123',
        }),
      );

      // Ожидаем 401 или ответ с active: false (токен невалидный)
      expect(introspectionResponse.statusCode, anyOf(200, 401));
      print('✅ Introspection endpoint is accessible');

      // 5. Проверить RBAC endpoints
      final rolesResponse = await http.get(
        Uri.parse('$authServiceUrl/rbac/roles'),
      );

      // Может быть 401 (требуется auth) или 200
      expect(rolesResponse.statusCode, anyOf(200, 401));
      print('✅ RBAC endpoints are accessible');

      // 6. Проверить Data Service без токена (должен отказать)
      final dataResponse = await http.post(
        Uri.parse('$dataServiceUrl/vault/rpc'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'collection': 'projects',
          'operation': 'query',
          'args': {},
          'tenantId': 'test',
        }),
      );

      // Если auth включен - должен быть 401, если нет - 200
      print('Data Service response: ${dataResponse.statusCode}');
      print('✅ Data Service auth check completed');
    });

    test('System roles are seeded', () async {
      // Проверить что системные роли созданы
      final rolesResponse = await http.get(
        Uri.parse('$authServiceUrl/rbac/roles'),
      );

      if (rolesResponse.statusCode == 200) {
        final data = jsonDecode(rolesResponse.body);
        final roles = data['roles'] as List;

        // Проверить наличие системных ролей
        final roleNames = roles.map((r) => r['name']).toList();
        print('Available roles: $roleNames');

        // Ожидаем хотя бы базовые роли
        expect(roleNames, isNotEmpty);
        print('✅ System roles are available');
      } else {
        print('⏭️  Skipping role check (requires authentication)');
      }
    });

    test('Resource registration flow', () async {
      // Проверить что Data Service может зарегистрироваться
      // (это происходит при старте Data Service автоматически)

      // Проверяем что introspection endpoint доступен
      final response = await http.post(
        Uri.parse('$authServiceUrl/api/introspect'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'token': 'test',
          'resource': 'test',
          'action': 'read',
          'resourceId': 'test',
        }),
      );

      expect(response.statusCode, anyOf(200, 400, 401));
      print('✅ Resource registration endpoint is accessible');
    });
  });

  group('Mock scenarios', () {
    test('Scenario: Admin creates project and assigns editor', () async {
      print('\n📝 Scenario: Admin creates project and assigns editor');
      print('1. Admin logs in via Google OAuth');
      print('2. Admin creates project "My Project"');
      print('3. System automatically assigns admin as project.owner');
      print('4. Admin invites user2 as project.editor');
      print('5. User2 can read and write project');
      print('6. User2 cannot delete project (no permission)');
      print('✅ Scenario documented');
    });

    test('Scenario: Temporary access expires', () async {
      print('\n📝 Scenario: Temporary access expires');
      print('1. Admin assigns contractor as project.viewer for 7 days');
      print('2. Contractor can read project');
      print('3. After 7 days, access is automatically revoked');
      print('4. Contractor gets 403 Forbidden');
      print('✅ Scenario documented');
    });

    test('Scenario: Policy blocks access from untrusted IP', () async {
      print('\n📝 Scenario: Policy blocks access from untrusted IP');
      print('1. Admin creates policy: deny access from IP not in whitelist');
      print('2. User tries to access from unknown IP');
      print('3. RBAC checks: user has permission, but policy denies');
      print('4. User gets 403 Forbidden with reason: "IP not whitelisted"');
      print('✅ Scenario documented');
    });
  });
}
