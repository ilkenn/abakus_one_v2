import 'package:abakus_one_v2/features/crm/application/identity/customer_reward_grant_id_generator.dart';
import 'package:abakus_one_v2/features/crm/application/use_cases/grant_visit_reward.dart';
import 'package:abakus_one_v2/features/crm/data/customer_reward_grant_repository.dart';
import 'package:abakus_one_v2/features/crm/domain/rewards/reward_type.dart';
import 'package:abakus_one_v2/features/crm/domain/rewards/visit_reward_config.dart';
import 'package:abakus_one_v2/features/crm/domain/rewards/visit_reward_rule.dart';
import 'package:flutter_test/flutter_test.dart';

VisitRewardRule _buildRule() {
  return VisitRewardRule(
    id: 'reward-rule-1',
    requiredVisitCount: 5,
    rewardType: RewardType.freeDrink,
    rewardConfig: const VisitRewardConfig(description: 'Bedava içecek'),
    createdByStaffId: 'manager-1',
    createdAt: DateTime(2026, 1, 1),
    revision: 1,
  );
}

void main() {
  group('GrantVisitReward', () {
    test('grants a reward and snapshots the rule reward type/config', () async {
      final repository = InMemoryCustomerRewardGrantRepository();
      final useCase = GrantVisitReward(
        idGenerator: SequentialCustomerRewardGrantIdGenerator(),
        repository: repository,
      );

      final grant = await useCase(
        customerId: 'customer-1',
        rule: _buildRule(),
        visitCountAtGrant: 5,
        grantedAt: DateTime(2026, 1, 5),
      );

      expect(grant, isNotNull);
      expect(grant!.rewardType, RewardType.freeDrink);
      expect(grant.rewardConfig.description, 'Bedava içecek');
      expect(await repository.findByCustomerId('customer-1'), [grant]);
    });

    test('never double-grants the same rule at the same visit count', () async {
      final repository = InMemoryCustomerRewardGrantRepository();
      final useCase = GrantVisitReward(
        idGenerator: SequentialCustomerRewardGrantIdGenerator(),
        repository: repository,
      );
      final rule = _buildRule();

      final first = await useCase(
        customerId: 'customer-1',
        rule: rule,
        visitCountAtGrant: 5,
        grantedAt: DateTime(2026, 1, 5),
      );
      final second = await useCase(
        customerId: 'customer-1',
        rule: rule,
        visitCountAtGrant: 5,
        grantedAt: DateTime(2026, 1, 6),
      );

      expect(first, isNotNull);
      expect(second, isNull);
      expect(await repository.findByCustomerId('customer-1'), hasLength(1));
    });

    test('reaching the same rule again at a higher visit count grants again',
        () async {
      final repository = InMemoryCustomerRewardGrantRepository();
      final useCase = GrantVisitReward(
        idGenerator: SequentialCustomerRewardGrantIdGenerator(),
        repository: repository,
      );
      final rule = _buildRule();

      await useCase(
        customerId: 'customer-1',
        rule: rule,
        visitCountAtGrant: 5,
        grantedAt: DateTime(2026, 1, 5),
      );
      final second = await useCase(
        customerId: 'customer-1',
        rule: rule,
        visitCountAtGrant: 10,
        grantedAt: DateTime(2026, 1, 10),
      );

      expect(second, isNotNull);
      expect(await repository.findByCustomerId('customer-1'), hasLength(2));
    });
  });
}
