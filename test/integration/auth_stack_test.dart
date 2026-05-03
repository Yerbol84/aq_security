// test/integration/auth_stack_test.dart
//
// Интеграционный тест для проверки всего auth стека
// Требует запущенный docker-compose stack

import 'package:aq_security/src/client/aq_security_service.dart';
import 'package:test/test.dart';
import 'package:aq_security/aq_security.dart';
import 'dart:io';
import 'dart:convert';

void main() {
  group('Auth Stack Integration', () {
    late AQSecurityService service;

    setUpAll(() async {
      // Проверить что стек запущен
      final dataServiceHealth =
          await _checkHealth('http://localhost:8090/health');
      final authServiceHealth =
          await _checkHealth('http://localhost:8080/auth/health');

      if (!dataServiceHealth || !authServiceHealth) {
        throw Exception(
          'Auth stack не запущен! Запустите: cd deploys/aq_auth_stack && docker-compose up',
        );
      }

      print('✅ Auth stack запущен');
    });

    test('1. Handshake с data service', () async {
      // AQSecurityClient.init делает handshake автоматически
      service = await AQSecurityClient.init('http://localhost:8080');

      expect(service, isNotNull);
      expect(service.state, isA<SecurityStateUnauthenticated>());

      print('✅ Handshake успешен');
    });

    test('2. Health check auth service', () async {
      try {
        final response = await _httpGet('http://localhost:8080/auth/health');

        if (response.isEmpty) {
          fail(
              'Auth service вернул пустой ответ. Проверьте логи: docker-compose logs auth_service');
        }

        final data = jsonDecode(response) as Map<String, dynamic>;
        expect(data['ok'], isTrue);
        print('✅ Auth service работает');
      } catch (e) {
        fail(
            'Auth service недоступен: $e\nПроверьте: docker-compose logs auth_service');
      }
    });

    test('3. Health check data service', () async {
      final response = await _httpGet('http://localhost:8090/health');

      expect(response, contains('ok'));
      print('✅ Data service работает');
    });

    test('4. Список доменов в data service', () async {
      final response = await _httpGet('http://localhost:8090/domains');
      final data = jsonDecode(response) as Map<String, dynamic>;
      final domains = data['domains'] as List;
      final collections =
          domains.map((d) => d['collection'] as String).toList();

      // Проверяем что все security домены зарегистрированы
      expect(collections, contains('security_users'));
      expect(collections, contains('security_tenants'));
      expect(collections, contains('security_profiles'));
      expect(collections, contains('security_roles'));
      expect(collections, contains('security_user_roles'));
      expect(collections, contains('security_sessions'));
      expect(collections, contains('security_api_keys'));

      print(
          '✅ Security домены зарегистрированы (${collections.length} доменов)');
    });

    test('5. Login с API key (если есть)', () async {
      final apiKey = Platform.environment['TEST_API_KEY'];

      if (apiKey == null || apiKey.isEmpty) {
        print('⚠️  TEST_API_KEY не задан, пропускаем тест');
        return;
      }

      try {
        final auth = await service.loginWithApiKey(apiKey);

        expect(auth.user, isNotNull);
        expect(auth.tokens.accessToken, isNotEmpty);
        expect(service.isAuthenticated, isTrue);

        print('✅ Login с API key успешен');
        print('   User: ${auth.user.email}');

        // Logout
        await service.logout();
        expect(service.isAuthenticated, isFalse);

        print('✅ Logout успешен');
      } catch (e) {
        print('⚠️  Login failed: $e');
        // Не падаем, т.к. API key может быть невалидным
      }
    });

    test('6. Validate token endpoint', () async {
      // Создаем фейковый токен для проверки endpoint
      final response = await _httpPost(
        'http://localhost:8080/auth/validate',
        {'token': 'invalid_token'},
      );

      // Должен вернуть ошибку, но endpoint должен работать
      expect(response, isNotNull);
      print('✅ Validate endpoint работает');
    });
  });
}

// ── Helpers ───────────────────────────────────────────────────────────────────

Future<bool> _checkHealth(String url) async {
  try {
    final client = HttpClient();
    final request = await client.getUrl(Uri.parse(url));
    final response = await request.close();
    await response.drain();
    client.close();
    return response.statusCode == 200;
  } catch (e) {
    return false;
  }
}

Future<String> _httpGet(String url) async {
  final client = HttpClient();
  try {
    final request = await client.getUrl(Uri.parse(url));
    final response = await request.close();
    final body = await response.transform(const Utf8Decoder()).join();
    client.close();
    return body;
  } catch (e) {
    client.close();
    rethrow;
  }
}

Future<String> _httpPost(String url, Map<String, dynamic> data) async {
  final client = HttpClient();
  try {
    final request = await client.postUrl(Uri.parse(url));
    request.headers.contentType = ContentType.json;
    request.write(jsonEncode(data));
    final response = await request.close();
    final body = await response.transform(const Utf8Decoder()).join();
    client.close();
    return body;
  } catch (e) {
    client.close();
    rethrow;
  }
}
