// pkgs/aq_security/lib/src/server/auth_router.dart
//
// All auth HTTP endpoints. Mounted at /auth.
//
// POST /auth/login        — Google OAuth2 code exchange, API key
// POST /auth/refresh      — refresh access token
// POST /auth/logout       — revoke session
// GET  /auth/me           — current user
// GET  /auth/sessions     — list active sessions
// DELETE /auth/sessions/:id — revoke session
// POST /auth/validate     — validate token (for other services)
// POST /auth/api-keys     — create API key
// GET  /auth/api-keys     — list user's API keys
// POST /auth/api-keys/:id/rotate — rotate API key
// DELETE /auth/api-keys/:id — revoke API key
// GET  /auth/health       — health check

import 'dart:convert';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:aq_schema/security/security.dart';

import 'google_oauth_service.dart';
import 'github_oauth_service.dart';
import 'user_service.dart';
import 'session_service.dart';
import 'token_issuer.dart';
import 'api_key_service.dart';
import 'middleware/auth_middleware.dart';
import 'oauth/csrf_store.dart';
import 'oauth/pkce_store.dart';
import 'email_verification_service.dart';
import 'magic_link_service.dart';
import 'health_service.dart';

final class AuthRouter {
  AuthRouter({
    required this.googleOAuth,
    required this.userService,
    required this.sessionService,
    required this.tokenIssuer,
    required this.apiKeyService,
    required this.validator,
    this.githubOAuth,
    this.healthService,
    CsrfStore? csrfStore,
    PkceStore? pkceStore,
    EmailVerificationService? emailVerificationService,
    MagicLinkService? magicLinkService,
  })  : _csrfStore = csrfStore ?? CsrfStore(),
        _pkceStore = pkceStore ?? PkceStore(),
        _emailVerificationService =
            emailVerificationService ?? EmailVerificationService(),
        _magicLinkService = magicLinkService ?? MagicLinkService();

  final GoogleOAuthService googleOAuth;
  final GitHubOAuthService? githubOAuth;
  final UserService userService;
  final SessionService sessionService;
  final TokenIssuer tokenIssuer;
  final ApiKeyService apiKeyService;
  final TokenValidator validator;
  final HealthService? healthService;
  final CsrfStore _csrfStore;
  final PkceStore _pkceStore;
  final EmailVerificationService _emailVerificationService;
  final MagicLinkService _magicLinkService;

  Router get router {
    final r = Router();

    r.get('/health', _health);

    // OAuth flow
    r.get('/oauth/google/authorize', _googleAuthorize);
    r.get('/oauth/google/callback', _googleCallback);
    r.get('/oauth/github/authorize', _githubAuthorize);
    r.get('/oauth/github/callback', _githubCallback);

    // Email/Password auth
    r.post('/register', _register);
    r.post('/verify-email', _verifyEmail);
    r.post('/resend-verification', _resendVerification);
    r.post('/forgot-password', _forgotPassword);
    r.post('/reset-password', _resetPassword);

    // Magic Link auth
    r.post('/magic-link/send', _sendMagicLink);
    r.get('/magic-link/verify', _verifyMagicLink);

    // Traditional auth
    r.post('/login', _login);
    r.post('/refresh', _refresh);
    r.post('/logout', _logout);
    r.get('/me', _me);
    r.get('/sessions', _listSessions);
    r.delete('/sessions/<id>', _revokeSession);
    r.post('/validate', _validate);

    // API Keys
    r.post('/api-keys', _createApiKey);
    r.get('/api-keys', _listApiKeys);
    r.post('/api-keys/<id>/rotate', _rotateApiKey);
    r.delete('/api-keys/<id>', _revokeApiKey);

    return r;
  }

  // ── Handlers ──────────────────────────────────────────────────────────────

  Future<Response> _health(Request req) async {
    if (healthService != null) {
      final result = await healthService!.check();
      final statusCode = result.status == 'healthy' ? 200 : 503;
      return Response(statusCode,
          body: jsonEncode(result.toJson()),
          headers: {'content-type': 'application/json'});
    }
    // Fallback to simple health check
    return _ok({'ok': true, 'ts': _now()});
  }

