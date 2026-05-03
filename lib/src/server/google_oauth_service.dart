// pkgs/aq_security/lib/src/server/google_oauth_service.dart
//
// Server-only. Exchanges Google OAuth2 authorization code for user info.
// Flow: frontend gets code → sends to POST /auth/login → we exchange here.
//
// Required env vars:
//   GOOGLE_CLIENT_ID
//   GOOGLE_CLIENT_SECRET

import 'dart:convert';
import 'package:http/http.dart' as http;

final class GoogleUserInfo {
  const GoogleUserInfo({
    required this.sub,
    required this.email,
    required this.emailVerified,
    this.name,
    this.picture,
  });

  /// Google user ID — stable unique identifier.
  final String sub;
  final String email;
  final bool emailVerified;
  final String? name;
  final String? picture;
}

final class GoogleOAuthConfig {
  const GoogleOAuthConfig({
    required this.clientId,
    required this.clientSecret,
  });

  final String clientId;
  final String clientSecret;
}

final class GoogleOAuthService {
  GoogleOAuthService({required this.config, http.Client? client})
      : _client = client ?? http.Client();

  final GoogleOAuthConfig config;
  final http.Client _client;

  static const _tokenUrl = 'https://oauth2.googleapis.com/token';
  static const _userInfoUrl = 'https://www.googleapis.com/oauth2/v3/userinfo';

  /// Exchange authorization code for Google user info.
  Future<GoogleUserInfo> exchangeCode({
    required String code,
    required String redirectUri,
  }) async {
    // Step 1: Exchange code for access token
    final tokenResponse = await _client.post(
      Uri.parse(_tokenUrl),
      headers: {'Content-Type': 'application/x-www-form-urlencoded'},
      body: {
        'code': code,
        'client_id': config.clientId,
        'client_secret': config.clientSecret,
        'redirect_uri': redirectUri,
        'grant_type': 'authorization_code',
      },
    );

    if (tokenResponse.statusCode != 200) {
      final body = jsonDecode(tokenResponse.body) as Map<String, dynamic>;
      throw GoogleOAuthException(
        body['error_description'] as String? ??
            body['error'] as String? ??
            'Google token exchange failed',
      );
    }

    final tokenData = jsonDecode(tokenResponse.body) as Map<String, dynamic>;
    final googleAccessToken = tokenData['access_token'] as String?;

    if (googleAccessToken == null) {
      throw const GoogleOAuthException('No access_token in Google response');
    }

    // Step 2: Fetch user info
    final userResponse = await _client.get(
      Uri.parse(_userInfoUrl),
      headers: {'Authorization': 'Bearer $googleAccessToken'},
    );

    if (userResponse.statusCode != 200) {
      throw const GoogleOAuthException('Failed to fetch Google user info');
    }

    final userData = jsonDecode(userResponse.body) as Map<String, dynamic>;

    return GoogleUserInfo(
      sub: userData['sub'] as String,
      email: userData['email'] as String,
      emailVerified: userData['email_verified'] as bool? ?? false,
      name: userData['name'] as String?,
      picture: userData['picture'] as String?,
    );
  }
}

final class GoogleOAuthException implements Exception {
  const GoogleOAuthException(this.message);
  final String message;
  @override
  String toString() => 'GoogleOAuthException: $message';
}
