import 'package:abakus_one_v2/features/crm/application/use_cases/build_customer_visit_passport.dart';
import 'package:abakus_one_v2/features/crm/data/customer_reward_grant_repository.dart';
import 'package:abakus_one_v2/features/crm/data/customer_visit_repository.dart';
import 'package:abakus_one_v2/features/crm/data/visit_reward_rule_repository.dart';
import 'package:abakus_one_v2/features/crm/domain/rewards/customer_reward_grant.dart';
import 'package:abakus_one_v2/features/crm/domain/rewards/reward_type.dart';
import 'package:abakus_one_v2/features/crm/domain/rewards/visit_reward_config.dart';
import 'package:abakus_one_v2/features/crm/domain/rewards/visit_reward_rule.dart';
import 'package:abakus_one_v2/features/crm/domain/visits/customer_visit.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../pos/test_support/fake_clock.dart';

VisitRewardRule _rule({
  required String id,
  required int requiredVisitCount,
  bool isActive = true,
  List<String> branchIds = const [],
  DateTime? campaignStartDate,
  DateTime? campaignEndDate,
}) {
  return VisitRewardRule(
    id: id,
    requiredVisitCount: requiredVisitCount,
    rewardType: RewardType.freeDrink,
    rewardConfig: const VisitRewardConfig(description: 'Bedava içecek'),
    isActive: isActive,
    branchIds: branchIds,
    campaignStartDate: campaignStartDate,
    campaignEndDate: campaignEndDate,
    createdByStaffId: 'manager-1',
    createdAt: DateTime(2026, 1, 1),
    revision: 1,
  );
}