  Future<Response> _login(Request req) async {
    final body = await _readBody(req);
    final authReq = AuthRequest.fromJson(body);

    try {
      // Классифицировать credentials и передать обработчику
      final credentials = authReq.credentials;

      final AuthResponse response;

      switch (credentials) {
        case GoogleOAuthCredentials():
          response = await _handleGoogleOAuth(req, credentials);
        case ApiKeyCredentials():
          response = await _handleApiKey(req, credentials);
        case EmailPasswordCredentials():
          response = await _handleEmailPassword(req, credentials);
        case ServiceTokenCredentials():
          response = await _handleServiceToken(req, credentials);
        default:
          return _badRequest(
            'Unsupported credentials type: ${credentials.type}',
          );
      }

      return _ok(response.toJson());
    } on GoogleOAuthException catch (e) {
      return _badRequest(e.message);
    } catch (e) {
      return _serverError(e.toString());
    }
  }

  // ── OAuth Flow Handlers ───────────────────────────────────────────────────

  /// GET /auth/oauth/google/authorize
  /// Инициирует OAuth flow: генерирует state, сохраняет PKCE challenge, редиректит на Google.
  Future<Response> _googleAuthorize(Request req) async {
    try {
      final params = req.url.queryParameters;

      // Параметры от клиента
      final redirectUri = params['redirect_uri'];
      final codeChallenge = params['code_challenge'];
      final codeChallengeMethod = params['code_challenge_method'] ?? 'S256';
      final appRedirectUrl =
          params['app_redirect_url']; // куда вернуть пользователя после auth

      if (redirectUri == null) {
        return _badRequest('Missing redirect_uri parameter');
      }

      // Генерируем state для CSRF защиты
      final state = _csrfStore.generate(metadata: {
        'redirect_uri': redirectUri,
        'app_redirect_url': appRedirectUrl,
      });

      // Сохраняем PKCE challenge если предоставлен (для мобильных клиентов)
      if (codeChallenge != null) {
        _pkceStore.store(
          state: state,
          codeChallenge: codeChallenge,
          codeChallengeMethod: codeChallengeMethod,
        );
      }

      // Строим Google OAuth URL
      final googleAuthUrl =
          Uri.https('accounts.google.com', '/o/oauth2/v2/auth', {
        'client_id': googleOAuth.config.clientId,
        'redirect_uri': redirectUri,
        'response_type': 'code',
        'scope': 'openid email profile',
        'state': state,
        'access_type': 'offline', // для refresh token
        'prompt': 'consent', // всегда показывать consent screen
      });

      // Редирект на Google
      return Response.found(googleAuthUrl.toString());
    } catch (e) {
      return _serverError('Failed to initiate OAuth: $e');
    }
  }

