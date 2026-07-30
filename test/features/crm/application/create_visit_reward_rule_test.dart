import 'package:abakus_one_v2/core/errors/business_rule_violation.dart';
import 'package:abakus_one_v2/features/crm/application/identity/visit_reward_rule_id_generator.dart';
import 'package:abakus_one_v2/features/crm/application/use_cases/create_visit_reward_rule.dart';
import 'package:abakus_one_v2/features/crm/data/visit_reward_rule_repository.dart';
import 'package:abakus_one_v2/features/crm/domain/rewards/reward_type.dart';
import 'package:abakus_one_v2/features/crm/domain/rewards/visit_reward_config.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_support/crm_test_fixtures.dart';

void main() {
  group('CreateVisitRewardRule', () {
    test('creates an active rule with the given visit threshold', () async {
      final repository = InMemoryVisitRewardRuleRepository();
      final useCase = CreateVisitRewardRule(
        authorizationPolicy: const AllowAllCrmPolicy(),
        idGenerator: SequentialVisitRewardRuleIdGenerator(),
        repository: repository,
      );

      final rule = await useCase(
        requiredVisitCount: 5,
        rewardType: RewardType.freeDrink,
        rewardConfig: const VisitRewardConfig(description: 'Bedava içecek'),
        performedByStaffId: 'manager-1',
        createdAt: DateTime(2026, 1, 1),
      );

      expect(rule.requiredVisitCount, 5);
      expect(rule.isActive, isTrue);
      expect(await repository.findById(rule.id), rule);
    });

    test('rejects a non-positive requiredVisitCount', () async {
      final useCase = CreateVisitRewardRule(
        authorizationPolicy: const AllowAllCrmPolicy(),
        idGenerator: SequentialVisitRewardRuleIdGenerator(),
        repository: InMemoryVisitRewardRuleRepository(),
      );

      expect(
        () => useCase(
          requiredVisitCount: 0,
          rewardType: RewardType.loyaltyPoints,
          rewardConfig: const VisitRewardConfig(pointsAmount: 50),
          performedByStaffId: 'manager-1',
          createdAt: DateTime(2026, 1, 1),
        ),
        throwsA(isA<InvalidVisitRewardRuleViolation>()),
      );
    });

    test('an unauthorized actor cannot create a rule', () async {
      final useCase = CreateVisitRewardRule(
        authorizationPolicy: const DenyAllCrmPolicy(),
        idGenerator: SequentialVisitRewardRuleIdGenerator(),
        repository: InMemoryVisitRewardRuleRepository(),
      );

      expect(
        () => useCase(
          requiredVisitCount: 5,
          rewardType: RewardType.loyaltyPoints,
          rewardConfig: const VisitRewardConfig(pointsAmount: 50),
          performedByStaffId: 'staff-1',
          createdAt: DateTime(2026, 1, 1),
        ),
        throwsA(isA<AuthorizationDeniedViolation>()),
      );
    });
  });
}
