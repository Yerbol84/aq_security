// pkgs/aq_security/lib/src/client/http_audit_service.dart
//
// HTTP-клиент для IAuditService.
// Вызывает /rbac/logs endpoints auth сервера.

import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:aq_schema/security/security.dart';

/// HTTP-реализация IAuditService.
final class HttpAuditService implements IAuditService {
  HttpAuditService({
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

  // ── Write (fire-and-forget) ───────────────────────────────────────────────

  @override
  Future<void> logAccess({
    required String userId,
    required String userEmail,
    required String tenantId,
    required String resource,
    required String action,
    required bool allowed,
    String? reason,
    String? ipAddress,
    String? userAgent,
    Map<String, dynamic>? metadata,
  }) async {
    // fire-and-forget: не блокируем вызывающий код
    unawaited(Future(() async {
      try {
        await http.post(
          Uri.parse('$_base/rbac/logs/access'),
          headers: await _headers(),
          body: jsonEncode({
            'userId': userId,
            'userEmail': userEmail,
            'tenantId': tenantId,
            'resource': resource,
            'action': action,
            'allowed': allowed,
            if (reason != null) 'reason': reason,
            if (ipAddress != null) 'ipAddress': ipAddress,
            if (userAgent != null) 'userAgent': userAgent,
            if (metadata != null) 'metadata': metadata,
          }),
        );
      } catch (_) {}
    }));
  }

  @override
  Future<void> logAudit({
    required AuditActionType action,
    required AuditEntityType entityType,
    required String entityId,
    required String entityName,
    required String userId,
    required String userEmail,
    required String tenantId,
    Map<String, dynamic>? changes,
    String? reason,
    String? ipAddress,
    Map<String, dynamic>? metadata,
  }) async {
    // fire-and-forget
    unawaited(Future(() async {
      try {
        await http.post(
          Uri.parse('$_base/rbac/logs/audit'),
          headers: await _headers(),
          body: jsonEncode({
            'action': action.name,
            'entityType': entityType.name,
            'entityId': entityId,
            'entityName': entityName,
            'userId': userId,
            'userEmail': userEmail,
            'tenantId': tenantId,
            if (changes != null) 'changes': changes,
            if (reason != null) 'reason': reason,
            if (ipAddress != null) 'ipAddress': ipAddress,
            if (metadata != null) 'metadata': metadata,
          }),
        );
      } catch (_) {}
    }));
  }

  // ── Read ──────────────────────────────────────────────────────────────────

  @override
  Future<List<AqAccessLog>> getAccessLogs(AccessLogFilter filter) async {
    final res = await http.post(
      Uri.parse('$_base/rbac/logs/access/query'),
      headers: await _headers(),
      body: jsonEncode(filter.toJson()),
    );
    final body = _decode(res);
    return (body['logs'] as List)
        .map((e) => AqAccessLog.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<List<AqAuditTrail>> getAuditTrail(AuditTrailFilter filter) async {
    final res = await http.post(
      Uri.parse('$_base/rbac/logs/audit/query'),
      headers: await _headers(),
      body: jsonEncode(filter.toJson()),
    );
    final body = _decode(res);
    return (body['trail'] as List)
        .map((e) => AqAuditTrail.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  // ── Stats ─────────────────────────────────────────────────────────────────

  @override
  Future<Map<String, dynamic>> getAccessLogStats({
    String? tenantId,
    required int startTime,
    required int endTime,
  }) async {
    final res = await http.get(
      Uri.parse('$_base/rbac/logs/access/stats').replace(queryParameters: {
        'startTime': startTime.toString(),
        'endTime': endTime.toString(),
        if (tenantId != null) 'tenantId': tenantId,
      }),
      headers: await _headers(),
    );
    return _decode(res);
  }

  @override
  Future<Map<String, dynamic>> getAuditTrailStats({
    String? tenantId,
    required int startTime,
    required int endTime,
  }) async {
    final res = await http.get(
      Uri.parse('$_base/rbac/logs/audit/stats').replace(queryParameters: {
        'startTime': startTime.toString(),
        'endTime': endTime.toString(),
        if (tenantId != null) 'tenantId': tenantId,
      }),
      headers: await _headers(),
    );
    return _decode(res);
  }

  // ── Cleanup ───────────────────────────────────────────────────────────────

  @override
  Future<int> cleanupAccessLogs({required int olderThan}) async {
    final res = await http.delete(
      Uri.parse('$_base/rbac/logs/access').replace(
        queryParameters: {'olderThan': olderThan.toString()},
      ),
      headers: await _headers(),
    );
    final body = _decode(res);
    return body['deleted'] as int;
  }

  @override
  Future<int> cleanupAuditTrail({required int olderThan}) async {
    final res = await http.delete(
      Uri.parse('$_base/rbac/logs/audit').replace(
        queryParameters: {'olderThan': olderThan.toString()},
      ),
      headers: await _headers(),
    );
    final body = _decode(res);
    return body['deleted'] as int;
  }
}
