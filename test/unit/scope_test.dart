// test/unit/scope_test.dart
//
// Тесты для AqScope и ScopeChecker

import 'package:test/test.dart';
import 'package:aq_schema/security/security.dart';

void main() {
  group('AqScope', () {
    group('parse', () {
      test('парсит простой scope "resource:action"', () {
        final scope = AqScope.parse('projects:read');

        expect(scope.resource, equals('projects'));
        expect(scope.action, equals('read'));
        expect(scope.resourceId, isNull);
        expect(scope.fullName, equals('projects:read'));
      });

      test('парсит scope с resourceId "resource:action:id"', () {
        final scope = AqScope.parse('projects:read:abc123');

        expect(scope.resource, equals('projects'));
        expect(scope.action, equals('read'));
        expect(scope.resourceId, equals('abc123'));
        expect(scope.fullName, equals('projects:read:abc123'));
      });

      test('выбрасывает FormatException для невалидного формата', () {
        expect(() => AqScope.parse('invalid'), throwsFormatException);
        expect(() => AqScope.parse(''), throwsFormatException);
        expect(() => AqScope.parse('only_one_part'), throwsFormatException);
      });
    });

    group('covers', () {
      test('admin покрывает все действия для ресурса', () {
        final admin = AqScope.parse('projects:admin');
        final read = AqScope.parse('projects:read');
        final write = AqScope.parse('projects:write');
        final delete = AqScope.parse('projects:delete');

        expect(admin.covers(read), isTrue);
        expect(admin.covers(write), isTrue);
        expect(admin.covers(delete), isTrue);
      });

      test('admin покрывает конкретные ресурсы', () {
        final admin = AqScope.parse('projects:admin');
        final specific = AqScope.parse('projects:read:abc123');

        expect(admin.covers(specific), isTrue);
      });

      test('общий scope покрывает конкретный ресурс', () {
        final general = AqScope.parse('projects:read');
        final specific = AqScope.parse('projects:read:abc123');

        expect(general.covers(specific), isTrue);
      });

      test('конкретный scope НЕ покрывает общий', () {
        final specific = AqScope.parse('projects:read:abc123');
        final general = AqScope.parse('projects:read');

        expect(specific.covers(general), isFalse);
      });

      test('конкретный scope покрывает только тот же ресурс', () {
        final scope1 = AqScope.parse('projects:read:abc123');
        final scope2 = AqScope.parse('projects:read:abc123');
        final scope3 = AqScope.parse('projects:read:xyz789');

        expect(scope1.covers(scope2), isTrue);
        expect(scope1.covers(scope3), isFalse);
      });

      test('разные действия НЕ покрывают друг друга', () {
        final read = AqScope.parse('projects:read');
        final write = AqScope.parse('projects:write');

        expect(read.covers(write), isFalse);
        expect(write.covers(read), isFalse);
      });

      test('разные ресурсы НЕ покрывают друг друга', () {
        final projects = AqScope.parse('projects:read');
        final graphs = AqScope.parse('graphs:read');

        expect(projects.covers(graphs), isFalse);
        expect(graphs.covers(projects), isFalse);
      });
    });

    group('equality', () {
      test('одинаковые scopes равны', () {
        final scope1 = AqScope.parse('projects:read');
        final scope2 = AqScope.parse('projects:read');

        expect(scope1, equals(scope2));
        expect(scope1.hashCode, equals(scope2.hashCode));
      });

      test('разные scopes не равны', () {
        final scope1 = AqScope.parse('projects:read');
        final scope2 = AqScope.parse('projects:write');

        expect(scope1, isNot(equals(scope2)));
      });
    });

    group('toString', () {
      test('возвращает fullName', () {
        final scope1 = AqScope.parse('projects:read');
        final scope2 = AqScope.parse('projects:read:abc123');

        expect(scope1.toString(), equals('projects:read'));
        expect(scope2.toString(), equals('projects:read:abc123'));
      });
    });
  });

  group('ScopeChecker', () {
    group('hasAny', () {
      test('возвращает true если есть хотя бы один scope', () {
        final checker = ScopeChecker(['projects:read', 'graphs:write']);

        expect(checker.hasAny(['projects:read']), isTrue);
        expect(checker.hasAny(['graphs:write']), isTrue);
        expect(checker.hasAny(['projects:read', 'users:admin']), isTrue);
      });

      test('возвращает false если нет ни одного scope', () {
        final checker = ScopeChecker(['projects:read']);

        expect(checker.hasAny(['projects:write']), isFalse);
        expect(checker.hasAny(['graphs:read']), isFalse);
      });

      test('возвращает true для пустого списка требований', () {
        final checker = ScopeChecker(['projects:read']);

        expect(checker.hasAny([]), isTrue);
      });

      test('работает с admin scope', () {
        final checker = ScopeChecker(['projects:admin']);

        expect(checker.hasAny(['projects:read']), isTrue);
        expect(checker.hasAny(['projects:write']), isTrue);
        expect(checker.hasAny(['projects:delete']), isTrue);
      });

      test('работает с конкретными ресурсами', () {
        final checker = ScopeChecker(['projects:read']);

        expect(checker.hasAny(['projects:read:abc123']), isTrue);
      });
    });

    group('hasAll', () {
      test('возвращает true если есть все scopes', () {
        final checker = ScopeChecker(['projects:read', 'projects:write', 'graphs:read']);

        expect(checker.hasAll(['projects:read', 'projects:write']), isTrue);
        expect(checker.hasAll(['projects:read']), isTrue);
      });

      test('возвращает false если нет хотя бы одного scope', () {
        final checker = ScopeChecker(['projects:read']);

        expect(checker.hasAll(['projects:read', 'projects:write']), isFalse);
      });

      test('возвращает true для пустого списка требований', () {
        final checker = ScopeChecker(['projects:read']);

        expect(checker.hasAll([]), isTrue);
      });

      test('работает с admin scope', () {
        final checker = ScopeChecker(['projects:admin']);

        expect(checker.hasAll(['projects:read', 'projects:write', 'projects:delete']), isTrue);
      });

      test('работает с конкретными ресурсами', () {
        final checker = ScopeChecker(['projects:read']);

        expect(checker.hasAll(['projects:read:abc123', 'projects:read:xyz789']), isTrue);
      });
    });

    group('has', () {
      test('проверяет конкретный scope', () {
        final checker = ScopeChecker(['projects:read', 'graphs:write']);

        expect(checker.has('projects:read'), isTrue);
        expect(checker.has('graphs:write'), isTrue);
        expect(checker.has('projects:write'), isFalse);
      });

      test('работает с admin scope', () {
        final checker = ScopeChecker(['projects:admin']);

        expect(checker.has('projects:read'), isTrue);
        expect(checker.has('projects:write'), isTrue);
      });
    });

    group('complex scenarios', () {
      test('system:admin покрывает всё', () {
        final checker = ScopeChecker(['system:admin']);

        expect(checker.has('system:audit'), isTrue);
        expect(checker.has('system:read'), isTrue);
      });

      test('множественные admin scopes', () {
        final checker = ScopeChecker(['projects:admin', 'graphs:admin']);

        expect(checker.hasAll(['projects:read', 'graphs:write']), isTrue);
        expect(checker.has('users:read'), isFalse);
      });

      test('смешанные общие и конкретные scopes', () {
        final checker = ScopeChecker([
          'projects:read',
          'projects:write:abc123',
          'graphs:admin',
        ]);

        expect(checker.has('projects:read'), isTrue);
        expect(checker.has('projects:read:xyz789'), isTrue);
        expect(checker.has('projects:write:abc123'), isTrue);
        expect(checker.has('projects:write:xyz789'), isFalse);
        expect(checker.has('graphs:read'), isTrue);
        expect(checker.has('graphs:execute'), isTrue);
      });
    });
  });

  group('AqScopes constants', () {
    test('все константы валидны', () {
      for (final scope in AqScopes.all) {
        expect(() => AqScope.parse(scope), returnsNormally);
      }
    });

    test('содержит основные scopes', () {
      expect(AqScopes.all, contains('projects:read'));
      expect(AqScopes.all, contains('projects:write'));
      expect(AqScopes.all, contains('projects:admin'));
      expect(AqScopes.all, contains('graphs:execute'));
      expect(AqScopes.all, contains('users:admin'));
      expect(AqScopes.all, contains('api_keys:rotate'));
      expect(AqScopes.all, contains('system:admin'));
    });
  });
}
