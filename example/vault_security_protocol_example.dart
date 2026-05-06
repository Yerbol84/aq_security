// pkgs/aq_security/example/vault_security_protocol_example.dart
//
// SCN-003: Демонстрация IVaultSecurityProtocol в embedded режиме.
//
// Показывает как data layer использует security protocol:
// - extractClaims из HTTP headers
// - canRead / canWrite / canDelete
// - validateData
// - logOperation (аудит)
// - resourcePermissions (RLAC)
//
// Использует InMemoryVaultSecurityProtocol — без HTTP, без dart_vault.

import 'package:aq_schema/security/security.dart';
import 'package:aq_schema/security/token/token_codec.dart';
import 'package:aq_security/aq_security_server.dart';

void main() async {
  print('=== SCN-003: IVaultSecurityProtocol (embedded mode) ===\n');

  // ── 1. Инициализация ──────────────────────────────────────────────────────

  // Создать in-memory протокол с дефолтными ролями (admin/editor/viewer)
  final protocol = InMemoryVaultSecurityProtocol.withDefaults();
  IVaultSecurityProtocol.initialize(protocol);

  // Создать тестовые токены
  const secret = 'test-secret-32-chars-long-string!';
  final codec = TokenCodec(secret: secret);

  final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;

  // Токен для editor
  final editorToken = codec.encode(AqTokenClaims(
    sub: 'user-editor',
    tid: 'tenant-1',
    email: 'editor@example.com',
    type: TokenType.access,
    roles: ['editor'],
    scopes: ['projects:read', 'projects:write'],
    iat: now,
    exp: now + 900,
    jti: 'jti-editor',
    sid: 'session-editor',
  ));

  // Токен для viewer
  final viewerToken = codec.encode(AqTokenClaims(
    sub: 'user-viewer',
    tid: 'tenant-1',
    email: 'viewer@example.com',
    type: TokenType.access,
    roles: ['viewer'],
    scopes: ['projects:read'],
    iat: now,
    exp: now + 900,
    jti: 'jti-viewer',
    sid: 'session-viewer',
  ));

  // Назначить роли
  protocol.assignRole('user-editor', 'role-editor');
  protocol.assignRole('user-viewer', 'role-viewer');

  print('✓ Protocol initialized with roles: admin, editor, viewer');
  print('✓ Tokens created for: user-editor, user-viewer\n');

  // ── 2. extractClaims ──────────────────────────────────────────────────────

  final editorClaims = await protocol.extractClaims({
    'Authorization': 'Bearer $editorToken',
  });
  print('extractClaims(editor): ${editorClaims?.sub} ✓');

  final anonClaims = await protocol.extractClaims({});
  print('extractClaims(no token): ${anonClaims == null ? 'null (anonymous)' : 'ERROR'} ✓\n');

  // ── 3. canRead ────────────────────────────────────────────────────────────

  final readDecision = await protocol.canRead(
    claims: editorClaims,
    collection: 'projects',
    entityId: 'proj-1',
  );
  print('canRead(editor, projects): ${readDecision.allowed ? '✓ ALLOW' : '✗ DENY'} — ${readDecision.reason}');

  final viewerClaims = await protocol.extractClaims({
    'Authorization': 'Bearer $viewerToken',
  });
  final viewerReadDecision = await protocol.canRead(
    claims: viewerClaims,
    collection: 'projects',
  );
  print('canRead(viewer, projects): ${viewerReadDecision.allowed ? '✓ ALLOW' : '✗ DENY'}\n');

  // ── 4. canWrite ───────────────────────────────────────────────────────────

  final writeDecision = await protocol.canWrite(
    claims: editorClaims,
    collection: 'projects',
    data: {'name': 'My Project'},
  );
  print('canWrite(editor, projects): ${writeDecision.allowed ? '✓ ALLOW' : '✗ DENY'}');

  final viewerWriteDecision = await protocol.canWrite(
    claims: viewerClaims,
    collection: 'projects',
    data: {'name': 'My Project'},
  );
  print('canWrite(viewer, projects): ${viewerWriteDecision.allowed ? '✓ ALLOW' : '✗ DENY — ${viewerWriteDecision.reason}'}\n');

  // ── 5. canDelete ──────────────────────────────────────────────────────────

  final deleteDecision = await protocol.canDelete(
    claims: editorClaims,
    collection: 'projects',
    entityId: 'proj-1',
  );
  print('canDelete(editor, projects): ${deleteDecision.allowed ? '✓ ALLOW' : '✗ DENY — ${deleteDecision.reason}'}');

  // ── 6. Anonymous access ───────────────────────────────────────────────────

  final anonDecision = await protocol.canRead(
    claims: null,
    collection: 'projects',
  );
  print('canRead(anonymous): ${anonDecision.allowed ? '✓ ALLOW' : '✗ DENY — ${anonDecision.reason}'}\n');

  // ── 7. Unknown collection → graceful deny ─────────────────────────────────

  final unknownDecision = await protocol.canRead(
    claims: editorClaims,
    collection: 'unknown_collection',
  );
  print('canRead(editor, unknown_collection): ${unknownDecision.allowed ? '✓ ALLOW' : '✗ DENY — ${unknownDecision.reason}'}\n');

  // ── 8. validateData ───────────────────────────────────────────────────────

  final validationErrors = await protocol.validateData(
    collection: 'projects',
    data: {'name': 'My Project', 'description': 'Safe content'},
  );
  print('validateData(safe data): ${validationErrors.isEmpty ? '✓ OK' : '✗ ${validationErrors.length} errors'}\n');

  // ── 9. logOperation (аудит) ───────────────────────────────────────────────

  await protocol.logOperation(
    claims: editorClaims,
    operation: 'read',
    collection: 'projects',
    entityId: 'proj-1',
    success: true,
  );
  await protocol.logOperation(
    claims: viewerClaims,
    operation: 'write',
    collection: 'projects',
    success: false,
    errorMessage: 'Permission denied',
  );

  print('Audit log (${protocol.auditLog.length} entries):');
  for (final entry in protocol.auditLog) {
    print('  $entry');
  }

  // ── 10. resourcePermissions (RLAC) ────────────────────────────────────────

  print('\nResourcePermissions (RLAC):');
  await protocol.resourcePermissions.grant(
    resourceId: 'proj-secret',
    userId: 'user-viewer',
    level: AccessLevel.read,
    grantedBy: 'user-editor',
  );

  final hasAccess = await protocol.resourcePermissions.hasAccess(
    resourceId: 'proj-secret',
    userId: 'user-viewer',
    minimumLevel: AccessLevel.read,
  );
  print('  viewer has read access to proj-secret: ${hasAccess ? '✓' : '✗'}');

  final noAccess = await protocol.resourcePermissions.hasAccess(
    resourceId: 'proj-secret',
    userId: 'user-viewer',
    minimumLevel: AccessLevel.write,
  );
  print('  viewer has write access to proj-secret: ${noAccess ? '✓' : '✗ (expected)'}');

  print('\n✓ Example completed successfully');
}
