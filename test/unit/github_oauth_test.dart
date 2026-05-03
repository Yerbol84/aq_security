// test/unit/github_oauth_test.dart
//
// Тесты для GitHub OAuth integration

import 'package:test/test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'dart:convert';
import 'package:aq_security/aq_security_server.dart';

void main() {
  group('GitHubOAuthService', () {
    test('exchangeCode успешно обменивает code на user info', () async {
      final mockClient = MockClient((request) async {
        // Mock token exchange
        if (request.url.path == '/login/oauth/access_token') {
          return http.Response(
            jsonEncode({'access_token': 'gho_test_token'}),
            200,
            headers: {'content-type': 'application/json'},
          );
        }

        // Mock user info
        if (request.url.path == '/user') {
          return http.Response(
            jsonEncode({
              'id': 12345,
              'login': 'testuser',
              'email': 'test@example.com',
              'name': 'Test User',
              'avatar_url': 'https://avatars.githubusercontent.com/u/12345',
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }

        return http.Response('Not Found', 404);
      });

      final service = GitHubOAuthService(
        config: const GitHubOAuthConfig(
          clientId: 'test_client_id',
          clientSecret: 'test_client_secret',
        ),
        httpClient: mockClient,
      );

      final user = await service.exchangeCode(
        code: 'test_code',
        redirectUri: 'http://localhost:3000/callback',
      );

      expect(user.id, equals(12345));
      expect(user.login, equals('testuser'));
      expect(user.email, equals('test@example.com'));
      expect(user.name, equals('Test User'));
      expect(user.avatarUrl, contains('avatars.githubusercontent.com'));

      service.dispose();
    });

    test('exchangeCode получает email из /user/emails если не публичный', () async {
      final mockClient = MockClient((request) async {
        // Mock token exchange
        if (request.url.path == '/login/oauth/access_token') {
          return http.Response(
            jsonEncode({'access_token': 'gho_test_token'}),
            200,
            headers: {'content-type': 'application/json'},
          );
        }

        // Mock user info без email
        if (request.url.path == '/user') {
          return http.Response(
            jsonEncode({
              'id': 12345,
              'login': 'testuser',
              'email': null, // email не публичный
              'name': 'Test User',
              'avatar_url': 'https://avatars.githubusercontent.com/u/12345',
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }

        // Mock emails endpoint
        if (request.url.path == '/user/emails') {
          return http.Response(
            jsonEncode([
              {'email': 'secondary@example.com', 'primary': false, 'verified': true},
              {'email': 'primary@example.com', 'primary': true, 'verified': true},
            ]),
            200,
            headers: {'content-type': 'application/json'},
          );
        }

        return http.Response('Not Found', 404);
      });

      final service = GitHubOAuthService(
        config: const GitHubOAuthConfig(
          clientId: 'test_client_id',
          clientSecret: 'test_client_secret',
        ),
        httpClient: mockClient,
      );

      final user = await service.exchangeCode(
        code: 'test_code',
        redirectUri: 'http://localhost:3000/callback',
      );

      expect(user.email, equals('primary@example.com'));

      service.dispose();
    });

    test('exchangeCode выбрасывает исключение при ошибке token exchange', () async {
      final mockClient = MockClient((request) async {
        if (request.url.path == '/login/oauth/access_token') {
          return http.Response(
            jsonEncode({
              'error': 'bad_verification_code',
              'error_description': 'The code passed is incorrect or expired.',
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('Not Found', 404);
      });

      final service = GitHubOAuthService(
        config: const GitHubOAuthConfig(
          clientId: 'test_client_id',
          clientSecret: 'test_client_secret',
        ),
        httpClient: mockClient,
      );

      expect(
        () => service.exchangeCode(
          code: 'invalid_code',
          redirectUri: 'http://localhost:3000/callback',
        ),
        throwsA(isA<GitHubOAuthException>()),
      );

      service.dispose();
    });

    test('exchangeCode выбрасывает исключение при HTTP ошибке', () async {
      final mockClient = MockClient((request) async {
        if (request.url.path == '/login/oauth/access_token') {
          return http.Response('Internal Server Error', 500);
        }
        return http.Response('Not Found', 404);
      });

      final service = GitHubOAuthService(
        config: const GitHubOAuthConfig(
          clientId: 'test_client_id',
          clientSecret: 'test_client_secret',
        ),
        httpClient: mockClient,
      );

      expect(
        () => service.exchangeCode(
          code: 'test_code',
          redirectUri: 'http://localhost:3000/callback',
        ),
        throwsA(isA<GitHubOAuthException>()),
      );

      service.dispose();
    });

    test('exchangeCode выбрасывает исключение если нет access_token', () async {
      final mockClient = MockClient((request) async {
        if (request.url.path == '/login/oauth/access_token') {
          return http.Response(
            jsonEncode({'error': 'no_token'}),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('Not Found', 404);
      });

      final service = GitHubOAuthService(
        config: const GitHubOAuthConfig(
          clientId: 'test_client_id',
          clientSecret: 'test_client_secret',
        ),
        httpClient: mockClient,
      );

      expect(
        () => service.exchangeCode(
          code: 'test_code',
          redirectUri: 'http://localhost:3000/callback',
        ),
        throwsA(isA<GitHubOAuthException>()),
      );

      service.dispose();
    });
  });

  group('GitHubUser', () {
    test('fromJson корректно парсит JSON', () {
      final json = {
        'id': 12345,
        'login': 'testuser',
        'email': 'test@example.com',
        'name': 'Test User',
        'avatar_url': 'https://avatars.githubusercontent.com/u/12345',
      };

      final user = GitHubUser.fromJson(json);

      expect(user.id, equals(12345));
      expect(user.login, equals('testuser'));
      expect(user.email, equals('test@example.com'));
      expect(user.name, equals('Test User'));
      expect(user.avatarUrl, contains('avatars.githubusercontent.com'));
    });

    test('fromJson обрабатывает null email и name', () {
      final json = {
        'id': 12345,
        'login': 'testuser',
        'email': null,
        'name': null,
        'avatar_url': 'https://avatars.githubusercontent.com/u/12345',
      };

      final user = GitHubUser.fromJson(json);

      expect(user.id, equals(12345));
      expect(user.login, equals('testuser'));
      expect(user.email, isNull);
      expect(user.name, isNull);
    });

    test('toJson корректно сериализует в JSON', () {
      const user = GitHubUser(
        id: 12345,
        login: 'testuser',
        email: 'test@example.com',
        name: 'Test User',
        avatarUrl: 'https://avatars.githubusercontent.com/u/12345',
      );

      final json = user.toJson();

      expect(json['id'], equals(12345));
      expect(json['login'], equals('testuser'));
      expect(json['email'], equals('test@example.com'));
      expect(json['name'], equals('Test User'));
      expect(json['avatar_url'], contains('avatars.githubusercontent.com'));
    });
  });
}
