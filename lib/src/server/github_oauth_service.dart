// pkgs/aq_security/lib/src/server/github_oauth_service.dart
//
// GitHub OAuth 2.0 integration.
// Docs: https://docs.github.com/en/apps/oauth-apps/building-oauth-apps/authorizing-oauth-apps

import 'dart:convert';
import 'package:http/http.dart' as http;

/// GitHub OAuth configuration.
final class GitHubOAuthConfig {
  const GitHubOAuthConfig({
    required this.clientId,
    required this.clientSecret,
  });

  final String clientId;
  final String clientSecret;
}

/// GitHub user info после успешной авторизации.
final class GitHubUser {
  const GitHubUser({
    required this.id,
    required this.login,
    required this.email,
    required this.name,
    required this.avatarUrl,
  });

  final int id;
  final String login;
  final String? email;
  final String? name;
  final String avatarUrl;

  factory GitHubUser.fromJson(Map<String, dynamic> json) {
    return GitHubUser(
      id: json['id'] as int,
      login: json['login'] as String,
      email: json['email'] as String?,
      name: json['name'] as String?,
      avatarUrl: json['avatar_url'] as String,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'login': login,
        'email': email,
        'name': name,
        'avatar_url': avatarUrl,
      };
}

/// GitHub OAuth service.
final class GitHubOAuthService {
  GitHubOAuthService({
    required this.config,
    http.Client? httpClient,
  }) : _http = httpClient ?? http.Client();

  final GitHubOAuthConfig config;
  final http.Client _http;

  /// Обменивает authorization code на access token и получает user info.
  Future<GitHubUser> exchangeCode({
    required String code,
    required String redirectUri,
  }) async {
    // Step 1: Exchange code for access token
    final tokenResponse = await _http.post(
      Uri.https('github.com', '/login/oauth/access_token'),
      headers: {
        'Accept': 'application/json',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'client_id': config.clientId,
        'client_secret': config.clientSecret,
        'code': code,
        'redirect_uri': redirectUri,
      }),
    );

    if (tokenResponse.statusCode != 200) {
      throw GitHubOAuthException(
        'Token exchange failed: ${tokenResponse.statusCode} ${tokenResponse.body}',
      );
    }

    final tokenData = jsonDecode(tokenResponse.body) as Map<String, dynamic>;

    if (tokenData.containsKey('error')) {
      throw GitHubOAuthException(
        'GitHub OAuth error: ${tokenData['error']} - ${tokenData['error_description']}',
      );
    }

    final accessToken = tokenData['access_token'] as String?;
    if (accessToken == null) {
      throw GitHubOAuthException('No access_token in response');
    }

    // Step 2: Get user info
    final userResponse = await _http.get(
      Uri.https('api.github.com', '/user'),
      headers: {
        'Accept': 'application/vnd.github+json',
        'Authorization': 'Bearer $accessToken',
        'X-GitHub-Api-Version': '2022-11-28',
      },
    );

    if (userResponse.statusCode != 200) {
      throw GitHubOAuthException(
        'User info request failed: ${userResponse.statusCode} ${userResponse.body}',
      );
    }

    final userData = jsonDecode(userResponse.body) as Map<String, dynamic>;

    // Step 3: Get primary email if not public
    String? email = userData['email'] as String?;
    if (email == null) {
      final emailsResponse = await _http.get(
        Uri.https('api.github.com', '/user/emails'),
        headers: {
          'Accept': 'application/vnd.github+json',
          'Authorization': 'Bearer $accessToken',
          'X-GitHub-Api-Version': '2022-11-28',
        },
      );

      if (emailsResponse.statusCode == 200) {
        final emails = jsonDecode(emailsResponse.body) as List<dynamic>;
        final primaryEmail = emails.firstWhere(
          (e) => e['primary'] == true,
          orElse: () => emails.isNotEmpty ? emails.first : null,
        );
        if (primaryEmail != null) {
          email = primaryEmail['email'] as String?;
        }
      }
    }

    return GitHubUser.fromJson({
      ...userData,
      'email': email,
    });
  }

  void dispose() {
    _http.close();
  }
}

/// GitHub OAuth exception.
final class GitHubOAuthException implements Exception {
  const GitHubOAuthException(this.message);

  final String message;

  @override
  String toString() => 'GitHubOAuthException: $message';
}
