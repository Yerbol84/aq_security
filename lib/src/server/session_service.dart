// pkgs/aq_security/lib/src/server/session_service.dart
//
// Server-only. Full session lifecycle: create, track, revoke, purge.
// All active sessions are tracked in the repository.
// Session ID is always embedded in the JWT (sid claim) for cross-check.

import 'dart:async';
import 'package:uuid/uuid.dart';
import 'package:aq_schema/security/security.dart';

import '../shared/security_config.dart';

final class SessionService {
  SessionService({
    required this.repo,
    required this.config,
  });

  final ISessionRepository repo;
  final SecurityConfig config;

  static final _uuid = Uuid();
  Timer? _purgeTimer;

  // ── Session creation ───────────────────────────────────────────────────────

  Future<AqSession> create({
    required String userId,
    required String tenantId,
    required IdentityProvider provider,
    String? ipAddress,
    String? userAgent,
  }) async {
    final now = _now();
    final session = AqSession(
      id: _uuid.v4(),
      userId: userId,
      tenantId: tenantId,
      status: SessionStatus.active,
      authProvider: provider,
      ipAddress: ipAddress,
      userAgent: userAgent,
      deviceHint: _extractDeviceHint(userAgent),
      createdAt: now,
      expiresAt: now + config.sessionTtlSeconds,
      lastSeenAt: now,
    );

    return repo.create(session);
  }

  // ── Session validation ─────────────────────────────────────────────────────

  /// Check session exists and is active.
  /// Called during token validation (after signature check).
  Future<AqSession?> validate(String sessionId) async {
    final session = await repo.findById(sessionId);
    if (session == null) return null;
    if (!session.isActive) return null;
    return session;
  }

  /// Update lastSeenAt — called on every authenticated request.
  Future<void> touch(String sessionId) async {
    await repo.touch(sessionId, _now());
  }

  // ── Session revocation ─────────────────────────────────────────────────────

  Future<void> revoke(String sessionId, {String reason = 'user_logout'}) async {
    await repo.revoke(sessionId, reason);
  }

  Future<void> revokeAll(String userId, {String reason = 'revoke_all'}) async {
    await repo.revokeAllForUser(userId);
  }

  // ── Session listing ────────────────────────────────────────────────────────

  Future<List<AqSession>> listActive(String userId) =>
      repo.listActiveByUser(userId);

  // ── Housekeeping ───────────────────────────────────────────────────────────

  /// Start periodic purge of expired sessions.
  void startPurgeTimer({Duration interval = const Duration(hours: 1)}) {
    _purgeTimer?.cancel();
    _purgeTimer = Timer.periodic(interval, (_) async {
      try {
        final count = await repo.purgeExpired();
        if (count > 0) {
          // ignore: avoid_print
          print('[SessionService] Purged $count expired sessions');
        }
      } catch (e) {
        // ignore: avoid_print
        print('[SessionService] Purge error: $e');
      }
    });
  }

  void dispose() {
    _purgeTimer?.cancel();
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  static String? _extractDeviceHint(String? ua) {
    if (ua == null) return null;
    if (ua.contains('Chrome')) return 'Chrome';
    if (ua.contains('Firefox')) return 'Firefox';
    if (ua.contains('Safari')) return 'Safari';
    if (ua.contains('Dart')) return 'Dart CLI';
    return 'Unknown';
  }

  static int _now() => DateTime.now().millisecondsSinceEpoch ~/ 1000;
}
