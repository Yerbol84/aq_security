// pkgs/aq_security/lib/src/server/mfa_service.dart
//
// Реализация IMfaService — TOTP (RFC 6238).
// In-memory pending store: sessionId → _PendingChallenge.

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:aq_schema/security/security.dart';

final class MfaService implements IMfaService {
  MfaService({
    this.issuer = 'AQ Platform',
    this.challengeTtlSeconds = 300, // 5 минут на прохождение
  });

  final String issuer;
  final int challengeTtlSeconds;

  final _pending = <String, _PendingChallenge>{}; // sessionId → challenge

  @override
  Future<MfaChallenge> initiate({
    required String sessionId,
    required String userId,
    required String userEmail,
  }) async {
    final secret = _generateSecret();
    final expiresAt = DateTime.now().millisecondsSinceEpoch ~/ 1000 + challengeTtlSeconds;

    _pending[sessionId] = _PendingChallenge(secret: secret, expiresAt: expiresAt);

    final uri = _buildTotpUri(secret: secret, email: userEmail);
    return MfaChallenge(
      sessionId: sessionId,
      method: MfaMethod.totp,
      totpUri: uri,
      expiresAt: expiresAt,
    );
  }

  @override
  Future<MfaVerifyResult> verify({
    required String sessionId,
    required String code,
  }) async {
    final pending = _pending[sessionId];
    if (pending == null) return MfaVerifyResult.fail('no_pending_challenge');

    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    if (now > pending.expiresAt) {
      _pending.remove(sessionId);
      return MfaVerifyResult.fail('challenge_expired');
    }

    // Проверяем текущий и соседние окна (±1 для clock skew)
    final counter = now ~/ 30;
    for (final c in [counter - 1, counter, counter + 1]) {
      if (_totp(pending.secret, c) == code) {
        _pending.remove(sessionId);
        return MfaVerifyResult.ok;
      }
    }

    return MfaVerifyResult.fail('invalid_code');
  }

  @override
  Future<bool> hasPendingChallenge(String sessionId) async {
    final pending = _pending[sessionId];
    if (pending == null) return false;
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    if (now > pending.expiresAt) {
      _pending.remove(sessionId);
      return false;
    }
    return true;
  }

  @override
  Future<void> cancel(String sessionId) async => _pending.remove(sessionId);

  // ── TOTP (RFC 6238) ────────────────────────────────────────────────────────

  /// Генерирует 6-значный TOTP код для данного counter.
  String _totp(String base32Secret, int counter) {
    final key = _base32Decode(base32Secret);
    final msg = Uint8List(8);
    var c = counter;
    for (var i = 7; i >= 0; i--) {
      msg[i] = c & 0xff;
      c >>= 8;
    }
    final hmac = Hmac(sha1, key).convert(msg).bytes;
    final offset = hmac[19] & 0xf;
    final code = ((hmac[offset] & 0x7f) << 24 |
            (hmac[offset + 1] & 0xff) << 16 |
            (hmac[offset + 2] & 0xff) << 8 |
            (hmac[offset + 3] & 0xff)) %
        1000000;
    return code.toString().padLeft(6, '0');
  }

  /// Генерирует случайный Base32 secret (160 бит = 32 символа).
  String _generateSecret() {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';
    final rng = Random.secure();
    return List.generate(32, (_) => chars[rng.nextInt(chars.length)]).join();
  }

  /// Строит otpauth URI для QR кода.
  String _buildTotpUri({required String secret, required String email}) {
    final label = Uri.encodeComponent('$issuer:$email');
    return 'otpauth://totp/$label?secret=$secret&issuer=${Uri.encodeComponent(issuer)}&algorithm=SHA1&digits=6&period=30';
  }

  /// Декодирует Base32 строку в байты.
  List<int> _base32Decode(String input) {
    const alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';
    final clean = input.toUpperCase().replaceAll('=', '');
    var bits = 0;
    var value = 0;
    final output = <int>[];
    for (final char in clean.split('')) {
      final idx = alphabet.indexOf(char);
      if (idx < 0) continue;
      value = (value << 5) | idx;
      bits += 5;
      if (bits >= 8) {
        output.add((value >> (bits - 8)) & 0xff);
        bits -= 8;
      }
    }
    return output;
  }
}

final class _PendingChallenge {
  const _PendingChallenge({required this.secret, required this.expiresAt});
  final String secret;
  final int expiresAt;
}