  /// GET /auth/oauth/google/callback
  /// Обрабатывает callback от Google: валидирует state, обменивает code на tokens.
  Future<Response> _googleCallback(Request req) async {
    try {
      final params = req.url.queryParameters;

      final code = params['code'];
      final state = params['state'];
      final error = params['error'];
      final errorDescription = params['error_description'];

      // Обработка ошибок от Google
      if (error != null) {
        final appRedirectUrl =
            _csrfStore.validate(state)?['app_redirect_url'] as String?;
        final errorUrl = appRedirectUrl != null
            ? Uri.parse(appRedirectUrl).replace(queryParameters: {
                'error': error,
                'error_description': errorDescription ?? error,
              }).toString()
            : '/auth/error?error=$error';

        return Response.found(errorUrl);
      }

      if (code == null || state == null) {
        return _badRequest('Missing code or state parameter');
      }

      // Валидация CSRF state
      final stateMetadata = _csrfStore.validate(state);
      if (stateMetadata == null) {
        return Response.forbidden(
            jsonEncode({
              'code': 'invalid_state',
              'message': 'Invalid or expired state parameter',
            }),
            headers: {'Content-Type': 'application/json'});
      }

      final redirectUri = stateMetadata['redirect_uri'] as String;
      final appRedirectUrl = stateMetadata['app_redirect_url'] as String?;

      // Валидация PKCE если был предоставлен challenge
      final codeVerifier = params['code_verifier'];
      if (codeVerifier != null) {
        if (!_pkceStore.validate(state: state, codeVerifier: codeVerifier)) {
          return Response.forbidden(
              jsonEncode({
                'code': 'invalid_pkce',
                'message': 'Invalid code_verifier',
              }),
              headers: {'Content-Type': 'application/json'});
        }
      }

      // Обменять code на user info
      final googleUser = await googleOAuth.exchangeCode(
        code: code,
        redirectUri: redirectUri,
      );

      // Найти или создать пользователя
      final user = await userService.findOrCreateFromGoogle(googleUser);
      final tenant = await userService.findTenantById(user.tenantId);

      if (tenant == null) {
        throw Exception('Tenant not found: ${user.tenantId}');
      }

      // Создать сессию
      final session = await sessionService.create(
        userId: user.id,
        tenantId: user.tenantId,
        provider: IdentityProvider.google,
        ipAddress: req.context['ip'] as String?,
        userAgent: req.headers['user-agent'],
      );

      // Выдать токены
      final roles = await userService.getRolesForUser(user.id, user.tenantId);
      final tokens = tokenIssuer.issue(
        user: user,
        session: session,
        roles: roles,
      );

      // Редирект обратно в приложение с токенами
      if (appRedirectUrl != null) {
        final expiresIn = tokens.accessExpiresAt - _now();
        final successUrl = Uri.parse(appRedirectUrl).replace(queryParameters: {
          'access_token': tokens.accessToken,
          'refresh_token': tokens.refreshToken,
          'expires_in': expiresIn.toString(),
        });
        return Response.found(successUrl.toString());
      }

      // Если нет app_redirect_url, возвращаем JSON
      return _ok({
        'user': user.toJson(),
        'tenant': tenant.toJson(),
        'tokens': tokens.toJson(),
        'session': session.toJson(),
      });
    } on GoogleOAuthException catch (e) {
      return _badRequest(e.message);
    } catch (e) {
      return _serverError('OAuth callback failed: $e');
    }
  }

  /// GET /auth/oauth/github/authorize
  /// Инициирует GitHub OAuth flow: генерирует state, сохраняет PKCE challenge, редиректит на GitHub.
  Future<Response> _githubAuthorize(Request req) async {
    if (githubOAuth == null) {
      return _badRequest('GitHub OAuth not configured');
    }

    try {
      final params = req.url.queryParameters;

      // Параметры от клиента
      final redirectUri = params['redirect_uri'];
      final codeChallenge = params['code_challenge'];
      final codeChallengeMethod = params['code_challenge_method'] ?? 'S256';
      final appRedirectUrl = params['app_redirect_url'];

      if (redirectUri == null) {
        return _badRequest('Missing redirect_uri parameter');
      }

      // Генерируем state для CSRF защиты
      final state = _csrfStore.generate(metadata: {
        'redirect_uri': redirectUri,
        'app_redirect_url': appRedirectUrl,
        'provider': 'github',
      });

      // Сохраняем PKCE challenge если предоставлен
      if (codeChallenge != null) {
        _pkceStore.store(
          state: state,
          codeChallenge: codeChallenge,
          codeChallengeMethod: codeChallengeMethod,
        );
      }

      // Строим GitHub OAuth URL
      final githubAuthUrl = Uri.https('github.com', '/login/oauth/authorize', {
        'client_id': githubOAuth!.config.clientId,
        'redirect_uri': redirectUri,
        'state': state,
        'scope': 'read:user user:email',
      });

      // Редирект на GitHub
      return Response.found(githubAuthUrl.toString());
    } catch (e) {
      return _serverError('Failed to initiate GitHub OAuth: $e');
    }
  }

