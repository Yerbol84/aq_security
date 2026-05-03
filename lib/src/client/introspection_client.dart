// pkgs/aq_security/lib/src/client/introspection_client.dart
//
// HTTP клиент для вызова Token Introspection endpoint.
// Используется Resource Servers (Data Service) для проверки прав доступа.

import 'dart:convert';
import 'package:http/http.dart' as http;

/// Клиент для Token Introspection (RFC 7662).
class IntrospectionClient {
  IntrospectionClient({
    required this.introspectionEndpoint,
    this.timeout = const Duration(seconds: 5),
  });

  final String introspectionEndpoint;
  final Duration timeout;

  /// Проверить может ли токен выполнить действие на ресурсе.
  Future<IntrospectionResponse> introspect({
    required String token,
    required String resource,
    required String action,
    required String resourceId,
    Map<String, dynamic>? context,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse(introspectionEndpoint),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'token': token,
              'resource': resource,
              'action': action,
              'resourceId': resourceId,
              if (context != null) 'context': context,
            }),
          )
          .timeout(timeout);

      if (response.statusCode != 200) {
        throw IntrospectionException(
          'Introspection failed: ${response.statusCode} ${response.body}',
        );
      }

      return IntrospectionResponse.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>,
      );
    } catch (e) {
      throw IntrospectionException('Introspection error: $e');
    }
  }
}

/// Ответ от introspection endpoint.
class IntrospectionResponse {
  IntrospectionResponse({
    required this.active,
    required this.allowed,
    this.userId,
    this.tenantId,
    this.scopes = const [],
    this.roles = const [],
    this.expiresAt,
    this.reason,
  });

  /// Токен активен (не истёк, валидная подпись).
  final bool active;

  /// Доступ разрешён.
  final bool allowed;

  /// User ID из токена.
  final String? userId;

  /// Tenant ID из токена.
  final String? tenantId;

  /// Эффективные права пользователя (scopes).
  final List<String> scopes;

  /// Роли пользователя.
  final List<String> roles;

  /// Время истечения токена (unix timestamp).
  final int? expiresAt;

  /// Причина отказа (если allowed = false).
  final String? reason;

  factory IntrospectionResponse.fromJson(Map<String, dynamic> json) {
    return IntrospectionResponse(
      active: json['active'] as bool,
      allowed: json['allowed'] as bool,
      userId: json['userId'] as String?,
      tenantId: json['tenantId'] as String?,
      scopes: (json['scopes'] as List<dynamic>?)?.cast<String>() ?? [],
      roles: (json['roles'] as List<dynamic>?)?.cast<String>() ?? [],
      expiresAt: json['expiresAt'] as int?,
      reason: json['reason'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'active': active,
        'allowed': allowed,
        if (userId != null) 'userId': userId,
        if (tenantId != null) 'tenantId': tenantId,
        'scopes': scopes,
        'roles': roles,
        if (expiresAt != null) 'expiresAt': expiresAt,
        if (reason != null) 'reason': reason,
      };

  @override
  String toString() => 'IntrospectionResponse('
      'active: $active, '
      'allowed: $allowed, '
      'userId: $userId, '
      'tenantId: $tenantId, '
      'scopes: ${scopes.length}, '
      'reason: $reason)';
}

/// Исключение при introspection.
class IntrospectionException implements Exception {
  IntrospectionException(this.message);

  final String message;

  @override
  String toString() => 'IntrospectionException: $message';
}
