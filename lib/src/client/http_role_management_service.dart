// pkgs/aq_security/lib/src/client/http_role_management_service.dart
//
// HTTP-клиент для IRoleManagementService.
// Вызывает /rbac/* endpoints auth сервера.

import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:aq_schema/security/security.dart';

/// HTTP-реализация IRoleManagementService.
/// Делегирует все операции серверному RBACRouter через HTTP.
final class HttpRoleManagementService implements IRoleManagementService {
  HttpRoleManagementService({
    required String baseUrl,
    required Future<String?> Function() tokenProvider,
  })  : _base = baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl,
        _tokenProvider = tokenProvider;

  final String _base;
  final Future<String?> Function() _tokenProvider;

  Future<Map<String, String>> _headers() async {
    final token = await _tokenProvider();
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  Map<String, dynamic> _decode(http.Response res) {
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    if (res.statusCode >= 400) {
      throw Exception(body['error'] ?? 'HTTP ${res.statusCode}');
    }
    return body;
  }

  // ── CRUD ──────────────────────────────────────────────────────────────────

  @override
  Future<List<AqRole>> getRoles() async {
    final res = await http.get(
      Uri.parse('$_base/rbac/roles'),
      headers: await _headers(),
    );
    final body = _decode(res);
    return (body['roles'] as List).map((e) => AqRole.fromJson(e as Map<String, dynamic>)).toList();
  }

  @override
  Future<AqRole?> getRole(String roleId) async {
    final res = await http.get(
      Uri.parse('$_base/rbac/roles/$roleId'),
      headers: await _headers(),
    );
    if (res.statusCode == 404) return null;
    final body = _decode(res);
    return AqRole.fromJson(body['role'] as Map<String, dynamic>);
  }

  @override
  Future<AqRole> createRole({
    required String name,
    String? description,
    required List<String> permissions,
  }) async {
    final res = await http.post(
      Uri.parse('$_base/rbac/roles'),
      headers: await _headers(),
      body: jsonEncode({
        'name': name,
        if (description != null) 'description': description,
        'permissions': permissions,
      }),
    );
    final body = _decode(res);
    return AqRole.fromJson(body['role'] as Map<String, dynamic>);
  }

  @override
  Future<AqRole> updateRole({
    required String roleId,
    String? name,
    String? description,
    List<String>? permissions,
  }) async {
    final res = await http.put(
      Uri.parse('$_base/rbac/roles/$roleId'),
      headers: await _headers(),
      body: jsonEncode({
        if (name != null) 'name': name,
        if (description != null) 'description': description,
        if (permissions != null) 'permissions': permissions,
      }),
    );
    final body = _decode(res);
    return AqRole.fromJson(body['role'] as Map<String, dynamic>);
  }

  @override
  Future<void> deleteRole(String roleId) async {
    final res = await http.delete(
      Uri.parse('$_base/rbac/roles/$roleId'),
      headers: await _headers(),
    );
    _decode(res);
  }

  // ── Assignments ───────────────────────────────────────────────────────────

  @override
  Future<void> assignRole({
    required String userId,
    required String roleId,
    int? expiresAt,
  }) async {
    final res = await http.post(
      Uri.parse('$_base/rbac/users/$userId/roles'),
      headers: await _headers(),
      body: jsonEncode({
        'roleId': roleId,
        if (expiresAt != null) 'expiresAt': expiresAt,
      }),
    );
    _decode(res);
  }

  @override
  Future<void> revokeRole({
    required String userId,
    required String roleId,
  }) async {
    final res = await http.delete(
      Uri.parse('$_base/rbac/users/$userId/roles/$roleId'),
      headers: await _headers(),
    );
    _decode(res);
  }

  @override
  Future<List<AqRole>> getUserRoles(String userId) async {
    final res = await http.get(
      Uri.parse('$_base/rbac/users/$userId/roles'),
      headers: await _headers(),
    );
    final body = _decode(res);
    return (body['roles'] as List).map((e) => AqRole.fromJson(e as Map<String, dynamic>)).toList();
  }

  @override
  Future<List<AqUser>> getUsersByRole(String roleId) async {
    final res = await http.get(
      Uri.parse('$_base/rbac/roles/$roleId/users'),
      headers: await _headers(),
    );
    final body = _decode(res);
    return (body['users'] as List).map((e) => AqUser.fromJson(e as Map<String, dynamic>)).toList();
  }

  @override
  Future<List<String>> getAllPermissions() async {
    final res = await http.get(
      Uri.parse('$_base/rbac/permissions'),
      headers: await _headers(),
    );
    final body = _decode(res);
    return (body['permissions'] as List).cast<String>();
  }
}