  /// GET /auth/oauth/github/callback
  /// Обрабатывает callback от GitHub: валидирует state, обменивает code на tokens.
  Future<Response> _githubCallback(Request req) async {
    if (githubOAuth == null) {
      return _badRequest('GitHub OAuth not configured');
    }

    try {
      final params = req.url.queryParameters;

      final code = params['code'];
      final state = params['state'];
      final error = params['error'];
      final errorDescription = params['error_description'];

      // Обработка ошибок от GitHub
      if (error != null) {
        final appRedirectUrl =
            _csrfStore.validate(state)?['app_redirect_url'] as String?;
        final errorUrl = appRedirectUrl != null
            ? Uri.parse(appRedirectUrl).replace(queryParameters: {
                'error': error,
                'error_description': errorDescription ?? error,
              }).toString()
            : '/auth/error?error=$error';

        return Response.found(errorUrl);
      }

      if (code == null || state == null) {
        return _badRequest('Missing code or state parameter');
      }

      // Валидация CSRF state
      final stateMetadata = _csrfStore.validate(state);
      if (stateMetadata == null || stateMetadata['provider'] != 'github') {
        return Response.forbidden(
            jsonEncode({
              'code': 'invalid_state',
              'message': 'Invalid or expired state parameter',
            }),
            headers: {'Content-Type': 'application/json'});
      }

      final redirectUri = stateMetadata['redirect_uri'] as String;
      final appRedirectUrl = stateMetadata['app_redirect_url'] as String?;

      // Валидация PKCE если был предоставлен challenge
      final codeVerifier = params['code_verifier'];
      if (codeVerifier != null) {
        if (!_pkceStore.validate(state: state, codeVerifier: codeVerifier)) {
          return Response.forbidden(
              jsonEncode({
                'code': 'invalid_pkce',
                'message': 'Invalid code_verifier',
              }),
              headers: {'Content-Type': 'application/json'});
        }
      }

      // Обменять code на user info
      final githubUser = await githubOAuth!.exchangeCode(
        code: code,
        redirectUri: redirectUri,
      );

      // Найти или создать пользователя
      final user = await userService.findOrCreateFromGitHub(githubUser);
      final tenant = await userService.findTenantById(user.tenantId);

      if (tenant == null) {
        throw Exception('Tenant not found: ${user.tenantId}');
      }

      // Создать сессию
      final session = await sessionService.create(
        userId: user.id,
        tenantId: user.tenantId,
        provider: IdentityProvider.github,
        ipAddress: req.context['ip'] as String?,
        userAgent: req.headers['user-agent'],
      );

      // Выдать токены
      final roles = await userService.getRolesForUser(user.id, user.tenantId);
      final tokens = tokenIssuer.issue(
        user: user,
        session: session,
        roles: roles,
      );

      // Редирект обратно в приложение с токенами
      if (appRedirectUrl != null) {
        final expiresIn = tokens.accessExpiresAt - _now();
        final successUrl = Uri.parse(appRedirectUrl).replace(queryParameters: {
          'access_token': tokens.accessToken,
          'refresh_token': tokens.refreshToken,
          'expires_in': expiresIn.toString(),
        });
        return Response.found(successUrl.toString());
      }

      // Если нет app_redirect_url, возвращаем JSON
      return _ok({
        'user': user.toJson(),
        'tenant': tenant.toJson(),
        'tokens': tokens.toJson(),
        'session': session.toJson(),
      });
    } on GitHubOAuthException catch (e) {
      return _badRequest(e.message);
    } catch (e) {
      return _serverError('GitHub OAuth callback failed: $e');
    }
  }

  // ── Existing Handlers ─────────────────────────────────────────────────────

  /// POST /auth/register
  /// Регистрация нового пользователя с email/password.
  Future<Response> _register(Request req) async {
    try {
      final body = await _readBody(req);
      final email = body['email'] as String?;
      final password = body['password'] as String?;
      final displayName = body['displayName'] as String?;

      if (email == null || password == null) {
        return _badRequest('email and password are required');
      }

      // Регистрируем пользователя
      final user = await userService.registerWithEmailPassword(
        email: email,
        password: password,
        displayName: displayName,
      );

      // Генерируем verification token
      final verificationToken =
          _emailVerificationService.generateVerificationToken(email);

      // TODO: Отправить email с verification link
      // В production нужно интегрировать email service (SendGrid, AWS SES, etc.)
      // Пока возвращаем token в response для тестирования

      return Response(
        201,
        body: jsonEncode({
          'user': user.toJson(),
          'message': 'Registration successful. Please verify your email.',
          'verification_token': verificationToken, // только для dev/test
        }),
        headers: {'Content-Type': 'application/json'},
      );
    } on EmailPasswordException catch (e) {
      return _badRequest(e.message);
    } catch (e) {
      return _serverError('Registration failed: $e');
    }
  }

