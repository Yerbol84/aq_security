// pkgs/aq_security/lib/src/client/aq_security_service.dart
//
// The service handed to the application after init.
// Pure Dart — works in Flutter, Dart CLI, workers.
//
// Usage:
//   final service = await AQSecurityClient.init('https://auth.example.com');
//   final response = await service.loginWithGoogle(code: code, redirectUri: uri);
//   service.currentUser; // AqUser?
//   service.isAuthenticated; // bool
//   service.stream; // Stream<SecurityState>

import 'dart:async';
import 'package:aq_schema/security/security.dart';
import 'http_auth_transport.dart';
import 'local_session_store.dart';

// ── Service ───────────────────────────────────────────────────────────────────

/// Main security service. Obtained via [AQSecurityClient.init].
/// Manages auth lifecycle, token refresh, session state.
/// Implements [ISecurityService] interface from aq_schema.
final class AQSecurityService implements ISecurityService {
  AQSecurityService._({
    required HttpAuthTransport transport,
    required LocalSessionStore store,
    required TokenValidator validator,
  })  : _transport = transport,
        _store = store,
        _validator = validator;

  final HttpAuthTransport _transport;
  final LocalSessionStore _store;
  final TokenValidator _validator;

  final _controller = StreamController<SecurityState>.broadcast();
  SecurityState _state = const SecurityStateUnauthenticated();

  /// Observable security state stream.
  Stream<SecurityState> get stream => _controller.stream;

  /// Current state snapshot.
  SecurityState get state => _state;

  AqUser? get currentUser => _state is SecurityStateAuthenticated
      ? (_state as SecurityStateAuthenticated).user
      : null;

  AqTenant? get currentTenant => _state is SecurityStateAuthenticated
      ? (_state as SecurityStateAuthenticated).tenant
      : null;

  AqTokenClaims? get currentClaims => _state is SecurityStateAuthenticated
      ? (_state as SecurityStateAuthenticated).claims
      : null;

  bool get isAuthenticated => _state is SecurityStateAuthenticated;

  /// Current access token (may trigger silent refresh).
  Future<String?> get accessToken async {
    final stored = _store.getStoredTokens();
    if (stored == null) return null;

    // Check expiry with 60s buffer
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    if (stored.accessExpiresAt - now < 60) {
      // Silent refresh
      try {
        await _refresh(stored.refreshToken);
        return _store.getStoredTokens()?.accessToken;
      } catch (_) {
        return null;
      }
    }
    return stored.accessToken;
  }

  // ── Auth actions ───────────────────────────────────────────────────────────

  /// Login via Google OAuth2 authorization code.
  @override
  Future<AuthResponse> loginWithGoogle({
    required String code,
    required String redirectUri,
  }) async {
    _emit(const SecurityStateLoading());
    try {
      final credentials = GoogleOAuthCredentials(
        code: code,
        redirectUri: redirectUri,
      );
      final response = await _transport.login(
        AuthRequest(credentials: credentials),
      );
      await _handleAuthResponse(response);
      return response;
    } catch (e) {
      _emit(SecurityStateError(e.toString()));
      rethrow;
    }
  }

  /// Login via API key (service accounts, workers).
  @override
  Future<AuthResponse> loginWithApiKey(String apiKey) async {
    _emit(const SecurityStateLoading());
    try {
      final credentials = ApiKeyCredentials(apiKey: apiKey);
      final response = await _transport.login(
        AuthRequest(credentials: credentials),
      );
      await _handleAuthResponse(response);
      return response;
    } catch (e) {
      _emit(SecurityStateError(e.toString()));
      rethrow;
    }
  }

  /// Login via email/password.
  @override
  Future<AuthResponse> loginWithEmail({
    required String email,
    required String password,
  }) async {
    _emit(const SecurityStateLoading());
    try {
      final credentials = EmailPasswordCredentials(
        email: email,
        password: password,
      );
      final response = await _transport.login(
        AuthRequest(credentials: credentials),
      );
      await _handleAuthResponse(response);
      return response;
    } catch (e) {
      _emit(SecurityStateError(e.toString()));
      rethrow;
    }
  }

  /// Restore session from stored tokens (call on app start).
  @override
  Future<void> restoreSession() async {
    final stored = _store.getStoredTokens();
    if (stored == null) return;

    // Validate locally first
    final result = _validator.validateAccess(stored.accessToken);
    if (result.valid) {
      // Fetch fresh user info from server
      try {
        final me = await _transport.getMe(stored.accessToken);
        await _handleAuthResponse(me);
      } catch (_) {
        // Try refresh
        await _silentRefresh(stored.refreshToken);
      }
    } else {
      await _silentRefresh(stored.refreshToken);
    }
  }

