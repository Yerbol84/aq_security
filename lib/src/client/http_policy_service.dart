// pkgs/aq_security/lib/src/client/http_policy_service.dart
//
// HTTP-клиент для IPolicyService.
// Вызывает /rbac/policies/* endpoints auth сервера.

import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:aq_schema/security/security.dart';

/// HTTP-реализация IPolicyService.
final class HttpPolicyService implements IPolicyService {
  HttpPolicyService({
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
  Future<List<AqPolicy>> getPolicies({bool includeInactive = false}) async {
    final uri = Uri.parse('$_base/rbac/policies').replace(
      queryParameters: includeInactive ? {'includeInactive': 'true'} : null,
    );
    final res = await http.get(uri, headers: await _headers());
    final body = _decode(res);
    return (body['policies'] as List)
        .map((e) => AqPolicy.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<AqPolicy?> getPolicy(String policyId) async {
    final res = await http.get(
      Uri.parse('$_base/rbac/policies/$policyId'),
      headers: await _headers(),
    );
    if (res.statusCode == 404) return null;
    final body = _decode(res);
    return AqPolicy.fromJson(body['policy'] as Map<String, dynamic>);
  }

  @override
  Future<AqPolicy> createPolicy({
    required String name,
    String? description,
    required List<PolicyStatement> statements,
    bool isActive = true,
    int priority = 0,
  }) async {
    final res = await http.post(
      Uri.parse('$_base/rbac/policies'),
      headers: await _headers(),
      body: jsonEncode({
        'name': name,
        if (description != null) 'description': description,
        'statements': statements.map((s) => s.toJson()).toList(),
        'isActive': isActive,
        'priority': priority,
      }),
    );
    final body = _decode(res);
    return AqPolicy.fromJson(body['policy'] as Map<String, dynamic>);
  }

  @override
  Future<AqPolicy> updatePolicy({
    required String policyId,
    String? name,
    String? description,
    List<PolicyStatement>? statements,
    bool? isActive,
    int? priority,
  }) async {
    final res = await http.put(
      Uri.parse('$_base/rbac/policies/$policyId'),
      headers: await _headers(),
      body: jsonEncode({
        if (name != null) 'name': name,
        if (description != null) 'description': description,
        if (statements != null) 'statements': statements.map((s) => s.toJson()).toList(),
        if (isActive != null) 'isActive': isActive,
        if (priority != null) 'priority': priority,
      }),
    );
    final body = _decode(res);
    return AqPolicy.fromJson(body['policy'] as Map<String, dynamic>);
  }

  @override
  Future<void> deletePolicy(String policyId) async {
    final res = await http.delete(
      Uri.parse('$_base/rbac/policies/$policyId'),
      headers: await _headers(),
    );
    _decode(res);
  }

  // ── Evaluation ────────────────────────────────────────────────────────────

  @override
  Future<PolicyEvaluationResult> evaluatePolicy(PolicyContext context) async {
    final res = await http.post(
      Uri.parse('$_base/rbac/policies/evaluate'),
      headers: await _headers(),
      body: jsonEncode({'context': context.toJson()}),
    );
    final body = _decode(res);
    return _parseResult(body['result'] as Map<String, dynamic>);
  }

  @override
  Future<PolicyEvaluationResult> testPolicy({
    required String userId,
    required String resource,
    required String action,
    Map<String, dynamic>? additionalContext,
  }) async {
    final res = await http.post(
      Uri.parse('$_base/rbac/policies/test'),
      headers: await _headers(),
      body: jsonEncode({
        'userId': userId,
        'resource': resource,
        'action': action,
        if (additionalContext != null) 'additionalContext': additionalContext,
      }),
    );
    final body = _decode(res);
    return _parseResult(body['result'] as Map<String, dynamic>);
  }

  PolicyEvaluationResult _parseResult(Map<String, dynamic> json) {
    final allowed = json['allowed'] as bool;
    final matchedPolicies = (json['matchedPolicies'] as List?)?.cast<String>() ?? [];
    final reason = json['reason'] as String?;
    return allowed
        ? PolicyEvaluationResult.allow(matchedPolicies: matchedPolicies)
        : PolicyEvaluationResult.deny(reason: reason, matchedPolicies: matchedPolicies);
  }
}