  /// POST /auth/verify-email
  /// Подтверждение email через verification token.
  Future<Response> _verifyEmail(Request req) async {
    try {
      final body = await _readBody(req);
      final token = body['token'] as String?;

      if (token == null) {
        return _badRequest('token is required');
      }

      // Валидируем token и получаем email
      final email = _emailVerificationService.validateVerificationToken(token);
      if (email == null) {
        return _badRequest('Invalid or expired verification token');
      }

      // Находим пользователя
      final user = await userService.findByEmail(email);
      if (user == null) {
        return _notFound('User not found');
      }

      // Помечаем email как verified
      final verifiedUser = await userService.markEmailVerified(user.id);

      return _ok({
        'user': verifiedUser.toJson(),
        'message': 'Email verified successfully',
      });
    } catch (e) {
      return _serverError('Email verification failed: $e');
    }
  }

  /// POST /auth/resend-verification
  /// Повторная отправка verification email.
  Future<Response> _resendVerification(Request req) async {
    try {
      final body = await _readBody(req);
      final email = body['email'] as String?;

      if (email == null) {
        return _badRequest('email is required');
      }

      // Проверяем, что пользователь существует
      final user = await userService.findByEmail(email);
      if (user == null) {
        return _notFound('User not found');
      }

      // Проверяем, что email ещё не verified
      if (user.isVerified) {
        return _badRequest('Email already verified');
      }

      // Отменяем старые токены
      _emailVerificationService.cancelVerificationTokens(email);

      // Генерируем новый token
      final verificationToken =
          _emailVerificationService.generateVerificationToken(email);

      // TODO: Отправить email

      return _ok({
        'message': 'Verification email sent',
        'verification_token': verificationToken, // только для dev/test
      });
    } catch (e) {
      return _serverError('Failed to resend verification: $e');
    }
  }

  /// POST /auth/forgot-password
  /// Инициирует password reset flow.
  Future<Response> _forgotPassword(Request req) async {
    try {
      final body = await _readBody(req);
      final email = body['email'] as String?;

      if (email == null) {
        return _badRequest('email is required');
      }

      // Находим пользователя
      final user = await userService.findByEmail(email);
      if (user == null) {
        // Не раскрываем, существует ли email (security best practice)
        return _ok(
            {'message': 'If the email exists, a reset link has been sent'});
      }

      // Проверяем, что это email/password пользователь
      if (user.authProvider != IdentityProvider.emailPassword) {
        return _ok(
            {'message': 'If the email exists, a reset link has been sent'});
      }

      // Отменяем старые reset токены
      _emailVerificationService.cancelResetTokens(user.id);

      // Генерируем reset token
      final resetToken =
          _emailVerificationService.generateResetToken(user.id, email);

      // TODO: Отправить email с reset link

      return _ok({
        'message': 'If the email exists, a reset link has been sent',
        'reset_token': resetToken, // только для dev/test
      });
    } catch (e) {
      return _serverError('Password reset failed: $e');
    }
  }

  /// POST /auth/reset-password
  /// Сбрасывает пароль используя reset token.
  Future<Response> _resetPassword(Request req) async {
    try {
      final body = await _readBody(req);
      final token = body['token'] as String?;
      final newPassword = body['newPassword'] as String?;

      if (token == null || newPassword == null) {
        return _badRequest('token and newPassword are required');
      }

      // Валидируем token и получаем userId
      final userId = _emailVerificationService.validateResetToken(token);
      if (userId == null) {
        return _badRequest('Invalid or expired reset token');
      }

      // Обновляем пароль
      await userService.updatePassword(
        userId: userId,
        newPassword: newPassword,
      );

      return _ok({'message': 'Password reset successful'});
    } on EmailPasswordException catch (e) {
      return _badRequest(e.message);
    } catch (e) {
      return _serverError('Password reset failed: $e');
    }
  }

  /// POST /auth/magic-link/send
  /// Отправляет magic link на email.
  Future<Response> _sendMagicLink(Request req) async {
    try {
      final body = await _readBody(req);
      final email = body['email'] as String?;
      final displayName = body['displayName'] as String?;

      if (email == null) {
        return _badRequest('email is required');
      }

      // Проверяем, существует ли пользователь
      final existingUser = await userService.findByEmail(email);
      final isNewUser = existingUser == null;

      // Отменяем старые magic links
      _magicLinkService.cancelTokens(email);

      // Генерируем magic link token
      final token = _magicLinkService.generateToken(
        email: email,
        newUser: isNewUser,
        displayName: displayName,
      );

      // TODO: Отправить email с magic link
      // В production: emailService.sendMagicLink(email, token)

      return _ok({
        'message': 'Magic link sent to your email',
        'magic_link_token': token, // только для dev/test
        'is_new_user': isNewUser,
      });
    } catch (e) {
      return _serverError('Failed to send magic link: $e');
    }
  }