  /// Refresh token pair using stored refresh token.
  Future<void> _silentRefresh(String refreshToken) async {
    try {
      await _refresh(refreshToken);
    } catch (_) {
      _store.clear();
      _emit(const SecurityStateUnauthenticated());
    }
  }

  Future<void> _refresh(String refreshToken) async {
    final tokens = await _transport.refresh(refreshToken);
    _store.saveTokens(tokens);
    // Re-fetch me with new access token
    final me = await _transport.getMe(tokens.accessToken);
    await _handleAuthResponse(me);
  }

  /// Logout and revoke session.
  @override
  Future<void> logout() async {
    final token = _store.getStoredTokens()?.accessToken;
    if (token != null) {
      try {
        await _transport.logout(token);
      } catch (_) {}
    }
    _store.clear();
    _emit(const SecurityStateUnauthenticated());
  }

  /// List active sessions for current user.
  Future<List<AqSession>> listSessions() async {
    final token = await accessToken;
    if (token == null) throw Exception('Not authenticated');
    return _transport.listSessions(token);
  }

  /// Revoke a specific session.
  Future<void> revokeSession(String sessionId) async {
    final token = await accessToken;
    if (token == null) throw Exception('Not authenticated');
    await _transport.revokeSession(sessionId, token);
  }

  /// Validate a token (calls server — includes revocation check).
  Future<ValidateTokenResponse> _validateTokenInternal(
    String token, {
    List<String> requiredPerms = const [],
  }) {
    return _transport.validate(
      ValidateTokenRequest(token: token, requiredPerms: requiredPerms),
    );
  }

  // ── ISecurityService implementation ───────────────────────────────────────

  // Подсервисы (TODO: реализовать)
  @override
  IRoleManagementService get roleManagement => throw UnimplementedError(
      'Role management not yet implemented. Use direct API calls.');

  @override
  IPolicyService get policies => throw UnimplementedError(
      'Policy service not yet implemented. Use direct API calls.');

  @override
  IAuditService get audit => throw UnimplementedError(
      'Audit service not yet implemented. Use direct API calls.');

  // Регистрация
  @override
  Future<AuthResponse> register({
    required String email,
    required String password,
    String? displayName,
  }) async {
    // TODO: Implement register in HttpAuthTransport
    throw UnimplementedError('register() not yet implemented in transport layer');
  }

  // Обновление токенов
  @override
  Future<TokenPair> refreshTokens() async {
    final stored = _store.getStoredTokens();
    if (stored == null) {
      throw Exception('No refresh token available');
    }
    final tokens = await _transport.refresh(stored.refreshToken);
    _store.saveTokens(tokens);
    return tokens;
  }

  // Управление сессиями
  @override
  Future<List<AqSession>> getActiveSessions() => listSessions();

  @override
  Future<void> revokeAllOtherSessions() async {
    final sessions = await getActiveSessions();
    final currentSessionId = _state is SecurityStateAuthenticated
        ? (_state as SecurityStateAuthenticated).session.id
        : null;
    for (final session in sessions) {
      if (session.id != currentSessionId) {
        await revokeSession(session.id);
      }
    }
  }

  // Проверка прав
  @override
  Future<bool> hasPermission(String permission) async {
    final claims = currentClaims;
    if (claims == null) return false;
    // TODO: AqTokenClaims needs permissions field
    // For now, check scopes as fallback
    return claims.scopes.contains(permission) || claims.scopes.contains('*');
  }

  @override
  Future<bool> hasRole(String role) async {
    final claims = currentClaims;
    if (claims == null) return false;
    return claims.roles.contains(role);
  }

  @override
  Future<bool> hasPermissions(
    List<String> permissions, {
    bool requireAll = true,
  }) async {
    if (requireAll) {
      for (final perm in permissions) {
        if (!await hasPermission(perm)) return false;
      }
      return true;
    } else {
      for (final perm in permissions) {
        if (await hasPermission(perm)) return true;
      }
      return false;
    }
  }

  @override
  Future<bool> hasRoles(
    List<String> roles, {
    bool requireAll = true,
  }) async {
    if (requireAll) {
      for (final role in roles) {
        if (!await hasRole(role)) return false;
      }
      return true;
    } else {
      for (final role in roles) {
        if (await hasRole(role)) return true;
      }
      return false;
    }
  }

