// test/unit/oauth_flow_test.dart
//
// Тесты для OAuth flow: authorize, callback, CSRF, PKCE

import 'package:test/test.dart';
import 'package:aq_security/aq_security_server.dart';

void main() {
  group('CsrfStore', () {
    late CsrfStore store;

    setUp(() {
      store = CsrfStore(ttl: const Duration(seconds: 2));
    });

    test('generate создаёт уникальный state token', () {
      final state1 = store.generate();
      final state2 = store.generate();

      expect(state1, isNotEmpty);
      expect(state2, isNotEmpty);
      expect(state1, isNot(equals(state2)));
    });

    test('validate возвращает metadata для валидного state', () {
      final metadata = {'user_id': '123', 'redirect': '/app'};
      final state = store.generate(metadata: metadata);

      final result = store.validate(state);

      expect(result, equals(metadata));
    });

    test('validate возвращает null для невалидного state', () {
      final result = store.validate('invalid_state');

      expect(result, isNull);
    });

    test('validate удаляет state после использования (one-time use)', () {
      final state = store.generate(metadata: {'test': 'data'});

      final result1 = store.validate(state);
      final result2 = store.validate(state);

      expect(result1, isNotNull);
      expect(result1, equals({'test': 'data'}));
      expect(result2, isNull);
    });

    test('validate возвращает null для истёкшего state', () async {
      final state = store.generate();

      await Future.delayed(const Duration(seconds: 3));

      final result = store.validate(state);

      expect(result, isNull);
    });

    test('cleanup удаляет истёкшие state tokens', () async {
      store.generate();
      store.generate();

      expect(store.activeCount, equals(2));

      await Future.delayed(const Duration(seconds: 3));

      expect(store.activeCount, equals(0));
    });
  });

  group('PkceStore', () {
    late PkceStore store;

    setUp(() {
      store = PkceStore(ttl: const Duration(seconds: 2));
    });

    test('validate возвращает true для валидного code_verifier (S256)', () {
      const state = 'test_state';
      const codeVerifier = 'dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk';
      const codeChallenge = 'E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM';

      store.store(
        state: state,
        codeChallenge: codeChallenge,
        codeChallengeMethod: 'S256',
      );

      final result = store.validate(
        state: state,
        codeVerifier: codeVerifier,
      );

      expect(result, isTrue);
    });

    test('validate возвращает true для валидного code_verifier (plain)', () {
      const state = 'test_state';
      const codeVerifier = 'my_secret_verifier';

      store.store(
        state: state,
        codeChallenge: codeVerifier,
        codeChallengeMethod: 'plain',
      );

      final result = store.validate(
        state: state,
        codeVerifier: codeVerifier,
      );

      expect(result, isTrue);
    });

    test('validate возвращает false для неправильного code_verifier', () {
      const state = 'test_state';
      const codeChallenge = 'E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM';

      store.store(
        state: state,
        codeChallenge: codeChallenge,
        codeChallengeMethod: 'S256',
      );

      final result = store.validate(
        state: state,
        codeVerifier: 'wrong_verifier',
      );

      expect(result, isFalse);
    });

    test('validate возвращает false для несуществующего state', () {
      final result = store.validate(
        state: 'nonexistent_state',
        codeVerifier: 'any_verifier',
      );

      expect(result, isFalse);
    });

    test('validate удаляет challenge после использования (one-time use)', () {
      const state = 'test_state';
      const codeVerifier = 'dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk';
      const codeChallenge = 'E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM';

      store.store(
        state: state,
        codeChallenge: codeChallenge,
        codeChallengeMethod: 'S256',
      );

      final result1 = store.validate(state: state, codeVerifier: codeVerifier);
      final result2 = store.validate(state: state, codeVerifier: codeVerifier);

      expect(result1, isTrue);
      expect(result2, isFalse);
    });

    test('validate возвращает false для истёкшего challenge', () async {
      const state = 'test_state';
      const codeVerifier = 'dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk';
      const codeChallenge = 'E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM';

      store.store(
        state: state,
        codeChallenge: codeChallenge,
        codeChallengeMethod: 'S256',
      );

      await Future.delayed(const Duration(seconds: 3));

      final result = store.validate(state: state, codeVerifier: codeVerifier);

      expect(result, isFalse);
    });

    test('cleanup удаляет истёкшие challenges', () async {
      store.store(
        state: 'state1',
        codeChallenge: 'challenge1',
        codeChallengeMethod: 'plain',
      );
      store.store(
        state: 'state2',
        codeChallenge: 'challenge2',
        codeChallengeMethod: 'plain',
      );

      expect(store.activeCount, equals(2));

      await Future.delayed(const Duration(seconds: 3));

      expect(store.activeCount, equals(0));
    });
  });
}
