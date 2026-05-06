// pkgs/aq_security/lib/src/client/http_auth_transport.dart
//
// HTTP client for the auth server API.
// All network calls go through here.
// Pure Dart — uses package:http.

import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:aq_schema/security/security.dart';

/// Low-level HTTP transport. Used internally by [AQSecurityService].
final class HttpAuthTransport {
  HttpAuthTransport({required this.baseUrl, http.Client? client})
      : _client = client ?? http.Client();

  final String baseUrl;
  final http.Client _client;

  // ── Public endpoints ───────────────────────────────────────────────────────

  Future<void> healthCheck() async {
    final response = await _get('/auth/health');
    _expect(response, 200, 'Auth server unreachable');
  }

  Future<AuthResponse> login(AuthRequest request) async {
    final response = await _post('/auth/login', request.toJson());
    _expect(response, 200, 'Login failed');
    return AuthResponse.fromJson(_decode(response));
  }

  Future<TokenPair> refresh(String refreshToken) async {
    final response = await _post('/auth/refresh', {'refreshToken': refreshToken});
    _expect(response, 200, 'Token refresh failed');
    return TokenPair.fromJson(_decode(response));
  }

  Future<AuthResponse> getMe(String accessToken) async {
    final response = await _get('/auth/me', bearerToken: accessToken);
    _expect(response, 200, 'Failed to fetch user');
    return AuthResponse.fromJson(_decode(response));
  }

  Future<void> logout(String accessToken) async {
    await _post('/auth/logout', {}, bearerToken: accessToken);
  }

  Future<AuthResponse> register({
    required String email,
    required String password,
    String? displayName,
  }) async {
    final response = await _post('/auth/register', {
      'email': email,
      'password': password,
      if (displayName != null) 'displayName': displayName,
    });
    _expect(response, 201, 'Registration failed');
    return AuthResponse.fromJson(_decode(response));
  }

  Future<List<AqSession>> listSessions(String accessToken) async {
    final response = await _get('/auth/sessions', bearerToken: accessToken);
    _expect(response, 200, 'Failed to fetch sessions');
    final list = jsonDecode(response.body) as List<dynamic>;
    return list
        .map((e) => AqSession.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> revokeSession(String sessionId, String accessToken) async {
    final response = await _delete(
      '/auth/sessions/$sessionId',
      bearerToken: accessToken,
    );
    _expect(response, 204, 'Failed to revoke session');
  }

  Future<ValidateTokenResponse> validate(ValidateTokenRequest request) async {
    final response = await _post('/auth/validate', request.toJson());
    _expect(response, 200, 'Validation call failed');
    return ValidateTokenResponse.fromJson(_decode(response));
  }

  Future<Map<String, dynamic>> createApiKey(
    String name,
    List<String> permissions,
    String accessToken,
  ) async {
    final response = await _post(
      '/auth/api-keys',
      {'name': name, 'permissions': permissions},
      bearerToken: accessToken,
    );
    _expect(response, 201, 'Failed to create API key');
    return _decode(response);
  }

  Future<void> revokeApiKey(String id, String accessToken) async {
    await _delete('/auth/api-keys/$id', bearerToken: accessToken);
  }

  // ── Private HTTP helpers ───────────────────────────────────────────────────

  Future<http.Response> _get(String path, {String? bearerToken}) {
    final uri = Uri.parse('$baseUrl$path');
    return _client.get(uri, headers: _headers(bearerToken));
  }

  Future<http.Response> _post(
    String path,
    Map<String, dynamic> body, {
    String? bearerToken,
  }) {
    final uri = Uri.parse('$baseUrl$path');
    return _client.post(
      uri,
      headers: _headers(bearerToken),
      body: jsonEncode(body),
    );
  }

  Future<http.Response> _delete(String path, {String? bearerToken}) {
    final uri = Uri.parse('$baseUrl$path');
    return _client.delete(uri, headers: _headers(bearerToken));
  }

  Map<String, String> _headers(String? bearerToken) => {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        if (bearerToken != null) 'Authorization': 'Bearer $bearerToken',
      };

  Map<String, dynamic> _decode(http.Response r) =>
      jsonDecode(r.body) as Map<String, dynamic>;

  void _expect(http.Response response, int expectedCode, String context) {
    if (response.statusCode != expectedCode) {
      String message = context;
      try {
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        message = body['message'] as String? ?? context;
      } catch (_) {}
      throw SecurityTransportException(
        message,
        statusCode: response.statusCode,
      );
    }
  }
}

final class SecurityTransportException implements Exception {
  const SecurityTransportException(this.message, {this.statusCode});
  final String message;
  final int? statusCode;

  @override
  String toString() => 'SecurityTransportException[$statusCode]: $message';
}
