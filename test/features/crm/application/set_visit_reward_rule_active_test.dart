import 'package:abakus_one_v2/core/errors/business_rule_violation.dart';
import 'package:abakus_one_v2/features/crm/application/use_cases/set_visit_reward_rule_active.dart';
import 'package:abakus_one_v2/features/crm/data/visit_reward_rule_repository.dart';
import 'package:abakus_one_v2/features/crm/domain/rewards/reward_type.dart';
import 'package:abakus_one_v2/features/crm/domain/rewards/visit_reward_config.dart';
import 'package:abakus_one_v2/features/crm/domain/rewards/visit_reward_rule.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_support/crm_test_fixtures.dart';

VisitRewardRule _buildRule(
    {String id = 'reward-rule-1', bool isActive = true}) {
  return VisitRewardRule(
    id: id,
    requiredVisitCount: 5,
    rewardType: RewardType.freeDrink,
    rewardConfig: const VisitRewardConfig(description: 'Bedava içecek'),
    isActive: isActive,
    createdByStaffId: 'manager-1',
    createdAt: DateTime(2026, 1, 1),
    revision: 1,
  );
}

void main() {
  group('SetVisitRewardRuleActive', () {
    test('deactivates an active rule', () async {
      final repository = InMemoryVisitRewardRuleRepository();
      await repository.save(_buildRule());
      final useCase = SetVisitRewardRuleActive(
        authorizationPolicy: const AllowAllCrmPolicy(),
        repository: repository,
      );

      final updated = await useCase(
        ruleId: 'reward-rule-1',
        isActive: false,
        performedByStaffId: 'manager-1',
      );

      expect(updated.isActive, isFalse);
      expect(updated.revision, 2);
    });

    test('an unknown rule id throws UnknownCrmEntityViolation', () async {
      final useCase = SetVisitRewardRuleActive(
        authorizationPolicy: const AllowAllCrmPolicy(),
        repository: InMemoryVisitRewardRuleRepository(),
      );

      expect(
        () => useCase(
          ruleId: 'missing',
          isActive: false,
          performedByStaffId: 'manager-1',
        ),
        throwsA(isA<UnknownCrmEntityViolation>()),
      );
    });

    test('an unauthorized actor cannot change activation', () async {
      final repository = InMemoryVisitRewardRuleRepository();
      await repository.save(_buildRule());
      final useCase = SetVisitRewardRuleActive(
        authorizationPolicy: const DenyAllCrmPolicy(),
        repository: repository,
      );

      expect(
        () => useCase(
          ruleId: 'reward-rule-1',
          isActive: false,
          performedByStaffId: 'staff-1',
        ),
        throwsA(isA<AuthorizationDeniedViolation>()),
      );
    });
  });
}