  /// GET /auth/magic-link/verify
  /// Верифицирует magic link и выполняет автоматический login.
  Future<Response> _verifyMagicLink(Request req) async {
    try {
      final params = req.url.queryParameters;
      final token = params['token'];

      if (token == null) {
        return _badRequest('token is required');
      }

      // Валидируем token
      final magicLinkData = _magicLinkService.validateToken(token);
      if (magicLinkData == null) {
        return _badRequest('Invalid or expired magic link');
      }

      // Найти или создать пользователя
      final user = await userService.findOrCreateForMagicLink(
        email: magicLinkData.email,
        displayName: magicLinkData.displayName,
      );

      final tenant = await userService.findTenantById(user.tenantId);
      if (tenant == null) {
        throw Exception('Tenant not found: ${user.tenantId}');
      }

      // Создать сессию
      final session = await sessionService.create(
        userId: user.id,
        tenantId: user.tenantId,
        provider: IdentityProvider
            .emailPassword, // magic link использует emailPassword
        ipAddress: req.context['ip'] as String?,
        userAgent: req.headers['user-agent'],
      );

      // Выдать токены
      final roles = await userService.getRolesForUser(user.id, user.tenantId);
      final tokens = tokenIssuer.issue(
        user: user,
        session: session,
        roles: roles,
      );

      return _ok({
        'user': user.toJson(),
        'tenant': tenant.toJson(),
        'tokens': tokens.toJson(),
        'session': session.toJson(),
        'is_new_user': magicLinkData.newUser,
      });
    } catch (e) {
      return _serverError('Magic link verification failed: $e');
    }
  }

  // ── Existing Handlers ─────────────────────────────────────────────────────

  Future<AuthResponse> _handleGoogleOAuth(
    Request req,
    GoogleOAuthCredentials creds,
  ) async {
    // Обменять code на Google user info
    final googleUser = await googleOAuth.exchangeCode(
      code: creds.code,
      redirectUri: creds.redirectUri,
    );

    // Найти или создать пользователя
    final user = await userService.findOrCreateFromGoogle(googleUser);
    final tenant = await userService.findTenantById(user.tenantId);

    if (tenant == null) {
      throw Exception('Tenant not found: ${user.tenantId}');
    }

    // Создать сессию
    final session = await sessionService.create(
      userId: user.id,
      tenantId: user.tenantId,
      provider: IdentityProvider.google,
      ipAddress: req.context['ip'] as String?,
      userAgent: req.headers['user-agent'],
    );

    // Выдать токены
    final roles = await userService.getRolesForUser(user.id, user.tenantId);
    final tokens = tokenIssuer.issue(
      user: user,
      session: session,
      roles: roles,
    );

    return AuthResponse(
      user: user,
      tenant: tenant,
      tokens: tokens,
      session: session,
    );
  }

  Future<AuthResponse> _handleApiKey(
    Request req,
    ApiKeyCredentials creds,
  ) async {
    // Валидировать API ключ
    final apiKey = await apiKeyService.validate(creds.apiKey);
    if (apiKey == null || !apiKey.isActive || apiKey.isExpired) {
      throw Exception('Invalid or expired API key');
    }

    // Получить пользователя
    final user = await userService.findById(apiKey.userId);
    if (user == null || !user.isActive) {
      throw Exception('User not found or inactive');
    }

    final tenant = await userService.findTenantById(user.tenantId);
    if (tenant == null) {
      throw Exception('Tenant not found: ${user.tenantId}');
    }

    // Обновить lastUsedAt (TODO: добавить метод в ApiKeyService)
    // await apiKeyService.trackUsage(apiKey.id);

    // Создать сессию
    final session = await sessionService.create(
      userId: user.id,
      tenantId: user.tenantId,
      provider: IdentityProvider.apiKey,
      ipAddress: req.context['ip'] as String?,
      userAgent: req.headers['user-agent'],
    );

    // Выдать токены с permissions из API ключа
    final fakeRole = AqRole(
      id: 'api-key-role',
      name: 'api_key',
      permissions: apiKey.permissions,
    );
    final tokens = tokenIssuer.issue(
      user: user,
      session: session,
      roles: [fakeRole],
    );

    return AuthResponse(
      user: user,
      tenant: tenant,
      tokens: tokens,
      session: session,
    );
  }