  @override
  Future<List<String>> getResourcePermissions(
    String resourceId, {
    List<String>? actions,
  }) async {
    // TODO: Implement full RBAC + PBAC check
    // For now, return permissions from claims
    final claims = currentClaims;
    if (claims == null) return [];

    final resourceType = resourceId.split('/').first;
    final checkActions = actions ?? ['read', 'write', 'delete', 'admin'];
    final allowed = <String>[];

    for (final action in checkActions) {
      final permission = '$resourceType:$action';
      if (await hasPermission(permission)) {
        allowed.add(permission);
      }
    }

    return allowed;
  }

  // API Keys
  @override
  Future<List<AqApiKey>> getApiKeys() async {
    // TODO: Implement listApiKeys in HttpAuthTransport
    throw UnimplementedError('getApiKeys() not yet implemented in transport layer');
  }

  @override
  Future<AqApiKey> createApiKey({
    required String name,
    required List<String> permissions,
    bool isTest = false,
  }) async {
    // TODO: Implement createApiKey in HttpAuthTransport
    throw UnimplementedError('createApiKey() not yet implemented in transport layer');
  }

  @override
  Future<AqApiKey> rotateApiKey(String keyId) async {
    // TODO: Implement rotateApiKey in HttpAuthTransport
    throw UnimplementedError('rotateApiKey() not yet implemented in transport layer');
  }

  @override
  Future<void> revokeApiKey(String keyId) async {
    final token = await accessToken;
    if (token == null) throw Exception('Not authenticated');
    await _transport.revokeApiKey(keyId, token);
  }

  // Profile management
  @override
  Future<AqUser> updateProfile({
    String? displayName,
    String? avatarUrl,
  }) async {
    // TODO: Implement updateProfile in HttpAuthTransport
    throw UnimplementedError('updateProfile() not yet implemented in transport layer');
  }

  @override
  Future<void> changePassword({
    required String oldPassword,
    required String newPassword,
  }) async {
    // TODO: Implement changePassword in HttpAuthTransport
    throw UnimplementedError('changePassword() not yet implemented in transport layer');
  }

  @override
  Future<void> requestPasswordReset(String email) async {
    // TODO: Implement requestPasswordReset in HttpAuthTransport
    throw UnimplementedError('requestPasswordReset() not yet implemented in transport layer');
  }

  @override
  Future<void> resetPassword({
    required String email,
    required String code,
    required String newPassword,
  }) async {
    // TODO: Implement resetPassword in HttpAuthTransport
    throw UnimplementedError('resetPassword() not yet implemented in transport layer');
  }

  // Email verification
  @override
  Future<void> sendVerificationCode() async {
    // TODO: Implement sendVerificationCode in HttpAuthTransport
    throw UnimplementedError('sendVerificationCode() not yet implemented in transport layer');
  }

  @override
  Future<void> verifyEmail(String code) async {
    // TODO: Implement verifyEmail in HttpAuthTransport
    throw UnimplementedError('verifyEmail() not yet implemented in transport layer');
  }

  // Tenant management
  @override
  Future<List<AqTenant>> getAvailableTenants() async {
    // TODO: Implement listTenants in HttpAuthTransport
    throw UnimplementedError('getAvailableTenants() not yet implemented in transport layer');
  }

  @override
  Future<void> switchTenant(String tenantId) async {
    // TODO: Implement switchTenant in HttpAuthTransport
    throw UnimplementedError('switchTenant() not yet implemented in transport layer');
  }

  // Validate token (interface method)
  @override
  Future<bool> validateToken(String token) async {
    try {
      final result = await _validateTokenInternal(token);
      return result.valid;
    } catch (_) {
      return false;
    }
  }

  // ── Internal ───────────────────────────────────────────────────────────────

  Future<void> _handleAuthResponse(AuthResponse response) async {
    _store.saveTokens(response.tokens);

    final claims = _validator.validateAccess(response.tokens.accessToken);
    if (!claims.valid) {
      throw Exception('Server returned invalid token');
    }

    _emit(SecurityStateAuthenticated(
      user: response.user,
      tenant: response.tenant,
      session: response.session,
      claims: claims.claims!,
    ));
  }

  void _emit(SecurityState state) {
    _state = state;
    _controller.add(state);
  }

  @override
  Future<void> dispose() async {
    _controller.close();
  }

  // ── Factory ────────────────────────────────────────────────────────────────

  static AQSecurityService create({
    required String endpoint,
    required TokenValidator validator,
  }) {
    final transport = HttpAuthTransport(baseUrl: endpoint);
    final store = LocalSessionStore();
    return AQSecurityService._(
      transport: transport,
      store: store,
      validator: validator,
    );
  }
}
