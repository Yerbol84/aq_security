// pkgs/aq_security/lib/src/server/rbac_router.dart
//
// REST API для RBAC системы.

import 'dart:convert';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:aq_schema/aq_schema.dart';
import '../rbac/rbac_service.dart';

/// Router для RBAC API.
class RBACRouter {
  RBACRouter(this.rbacService);

  final RBACService rbacService;

  Router get router {
    final router = Router();

    // ═══════════════════════════════════════════════════════════════════════
    // Role Management
    // ═══════════════════════════════════════════════════════════════════════

    router.post('/roles', _createRole);
    router.get('/roles', _listRoles);
    router.get('/roles/<roleId>', _getRole);
    router.put('/roles/<roleId>', _updateRole);
    router.delete('/roles/<roleId>', _deleteRole);

    // Иерархия
    router.post('/roles/<roleId>/inherit/<parentId>', _addInheritance);
    router.delete('/roles/<roleId>/inherit/<parentId>', _removeInheritance);
    router.get('/roles/<roleId>/hierarchy', _getRoleHierarchy);
    router.get('/roles/<roleId>/effective-permissions', _getRoleEffectivePermissions);

    // ═══════════════════════════════════════════════════════════════════════
    // User Role Assignment
    // ═══════════════════════════════════════════════════════════════════════

    router.post('/users/<userId>/roles', _assignRole);
    router.delete('/users/<userId>/roles/<roleId>', _revokeRole);
    router.get('/users/<userId>/roles', _getUserRoles);
    router.post('/users/<userId>/temporary-roles', _assignTemporaryRole);
    router.get('/users/<userId>/permissions', _getUserPermissions);

    // ═══════════════════════════════════════════════════════════════════════
    // Access Control
    // ═══════════════════════════════════════════════════════════════════════

    router.post('/check', _checkAccess);
    router.post('/check/batch', _checkAccessBatch);

    // ═══════════════════════════════════════════════════════════════════════
    // Policy Management
    // ═══════════════════════════════════════════════════════════════════════

    router.post('/policies', _createPolicy);
    router.get('/policies', _listPolicies);
    router.get('/policies/<policyId>', _getPolicy);
    router.put('/policies/<policyId>', _updatePolicy);
    router.delete('/policies/<policyId>', _deletePolicy);

    // ═══════════════════════════════════════════════════════════════════════
    // Monitoring & Analytics
    // ═══════════════════════════════════════════════════════════════════════

    router.get('/logs', _getLogs);
    router.get('/logs/user/<userId>', _getUserLogs);
    router.get('/logs/resource/<resource>', _getResourceLogs);
    router.get('/metrics', _getMetrics);
    router.get('/alerts', _getAlerts);
    router.post('/alerts/<alertId>/acknowledge', _acknowledgeAlert);

    return router;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Role Management Handlers
  // ═══════════════════════════════════════════════════════════════════════════

  Future<Response> _createRole(Request req) async {
    try {
      final body = await req.readAsString();
      final data = jsonDecode(body) as Map<String, dynamic>;

      final role = await rbacService.createRole(
        name: data['name'] as String,
        description: data['description'] as String?,
        permissions: (data['permissions'] as List<dynamic>).cast<String>(),
        inheritsFrom: (data['inheritsFrom'] as List<dynamic>?)?.cast<String>() ?? [],
        tenantId: data['tenantId'] as String,
        metadata: (data['metadata'] as Map<String, dynamic>?) ?? {},
      );

      return _ok({'role': role.toJson()});
    } catch (e) {
      return _error(e.toString());
    }
  }

  Future<Response> _listRoles(Request req) async {
    try {
      final roles = await rbacService.getAllRoles();
      return _ok({'roles': roles?.map((r) => r.toJson()).toList() ?? []});
    } catch (e) {
      return _error(e.toString());
    }
  }

  Future<Response> _getRole(Request req, String roleId) async {
    try {
      final role = await rbacService.getRole(roleId);
      if (role == null) {
        return _notFound('Role not found');
      }
      return _ok({'role': role.toJson()});
    } catch (e) {
      return _error(e.toString());
    }
  }

  Future<Response> _updateRole(Request req, String roleId) async {
    try {
      final body = await req.readAsString();
      final data = jsonDecode(body) as Map<String, dynamic>;

      final role = await rbacService.updateRole(
        roleId,
        name: data['name'] as String?,
        description: data['description'] as String?,
        permissions: (data['permissions'] as List<dynamic>?)?.cast<String>(),
        inheritsFrom: (data['inheritsFrom'] as List<dynamic>?)?.cast<String>(),
        metadata: data['metadata'] as Map<String, dynamic>?,
      );

      return _ok({'role': role.toJson()});
    } catch (e) {
      return _error(e.toString());
    }
  }

  Future<Response> _deleteRole(Request req, String roleId) async {
    try {
      await rbacService.deleteRole(roleId);
      return _ok({'message': 'Role deleted'});
    } catch (e) {
      return _error(e.toString());
    }
  }

  Future<Response> _addInheritance(Request req, String roleId, String parentId) async {
    try {
      await rbacService.addRoleInheritance(roleId, parentId);
      return _ok({'message': 'Inheritance added'});
    } catch (e) {
      return _error(e.toString());
    }
  }

  Future<Response> _removeInheritance(Request req, String roleId, String parentId) async {
    try {
      await rbacService.removeRoleInheritance(roleId, parentId);
      return _ok({'message': 'Inheritance removed'});
    } catch (e) {
      return _error(e.toString());
    }
  }

  Future<Response> _getRoleHierarchy(Request req, String roleId) async {
    try {
      // TODO: Реализовать получение полной иерархии
      final role = await rbacService.getRole(roleId);
      if (role == null) {
        return _notFound('Role not found');
      }
      return _ok({'role': role.toJson()});
    } catch (e) {
      return _error(e.toString());
    }
  }

  Future<Response> _getRoleEffectivePermissions(Request req, String roleId) async {
    try {
      final permissions = await rbacService.getRoleEffectivePermissions(roleId);
      return _ok({'permissions': permissions});
    } catch (e) {
      return _error(e.toString());
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // User Role Assignment Handlers
  // ═══════════════════════════════════════════════════════════════════════════

  Future<Response> _assignRole(Request req, String userId) async {
    try {
      final body = await req.readAsString();
      final data = jsonDecode(body) as Map<String, dynamic>;

      final userRole = await rbacService.assignRole(
        userId: userId,
        roleId: data['roleId'] as String,
        tenantId: data['tenantId'] as String,
        grantedBy: data['grantedBy'] as String?,
        reason: data['reason'] as String?,
      );

      return _ok({'userRole': userRole.toJson()});
    } catch (e) {
      return _error(e.toString());
    }
  }

  Future<Response> _revokeRole(Request req, String userId, String roleId) async {
    try {
      await rbacService.revokeRole(userId, roleId);
      return _ok({'message': 'Role revoked'});
    } catch (e) {
      return _error(e.toString());
    }
  }

  Future<Response> _getUserRoles(Request req, String userId) async {
    try {
      final roles = await rbacService.getUserRoles(userId);
      return _ok({'roles': roles?.map((r) => r.toJson()).toList() ?? []});
    } catch (e) {
      return _error(e.toString());
    }
  }

  Future<Response> _assignTemporaryRole(Request req, String userId) async {
    try {
      final body = await req.readAsString();
      final data = jsonDecode(body) as Map<String, dynamic>;

      final durationMs = data['durationMs'] as int;
      final duration = Duration(milliseconds: durationMs);

      final userRole = await rbacService.assignTemporaryRole(
        userId: userId,
        roleId: data['roleId'] as String,
        tenantId: data['tenantId'] as String,
        duration: duration,
        grantedBy: data['grantedBy'] as String?,
        reason: data['reason'] as String?,
      );

      return _ok({'userRole': userRole.toJson()});
    } catch (e) {
      return _error(e.toString());
    }
  }

  Future<Response> _getUserPermissions(Request req, String userId) async {
    try {
      final permissions = await rbacService.getUserEffectivePermissions(userId);
      return _ok({'permissions': permissions});
    } catch (e) {
      return _error(e.toString());
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Access Control Handlers
  // ═══════════════════════════════════════════════════════════════════════════

  Future<Response> _checkAccess(Request req) async {
    try {
      final body = await req.readAsString();
      final data = jsonDecode(body) as Map<String, dynamic>;

      final userId = data['userId'] as String;
      final tenantId = data['tenantId'] as String;
      final resource = data['resource'] as String;
      final action = data['action'] as String;
      final scope = data['scope'] as String? ?? 'own';

      // Создать контекст если есть
      AccessContext? context;
      if (data.containsKey('context')) {
        final ctx = data['context'] as Map<String, dynamic>;
        context = AccessContext(
          userId: userId,
          tenantId: tenantId,
          resource: resource,
          action: action,
          userRoles: (ctx['userRoles'] as List<dynamic>?)?.cast<String>() ?? [],
          userPermissions: (ctx['userPermissions'] as List<dynamic>?)?.cast<String>() ?? [],
          userScopes: (ctx['userScopes'] as List<dynamic>?)?.cast<String>() ?? [],
          ipAddress: ctx['ipAddress'] as String?,
          userAgent: ctx['userAgent'] as String?,
          mfaVerified: ctx['mfaVerified'] as bool? ?? false,
          userAttributes: (ctx['userAttributes'] as Map<String, dynamic>?) ?? {},
          resourceAttributes: (ctx['resourceAttributes'] as Map<String, dynamic>?) ?? {},
          sessionId: ctx['sessionId'] as String?,
          requestId: ctx['requestId'] as String?,
        );
      }

      final decision = await rbacService.can(
        userId,
        resource,
        action,
        scope,
        context: context,
      );

      return _ok({
        'allowed': decision.allowed,
        'reason': decision.reason,
        'matchedRoles': decision.matchedRoles,
        'matchedPermissions': decision.matchedPermissions,
        'appliedPolicies': decision.appliedPolicies,
      });
    } catch (e) {
      return _error(e.toString());
    }
  }

  Future<Response> _checkAccessBatch(Request req) async {
    try {
      final body = await req.readAsString();
      final data = jsonDecode(body) as Map<String, dynamic>;

      final userId = data['userId'] as String;
      final permissions = (data['permissions'] as List<dynamic>).cast<String>();

      final results = await rbacService.canBatch(userId, permissions);

      return _ok({'results': results});
    } catch (e) {
      return _error(e.toString());
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Policy Management Handlers
  // ═══════════════════════════════════════════════════════════════════════════

  Future<Response> _createPolicy(Request req) async {
    try {
      final body = await req.readAsString();
      final data = jsonDecode(body) as Map<String, dynamic>;

      final conditions = (data['conditions'] as List<dynamic>)
          .map((c) => PolicyCondition.fromJson(c as Map<String, dynamic>))
          .toList();

      final policy = await rbacService.createPolicy(
        name: data['name'] as String,
        description: data['description'] as String?,
        conditions: conditions,
        effect: PolicyEffect.values.firstWhere((e) => e.name == data['effect']),
        priority: data['priority'] as int,
        tenantId: data['tenantId'] as String,
        createdBy: data['createdBy'] as String,
      );

      return _ok({'policy': policy.toJson()});
    } catch (e) {
      return _error(e.toString());
    }
  }

  Future<Response> _listPolicies(Request req) async {
    try {
      final policies = await rbacService.policyRepository.getAllPolicies();
      return _ok({'policies': policies?.map((p) => p.toJson()).toList() ?? []});
    } catch (e) {
      return _error(e.toString());
    }
  }

  Future<Response> _getPolicy(Request req, String policyId) async {
    try {
      final policy = await rbacService.getPolicy(policyId);
      if (policy == null) {
        return _notFound('Policy not found');
      }
      return _ok({'policy': policy.toJson()});
    } catch (e) {
      return _error(e.toString());
    }
  }

  Future<Response> _updatePolicy(Request req, String policyId) async {
    try {
      final body = await req.readAsString();
      final data = jsonDecode(body) as Map<String, dynamic>;

      List<PolicyCondition>? conditions;
      if (data.containsKey('conditions')) {
        conditions = (data['conditions'] as List<dynamic>)
            .map((c) => PolicyCondition.fromJson(c as Map<String, dynamic>))
            .toList();
      }

      PolicyEffect? effect;
      if (data.containsKey('effect')) {
        effect = PolicyEffect.values.firstWhere((e) => e.name == data['effect']);
      }

      final policy = await rbacService.updatePolicy(
        policyId,
        name: data['name'] as String?,
        description: data['description'] as String?,
        conditions: conditions,
        effect: effect,
        priority: data['priority'] as int?,
        isActive: data['isActive'] as bool?,
      );

      return _ok({'policy': policy.toJson()});
    } catch (e) {
      return _error(e.toString());
    }
  }

  Future<Response> _deletePolicy(Request req, String policyId) async {
    try {
      await rbacService.deletePolicy(policyId);
      return _ok({'message': 'Policy deleted'});
    } catch (e) {
      return _error(e.toString());
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Monitoring & Analytics Handlers
  // ═══════════════════════════════════════════════════════════════════════════

  Future<Response> _getLogs(Request req) async {
    try {
      final limit = int.tryParse(req.url.queryParameters['limit'] ?? '100');
      final offset = int.tryParse(req.url.queryParameters['offset'] ?? '0');

      final logs = await rbacService.accessLogRepository?.getLogs(
        limit: limit,
        offset: offset,
      );

      return _ok({'logs': logs?.map((l) => l.toJson()).toList() ?? []});
    } catch (e) {
      return _error(e.toString());
    }
  }

  Future<Response> _getUserLogs(Request req, String userId) async {
    try {
      final limit = int.tryParse(req.url.queryParameters['limit'] ?? '100');

      final logs = await rbacService.accessLogRepository?.getLogs(
        userId: userId,
        limit: limit,
      );

      return _ok({'logs': logs?.map((l) => l.toJson()).toList() ?? []});
    } catch (e) {
      return _error(e.toString());
    }
  }

  Future<Response> _getResourceLogs(Request req, String resource) async {
    try {
      final limit = int.tryParse(req.url.queryParameters['limit'] ?? '100');

      final logs = await rbacService.accessLogRepository?.getLogs(
        resource: resource,
        limit: limit,
      );

      return _ok({'logs': logs?.map((l) => l.toJson()).toList() ?? []});
    } catch (e) {
      return _error(e.toString());
    }
  }

  Future<Response> _getMetrics(Request req) async {
    try {
      // TODO: Реализовать сбор метрик
      return _ok({'message': 'Metrics endpoint - not implemented yet'});
    } catch (e) {
      return _error(e.toString());
    }
  }

  Future<Response> _getAlerts(Request req) async {
    try {
      // TODO: Реализовать получение оповещений
      return _ok({'alerts': []});
    } catch (e) {
      return _error(e.toString());
    }
  }

  Future<Response> _acknowledgeAlert(Request req, String alertId) async {
    try {
      // TODO: Реализовать подтверждение оповещения
      return _ok({'message': 'Alert acknowledged'});
    } catch (e) {
      return _error(e.toString());
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Helper Methods
  // ═══════════════════════════════════════════════════════════════════════════

  Response _ok(Map<String, dynamic> data) {
    return Response.ok(
      jsonEncode(data),
      headers: {'Content-Type': 'application/json'},
    );
  }

  Response _error(String message, {int status = 400}) {
    return Response(
      status,
      body: jsonEncode({'error': message}),
      headers: {'Content-Type': 'application/json'},
    );
  }

  Response _notFound(String message) {
    return _error(message, status: 404);
  }
}