  Future<AuthResponse> _handleEmailPassword(
    Request req,
    EmailPasswordCredentials creds,
  ) async {
    // Аутентифицировать пользователя
    final user = await userService.authenticateWithEmailPassword(
      email: creds.email,
      password: creds.password,
    );

    final tenant = await userService.findTenantById(user.tenantId);
    if (tenant == null) {
      throw Exception('Tenant not found: ${user.tenantId}');
    }

    // Создать сессию
    final session = await sessionService.create(
      userId: user.id,
      tenantId: user.tenantId,
      provider: IdentityProvider.emailPassword,
      ipAddress: req.context['ip'] as String?,
      userAgent: req.headers['user-agent'],
    );

    // Выдать токены
    final roles = await userService.getRolesForUser(user.id, user.tenantId);
    final tokens = tokenIssuer.issue(
      user: user,
      session: session,
      roles: roles,
    );

    return AuthResponse(
      user: user,
      tenant: tenant,
      tokens: tokens,
      session: session,
    );
  }

  Future<AuthResponse> _handleServiceToken(
    Request req,
    ServiceTokenCredentials creds,
  ) async {
    // TODO: Реализовать для service accounts
    throw UnimplementedError('Service token auth not implemented yet');
  }

  Future<Response> _refresh(Request req) async {
    final body = await _readBody(req);
    final refreshToken = body['refreshToken'] as String?;
    if (refreshToken == null) return _badRequest('refreshToken required');

    final result = validator.validateRefresh(refreshToken);
    if (!result.valid)
      return _unauthorized(result.message ?? 'Invalid refresh token');

    final claims = result.claims!;

    // Check session still valid
    final session = await sessionService.validate(claims.sid);
    if (session == null) return _unauthorized('Session expired or revoked');

    final user = await userService.findById(claims.sub);
    if (user == null) return _unauthorized('User not found');

    final roles = await userService.getRolesForUser(user.id, user.tenantId);
    final tokens = tokenIssuer.reissue(
      refreshClaims: claims,
      user: user,
      session: session,
      roles: roles,
    );

    return _ok(tokens.toJson());
  }

  Future<Response> _logout(Request req) async {
    final claims = req.claims;
    if (claims == null) return _unauthorized('Not authenticated');

    await sessionService.revoke(claims.sid, reason: 'user_logout');
    return Response(204);
  }

  Future<Response> _me(Request req) async {
    final claims = req.claims;
    if (claims == null) return _unauthorized('Not authenticated');

    final user = await userService.findById(claims.sub);
    if (user == null) return _notFound('User not found');
    final tenant = await userService.findTenantById(claims.tid);
    if (tenant == null) return _notFound('Tenant not found');

    final session = await sessionService.validate(claims.sid);
    if (session == null) return _unauthorized('Session expired');

    // Synthesize tokens from claims (no new signing needed for /me)
    final tokens = TokenPair(
      accessToken: _extractRawToken(req) ?? '',
      refreshToken: '',
      accessExpiresAt: claims.exp,
      refreshExpiresAt: 0,
    );

    return _ok(AuthResponse(
      user: user,
      tenant: tenant,
      tokens: tokens,
      session: session,
    ).toJson());
  }

  Future<Response> _listSessions(Request req) async {
    final claims = req.claims;
    if (claims == null) return _unauthorized('Not authenticated');

    final sessions = await sessionService.listActive(claims.sub);
    return _ok(sessions.map((s) => s.toJson()).toList());
  }

  Future<Response> _revokeSession(Request req, String id) async {
    final claims = req.claims;
    if (claims == null) return _unauthorized('Not authenticated');

    final session = await sessionService.validate(id);
    if (session == null) return _notFound('Session not found');

    // Users can only revoke their own sessions
    if (session.userId != claims.sub &&
        claims.utype != UserType.platformAdmin) {
      return _forbidden('Cannot revoke another user\'s session');
    }

    await sessionService.revoke(id, reason: 'user_revoked');
    return Response(204);
  }