void main() {
  final now = DateTime(2026, 1, 10);

  group('BuildCustomerVisitPassport', () {
    test('reports the visit count, next reward, and progress ratio', () async {
      final visitRepository = InMemoryCustomerVisitRepository();
      for (var i = 0; i < 3; i++) {
        await visitRepository.append(CustomerVisit(
          id: 'visit-$i',
          customerId: 'customer-1',
          branchId: 'branch-1',
          occurredAt: DateTime(2026, 1, i + 1),
        ));
      }
      final ruleRepository = InMemoryVisitRewardRuleRepository();
      await ruleRepository.save(_rule(id: 'rule-5', requiredVisitCount: 5));
      await ruleRepository.save(_rule(id: 'rule-10', requiredVisitCount: 10));

      final useCase = BuildCustomerVisitPassport(
        clock: FakeClock(now),
        visitRepository: visitRepository,
        ruleRepository: ruleRepository,
        grantRepository: InMemoryCustomerRewardGrantRepository(),
      );

      final passport = await useCase(
        customerId: 'customer-1',
        branchId: 'branch-1',
      );

      expect(passport.totalVisitCount, 3);
      expect(passport.nextReward?.id, 'rule-5');
      expect(passport.progressRatioTowardNextReward, closeTo(0.6, 0.001));
      expect(passport.completedRewards, isEmpty);
    });

    test(
        'a reached threshold moves the rule into completedRewards and '
        'advances nextReward to the following rule', () async {
      final visitRepository = InMemoryCustomerVisitRepository();
      for (var i = 0; i < 5; i++) {
        await visitRepository.append(CustomerVisit(
          id: 'visit-$i',
          customerId: 'customer-1',
          branchId: 'branch-1',
          occurredAt: DateTime(2026, 1, i + 1),
        ));
      }
      final ruleRepository = InMemoryVisitRewardRuleRepository();
      await ruleRepository.save(_rule(id: 'rule-5', requiredVisitCount: 5));
      await ruleRepository.save(_rule(id: 'rule-10', requiredVisitCount: 10));

      final useCase = BuildCustomerVisitPassport(
        clock: FakeClock(now),
        visitRepository: visitRepository,
        ruleRepository: ruleRepository,
        grantRepository: InMemoryCustomerRewardGrantRepository(),
      );

      final passport = await useCase(
        customerId: 'customer-1',
        branchId: 'branch-1',
      );

      expect(passport.completedRewards.map((r) => r.id), ['rule-5']);
      expect(passport.nextReward?.id, 'rule-10');
    });

    test('an inactive rule is excluded from both next and completed', () async {
      final ruleRepository = InMemoryVisitRewardRuleRepository();
      await ruleRepository.save(
          _rule(id: 'rule-inactive', requiredVisitCount: 1, isActive: false));

      final useCase = BuildCustomerVisitPassport(
        clock: FakeClock(now),
        visitRepository: InMemoryCustomerVisitRepository(),
        ruleRepository: ruleRepository,
        grantRepository: InMemoryCustomerRewardGrantRepository(),
      );

      final passport = await useCase(
        customerId: 'customer-1',
        branchId: 'branch-1',
      );

      expect(passport.nextReward, isNull);
      expect(passport.completedRewards, isEmpty);
    });

    test('a rule restricted to another branch is excluded', () async {
      final ruleRepository = InMemoryVisitRewardRuleRepository();
      await ruleRepository.save(_rule(
        id: 'rule-other-branch',
        requiredVisitCount: 1,
        branchIds: const ['branch-2'],
      ));

      final useCase = BuildCustomerVisitPassport(
        clock: FakeClock(now),
        visitRepository: InMemoryCustomerVisitRepository(),
        ruleRepository: ruleRepository,
        grantRepository: InMemoryCustomerRewardGrantRepository(),
      );

      final passport = await useCase(
        customerId: 'customer-1',
        branchId: 'branch-1',
      );

      expect(passport.nextReward, isNull);
    });

    test('a rule outside its campaign window is excluded', () async {
      final ruleRepository = InMemoryVisitRewardRuleRepository();
      await ruleRepository.save(_rule(
        id: 'rule-expired',
        requiredVisitCount: 1,
        campaignStartDate: DateTime(2025, 1, 1),
        campaignEndDate: DateTime(2025, 12, 31),
      ));

      final useCase = BuildCustomerVisitPassport(
        clock: FakeClock(now),
        visitRepository: InMemoryCustomerVisitRepository(),
        ruleRepository: ruleRepository,
        grantRepository: InMemoryCustomerRewardGrantRepository(),
      );

      final passport = await useCase(
        customerId: 'customer-1',
        branchId: 'branch-1',
      );

      expect(passport.nextReward, isNull);
    });

    test('reward history reflects actually-granted rewards', () async {
      final grantRepository = InMemoryCustomerRewardGrantRepository();
      await grantRepository.append(CustomerRewardGrant(
        id: 'grant-1',
        customerId: 'customer-1',
        ruleId: 'rule-5',
        rewardType: RewardType.freeDrink,
        rewardConfig: const VisitRewardConfig(description: 'Bedava içecek'),
        visitCountAtGrant: 5,
        grantedAt: DateTime(2026, 1, 5),
      ));

      final useCase = BuildCustomerVisitPassport(
        clock: FakeClock(now),
        visitRepository: InMemoryCustomerVisitRepository(),
        ruleRepository: InMemoryVisitRewardRuleRepository(),
        grantRepository: grantRepository,
      );

      final passport = await useCase(
        customerId: 'customer-1',
        branchId: 'branch-1',
      );

      expect(passport.rewardHistory, hasLength(1));
      expect(passport.rewardHistory.first.ruleId, 'rule-5');
    });

    test('no configured rules yields a zeroed passport with null progress',
        () async {
      final useCase = BuildCustomerVisitPassport(
        clock: FakeClock(now),
        visitRepository: InMemoryCustomerVisitRepository(),
        ruleRepository: InMemoryVisitRewardRuleRepository(),
        grantRepository: InMemoryCustomerRewardGrantRepository(),
      );

      final passport = await useCase(
        customerId: 'customer-1',
        branchId: 'branch-1',
      );

      expect(passport.totalVisitCount, 0);
      expect(passport.nextReward, isNull);
      expect(passport.progressRatioTowardNextReward, isNull);
    });
  });
}
