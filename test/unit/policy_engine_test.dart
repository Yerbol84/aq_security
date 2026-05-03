// test/unit/policy_engine_test.dart
//
// Тесты для PolicyEngine

import 'package:test/test.dart';
import 'package:aq_security/aq_security_server.dart';
import 'package:aq_schema/security/security.dart';

// Mock repository для тестирования
class MockPolicyRepository implements IPolicyRepository {
  final Map<String, AqPolicy> _storage = {};

  @override
  Future<AqPolicy> create(AqPolicy policy) async {
    _storage[policy.id] = policy;
    return policy;
  }

  @override
  Future<AqPolicy> update(AqPolicy policy) async {
    _storage[policy.id] = policy;
    return policy;
  }

  @override
  Future<void> delete(String policyId) async {
    _storage.remove(policyId);
  }

  @override
  Future<AqPolicy?> findById(String id) async {
    return _storage[id];
  }

  @override
  Future<List<AqPolicy>> findByTenant(String tenantId) async {
    return _storage.values.where((p) => p.tenantId == tenantId).toList();
  }

  @override
  Future<List<AqPolicy>> findActive(String tenantId) async {
    return _storage.values
        .where((p) => p.tenantId == tenantId && p.isActive)
        .toList();
  }
}

void main() {
  group('PolicyEngine', () {
    late PolicyEngine engine;
    late MockPolicyRepository repo;

    setUp(() {
      repo = MockPolicyRepository();
      engine = PolicyEngine(repo: repo);
    });

    group('time_range conditions', () {
      test('allow доступ в рабочее время', () async {
        final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
        final start = now - 3600; // 1 час назад
        final end = now + 3600;   // 1 час вперёд

        final policy = AqPolicy(
          id: 'policy1',
          name: 'Business Hours',
          tenantId: 'tenant1',
          statements: [
            PolicyStatement(
              effect: PolicyEffect.allow,
              conditions: [
                PolicyCondition(
                  type: PolicyConditionType.timeRange,
                  operator: PolicyOperator.equals,
                  value: {'start': start, 'end': end},
                ),
              ],
            ),
          ],
          createdAt: now,
          createdBy: 'admin',
        );

        await repo.create(policy);

        final context = PolicyContext(
          userId: 'user1',
          tenantId: 'tenant1',
          timestamp: now,
        );

        final result = await engine.evaluate(
          tenantId: 'tenant1',
          context: context,
        );

        expect(result.allowed, isTrue);
      });

      test('deny доступ вне рабочего времени', () async {
        final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
        final start = now + 3600; // 1 час вперёд
        final end = now + 7200;   // 2 часа вперёд

        final policy = AqPolicy(
          id: 'policy1',
          name: 'Business Hours',
          tenantId: 'tenant1',
          statements: [
            PolicyStatement(
              effect: PolicyEffect.allow,
              conditions: [
                PolicyCondition(
                  type: PolicyConditionType.timeRange,
                  operator: PolicyOperator.equals,
                  value: {'start': start, 'end': end},
                ),
              ],
            ),
          ],
          createdAt: now,
          createdBy: 'admin',
        );

        await repo.create(policy);

        final context = PolicyContext(
          userId: 'user1',
          tenantId: 'tenant1',
          timestamp: now,
        );

        final result = await engine.evaluate(
          tenantId: 'tenant1',
          context: context,
        );

        expect(result.allowed, isFalse);
      });
    });

    group('ip_address conditions', () {
      test('allow доступ с разрешённого IP', () async {
        final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;

        final policy = AqPolicy(
          id: 'policy1',
          name: 'Office IP Only',
          tenantId: 'tenant1',
          statements: [
            PolicyStatement(
              effect: PolicyEffect.allow,
              conditions: [
                PolicyCondition(
                  type: PolicyConditionType.ipAddress,
                  operator: PolicyOperator.equals,
                  value: '192.168.1.100',
                ),
              ],
            ),
          ],
          createdAt: now,
          createdBy: 'admin',
        );

        await repo.create(policy);

        final context = PolicyContext(
          userId: 'user1',
          tenantId: 'tenant1',
          ipAddress: '192.168.1.100',
        );

        final result = await engine.evaluate(
          tenantId: 'tenant1',
          context: context,
        );

        expect(result.allowed, isTrue);
      });

      test('deny доступ с неразрешённого IP', () async {
        final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;

        final policy = AqPolicy(
          id: 'policy1',
          name: 'Office IP Only',
          tenantId: 'tenant1',
          statements: [
            PolicyStatement(
              effect: PolicyEffect.allow,
              conditions: [
                PolicyCondition(
                  type: PolicyConditionType.ipAddress,
                  operator: PolicyOperator.equals,
                  value: '192.168.1.100',
                ),
              ],
            ),
          ],
          createdAt: now,
          createdBy: 'admin',
        );

        await repo.create(policy);

        final context = PolicyContext(
          userId: 'user1',
          tenantId: 'tenant1',
          ipAddress: '10.0.0.1',
        );

        final result = await engine.evaluate(
          tenantId: 'tenant1',
          context: context,
        );

        expect(result.allowed, isFalse);
      });
    });

    group('user_attribute conditions', () {
      test('allow доступ для пользователя с атрибутом', () async {
        final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;

        final policy = AqPolicy(
          id: 'policy1',
          name: 'Premium Users Only',
          tenantId: 'tenant1',
          statements: [
            PolicyStatement(
              effect: PolicyEffect.allow,
              conditions: [
                PolicyCondition(
                  type: PolicyConditionType.userAttribute,
                  operator: PolicyOperator.equals,
                  field: 'subscription',
                  value: 'premium',
                ),
              ],
            ),
          ],
          createdAt: now,
          createdBy: 'admin',
        );

        await repo.create(policy);

        final context = PolicyContext(
          userId: 'user1',
          tenantId: 'tenant1',
          userAttributes: {'subscription': 'premium'},
        );

        final result = await engine.evaluate(
          tenantId: 'tenant1',
          context: context,
        );

        expect(result.allowed, isTrue);
      });
    });

    group('scope conditions', () {
      test('allow доступ с требуемым scope', () async {
        final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;

        final policy = AqPolicy(
          id: 'policy1',
          name: 'Projects Read',
          tenantId: 'tenant1',
          statements: [
            PolicyStatement(
              effect: PolicyEffect.allow,
              conditions: [
                PolicyCondition(
                  type: PolicyConditionType.scope,
                  operator: PolicyOperator.equals,
                  value: 'projects:read',
                ),
              ],
            ),
          ],
          createdAt: now,
          createdBy: 'admin',
        );

        await repo.create(policy);

        final context = PolicyContext(
          userId: 'user1',
          tenantId: 'tenant1',
          scopes: ['projects:read', 'graphs:write'],
        );

        final result = await engine.evaluate(
          tenantId: 'tenant1',
          context: context,
        );

        expect(result.allowed, isTrue);
      });
    });

    group('role conditions', () {
      test('allow доступ для роли admin', () async {
        final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;

        final policy = AqPolicy(
          id: 'policy1',
          name: 'Admin Only',
          tenantId: 'tenant1',
          statements: [
            PolicyStatement(
              effect: PolicyEffect.allow,
              conditions: [
                PolicyCondition(
                  type: PolicyConditionType.role,
                  operator: PolicyOperator.equals,
                  value: 'admin',
                ),
              ],
            ),
          ],
          createdAt: now,
          createdBy: 'admin',
        );

        await repo.create(policy);

        final context = PolicyContext(
          userId: 'user1',
          tenantId: 'tenant1',
          roles: ['admin', 'developer'],
        );

        final result = await engine.evaluate(
          tenantId: 'tenant1',
          context: context,
        );

        expect(result.allowed, isTrue);
      });
    });

    group('logic operators', () {
      test('AND logic требует все условия', () async {
        final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;

        final policy = AqPolicy(
          id: 'policy1',
          name: 'Admin AND Premium',
          tenantId: 'tenant1',
          statements: [
            PolicyStatement(
              effect: PolicyEffect.allow,
              logic: PolicyLogic.and,
              conditions: [
                PolicyCondition(
                  type: PolicyConditionType.role,
                  operator: PolicyOperator.equals,
                  value: 'admin',
                ),
                PolicyCondition(
                  type: PolicyConditionType.userAttribute,
                  operator: PolicyOperator.equals,
                  field: 'subscription',
                  value: 'premium',
                ),
              ],
            ),
          ],
          createdAt: now,
          createdBy: 'admin',
        );

        await repo.create(policy);

        // Оба условия выполнены
        final context1 = PolicyContext(
          userId: 'user1',
          tenantId: 'tenant1',
          roles: ['admin'],
          userAttributes: {'subscription': 'premium'},
        );

        final result1 = await engine.evaluate(
          tenantId: 'tenant1',
          context: context1,
        );

        expect(result1.allowed, isTrue);

        // Только одно условие
        final context2 = PolicyContext(
          userId: 'user2',
          tenantId: 'tenant1',
          roles: ['admin'],
          userAttributes: {'subscription': 'free'},
        );

        final result2 = await engine.evaluate(
          tenantId: 'tenant1',
          context: context2,
        );

        expect(result2.allowed, isFalse);
      });

      test('OR logic требует хотя бы одно условие', () async {
        final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;

        final policy = AqPolicy(
          id: 'policy1',
          name: 'Admin OR Premium',
          tenantId: 'tenant1',
          statements: [
            PolicyStatement(
              effect: PolicyEffect.allow,
              logic: PolicyLogic.or,
              conditions: [
                PolicyCondition(
                  type: PolicyConditionType.role,
                  operator: PolicyOperator.equals,
                  value: 'admin',
                ),
                PolicyCondition(
                  type: PolicyConditionType.userAttribute,
                  operator: PolicyOperator.equals,
                  field: 'subscription',
                  value: 'premium',
                ),
              ],
            ),
          ],
          createdAt: now,
          createdBy: 'admin',
        );

        await repo.create(policy);

        // Только admin
        final context1 = PolicyContext(
          userId: 'user1',
          tenantId: 'tenant1',
          roles: ['admin'],
          userAttributes: {'subscription': 'free'},
        );

        final result1 = await engine.evaluate(
          tenantId: 'tenant1',
          context: context1,
        );

        expect(result1.allowed, isTrue);

        // Только premium
        final context2 = PolicyContext(
          userId: 'user2',
          tenantId: 'tenant1',
          roles: ['user'],
          userAttributes: {'subscription': 'premium'},
        );

        final result2 = await engine.evaluate(
          tenantId: 'tenant1',
          context: context2,
        );

        expect(result2.allowed, isTrue);
      });
    });

    group('policy priority', () {
      test('deny policy с высоким приоритетом побеждает', () async {
        final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;

        // Allow policy (низкий приоритет)
        final allowPolicy = AqPolicy(
          id: 'allow',
          name: 'Allow All',
          tenantId: 'tenant1',
          priority: 0,
          statements: [
            PolicyStatement(
              effect: PolicyEffect.allow,
              conditions: [],
            ),
          ],
          createdAt: now,
          createdBy: 'admin',
        );

        // Deny policy (высокий приоритет)
        final denyPolicy = AqPolicy(
          id: 'deny',
          name: 'Deny Specific',
          tenantId: 'tenant1',
          priority: 10,
          statements: [
            PolicyStatement(
              effect: PolicyEffect.deny,
              conditions: [
                PolicyCondition(
                  type: PolicyConditionType.role,
                  operator: PolicyOperator.equals,
                  value: 'blocked',
                ),
              ],
            ),
          ],
          createdAt: now,
          createdBy: 'admin',
        );

        await repo.create(allowPolicy);
        await repo.create(denyPolicy);

        final context = PolicyContext(
          userId: 'user1',
          tenantId: 'tenant1',
          roles: ['blocked'],
        );

        final result = await engine.evaluate(
          tenantId: 'tenant1',
          context: context,
        );

        expect(result.allowed, isFalse);
        expect(result.reason, contains('Deny Specific'));
      });
    });

    group('default deny', () {
      test('deny если нет matching policies', () async {
        final context = PolicyContext(
          userId: 'user1',
          tenantId: 'tenant1',
        );

        final result = await engine.evaluate(
          tenantId: 'tenant1',
          context: context,
        );

        expect(result.allowed, isFalse);
        expect(result.reason, contains('No matching allow policy'));
      });
    });
  });
}