  Future<Response> _validate(Request req) async {
    final body = await _readBody(req);
    final validateReq = ValidateTokenRequest.fromJson(body);

    final result = validator.validate(validateReq.token);
    if (!result.valid) {
      return _ok(
          ValidateTokenResponse.fail(result.message ?? 'Invalid').toJson());
    }

    final claims = result.claims!;

    // Check session revocation
    final session = await sessionService.validate(claims.sid);
    if (session == null) {
      return _ok(ValidateTokenResponse.fail('Session revoked').toJson());
    }

    final permitted = validateReq.requiredPerms.isEmpty ||
        claims.hasAllPermissions(validateReq.requiredPerms);

    return _ok(ValidateTokenResponse.ok(claims, permitted: permitted).toJson());
  }

  Future<Response> _createApiKey(Request req) async {
    final claims = req.claims;
    if (claims == null) return _unauthorized('Not authenticated');

    final body = await _readBody(req);
    final name = body['name'] as String? ?? 'API Key';
    final perms = (body['permissions'] as List<dynamic>?)?.cast<String>() ??
        ['runs:*', 'graphs:read'];
    final isTest = body['isTest'] as bool? ?? false;
    final expiresAt = body['expiresAt'] as int?;

    final result = await apiKeyService.create(
      userId: claims.sub,
      tenantId: claims.tid,
      name: name,
      permissions: perms,
      isTest: isTest,
      expiresAt: expiresAt,
    );

    return Response(
      201,
      body: jsonEncode({
        ...result.record.toJson(),
        'key': result.rawKey, // ← shown ONCE
      }),
      headers: {'Content-Type': 'application/json'},
    );
  }

  Future<Response> _revokeApiKey(Request req, String id) async {
    final claims = req.claims;
    if (claims == null) return _unauthorized('Not authenticated');

    await apiKeyService.revoke(id);
    return Response(204);
  }

  Future<Response> _listApiKeys(Request req) async {
    final claims = req.claims;
    if (claims == null) return _unauthorized('Not authenticated');

    final keys = await apiKeyService.listForUser(claims.sub);
    return _ok({'keys': keys.map((k) => k.toJson()).toList()});
  }

  Future<Response> _rotateApiKey(Request req, String id) async {
    final claims = req.claims;
    if (claims == null) return _unauthorized('Not authenticated');

    try {
      final result = await apiKeyService.rotate(id);
      return Response(
        201,
        body: jsonEncode({
          ...result.record.toJson(),
          'key': result.rawKey, // ← shown ONCE
        }),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return _badRequest(e.toString());
    }
  }

  // ── Response helpers ───────────────────────────────────────────────────────

  Future<Response> _ok(Object body) async => Response.ok(
        jsonEncode(body),
        headers: {'Content-Type': 'application/json'},
      );

  Response _badRequest(String msg) => Response(
        400,
        body: jsonEncode({'code': 'bad_request', 'message': msg}),
        headers: {'Content-Type': 'application/json'},
      );

  Response _unauthorized(String msg) => Response(
        401,
        body: jsonEncode({'code': 'unauthorized', 'message': msg}),
        headers: {'Content-Type': 'application/json'},
      );

  Response _forbidden(String msg) => Response(
        403,
        body: jsonEncode({'code': 'forbidden', 'message': msg}),
        headers: {'Content-Type': 'application/json'},
      );

  Response _notFound(String msg) => Response(
        404,
        body: jsonEncode({'code': 'not_found', 'message': msg}),
        headers: {'Content-Type': 'application/json'},
      );

  Response _serverError(String msg) => Response(
        500,
        body: jsonEncode({'code': 'server_error', 'message': msg}),
        headers: {'Content-Type': 'application/json'},
      );

  Future<Map<String, dynamic>> _readBody(Request req) async {
    final body = await req.readAsString();
    return jsonDecode(body) as Map<String, dynamic>;
  }

  String? _extractRawToken(Request req) {
    final header = req.headers['authorization'];
    if (header == null || !header.startsWith('Bearer ')) return null;
    return header.substring(7).trim();
  }

  static int _now() => DateTime.now().millisecondsSinceEpoch ~/ 1000;
}
