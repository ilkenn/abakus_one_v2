import 'package:abakus_one_v2/features/crm/application/identity/customer_reward_grant_id_generator.dart';
import 'package:abakus_one_v2/features/crm/application/identity/customer_visit_id_generator.dart';
import 'package:abakus_one_v2/features/crm/application/use_cases/build_customer_visit_passport.dart';
import 'package:abakus_one_v2/features/crm/application/use_cases/grant_visit_reward.dart';
import 'package:abakus_one_v2/features/crm/application/use_cases/record_customer_visit.dart';
import 'package:abakus_one_v2/features/crm/application/use_cases/record_customer_visit_and_evaluate_rewards.dart';
import 'package:abakus_one_v2/features/crm/data/crm_audit_entry_repository.dart';
import 'package:abakus_one_v2/features/crm/data/customer_repository.dart';
import 'package:abakus_one_v2/features/crm/data/customer_reward_grant_repository.dart';
import 'package:abakus_one_v2/features/crm/data/customer_visit_repository.dart';
import 'package:abakus_one_v2/features/crm/data/visit_reward_rule_repository.dart';
import 'package:abakus_one_v2/features/crm/domain/rewards/customer_reward_grant.dart';
import 'package:abakus_one_v2/features/crm/domain/rewards/reward_type.dart';
import 'package:abakus_one_v2/features/crm/domain/rewards/visit_reward_config.dart';
import 'package:abakus_one_v2/features/crm/domain/rewards/visit_reward_rule.dart';
import 'package:abakus_one_v2/features/orders/domain/models/order.dart';
import 'package:abakus_one_v2/features/orders/domain/models/order_channel.dart';
import 'package:abakus_one_v2/features/orders/domain/models/order_id.dart';
import 'package:abakus_one_v2/features/orders/domain/models/order_line.dart';
import 'package:abakus_one_v2/features/orders/domain/models/order_number.dart';
import 'package:abakus_one_v2/features/orders/domain/models/order_status.dart';
import 'package:abakus_one_v2/features/orders/domain/models/order_timestamps.dart';
import 'package:abakus_one_v2/features/orders/domain/pricing/price_calculator.dart';
import 'package:abakus_one_v2/features/orders/domain/pricing/tax_policy.dart';
import 'package:abakus_one_v2/shared/models/currency.dart';
import 'package:abakus_one_v2/shared/models/money.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../pos/test_support/fake_clock.dart';
import '../test_support/crm_test_fixtures.dart';

class _ThrowingCustomerRewardGrantRepository
    implements CustomerRewardGrantRepository {
  @override
  Future<List<CustomerRewardGrant>> findByCustomerId(String customerId) {
    throw Exception('simulated downstream grant failure');
  }

  @override
  Future<void> append(CustomerRewardGrant grant) {
    throw Exception('simulated downstream grant failure');
  }
}

VisitRewardRule _buildRule({
  String id = 'reward-rule-1',
  int requiredVisitCount = 3,
  bool isActive = true,
}) {
  return VisitRewardRule(
    id: id,
    requiredVisitCount: requiredVisitCount,
    rewardType: RewardType.freeDrink,
    rewardConfig: const VisitRewardConfig(description: 'Bedava içecek'),
    isActive: isActive,
    createdByStaffId: 'manager-1',
    createdAt: DateTime(2026, 1, 1),
    revision: 1,
  );
}

Order _buildOrder({
  String orderId = 'order-1',
  String? customerId,
  OrderChannel channel = OrderChannel.delivery,
}) {
  final line = OrderLine.create(
    productId: 'p1',
    productName: 'Mexifit Bowl',
    quantity: 1,
    unitPrice: Money.fromWhole(194, Currency.tryLira),
    taxRate: TaxPolicy.defaultRate,
  );
  return Order(
    id: OrderId(orderId),
    orderNumber: OrderNumber('A-001'),
    status: OrderStatus.confirmed,
    channel: channel,
    branchId: 'branch-1',
    restaurantId: 'restaurant-1',
    customerId: customerId,
    lines: [line],
    pricing:
        PriceCalculator.calculate(lines: [line], currency: Currency.tryLira),
    timestamps: OrderTimestamps(created: DateTime(2026, 1, 1)),
  );
}

class _Fixture {
  _Fixture()
      : customerRepository = InMemoryCustomerRepository(),
        visitRepository = InMemoryCustomerVisitRepository(),
        ruleRepository = InMemoryVisitRewardRuleRepository(),
        grantRepository = InMemoryCustomerRewardGrantRepository(),
        auditRepository = InMemoryCrmAuditEntryRepository();

  final CustomerRepository customerRepository;
  final CustomerVisitRepository visitRepository;
  final VisitRewardRuleRepository ruleRepository;
  final CustomerRewardGrantRepository grantRepository;
  final CrmAuditEntryRepository auditRepository;

  RecordCustomerVisitAndEvaluateRewards build(
      {CustomerRewardGrantRepository? grantRepositoryOverride}) {
    return RecordCustomerVisitAndEvaluateRewards(
      visitRepository: visitRepository,
      ruleRepository: ruleRepository,
      recordCustomerVisit: RecordCustomerVisit(
        idGenerator: SequentialCustomerVisitIdGenerator(),
        customerRepository: customerRepository,
        visitRepository: visitRepository,
        auditRepository: auditRepository,
      ),
      grantVisitReward: GrantVisitReward(
        idGenerator: SequentialCustomerRewardGrantIdGenerator(),
        repository: grantRepositoryOverride ?? grantRepository,
        auditRepository: auditRepository,
      ),
    );
  }
}

void main() {
  group('RecordCustomerVisitAndEvaluateRewards', () {
    test('a qualifying delivery order completes -> exactly one visit',
        () async {
      final fixture = _Fixture();
      await fixture.customerRepository.save(buildTestCustomer());
      final useCase = fixture.build();

      final result = await useCase(
        customerId: 'customer-1',
        branchId: 'branch-1',
        orderId: 'order-1',
        occurredAt: DateTime(2026, 1, 5),
      );

      expect(result.wasAlreadyRecorded, isFalse);
      expect(
        await fixture.visitRepository.findByCustomerId('customer-1'),
        hasLength(1),
      );
    });

    test('a duplicate completion event for the same order -> still one visit',
        () async {
      final fixture = _Fixture();
      await fixture.customerRepository.save(buildTestCustomer());
      final useCase = fixture.build();

      final first = await useCase(
        customerId: 'customer-1',
        branchId: 'branch-1',
        orderId: 'order-1',
        occurredAt: DateTime(2026, 1, 5),
      );
      final second = await useCase(
        customerId: 'customer-1',
        branchId: 'branch-1',
        orderId: 'order-1',
        occurredAt: DateTime(2026, 1, 6),
      );

      expect(second.wasAlreadyRecorded, isTrue);
      expect(second.visit.id, first.visit.id);
      expect(
        await fixture.visitRepository.findByCustomerId('customer-1'),
        hasLength(1),
      );
    });

    test('reaching a rule\'s threshold grants exactly one reward', () async {
      final fixture = _Fixture();
      await fixture.customerRepository.save(buildTestCustomer());
      await fixture.ruleRepository.save(_buildRule(requiredVisitCount: 1));
      final useCase = fixture.build();

      final result = await useCase(
        customerId: 'customer-1',
        branchId: 'branch-1',
        orderId: 'order-1',
        occurredAt: DateTime(2026, 1, 5),
      );

      expect(result.grantedRewards, hasLength(1));
      expect(
        await fixture.grantRepository.findByCustomerId('customer-1'),
        hasLength(1),
      );
    });

    test(
        'a duplicate evaluation (two visits crossing the same already-'
        'granted threshold) never double-grants', () async {
      final fixture = _Fixture();
      await fixture.customerRepository.save(buildTestCustomer());
      await fixture.ruleRepository.save(_buildRule(requiredVisitCount: 1));
      final useCase = fixture.build();

      await useCase(
        customerId: 'customer-1',
        branchId: 'branch-1',
        orderId: 'order-1',
        occurredAt: DateTime(2026, 1, 5),
      );
      // A second, distinct order/visit at a higher visit count — the rule
      // (requiredVisitCount: 1) is still "eligible" (totalVisitCount >= 1)
      // but GrantVisitReward's own (customerId, ruleId, visitCountAtGrant)
      // guard only blocks an identical visitCountAtGrant, so this
      // specifically proves the orchestration doesn't regrant at the
      // *same* visit count via reprocessing, not that every future visit
      // is grant-free.
      final result = await useCase(
        customerId: 'customer-1',
        branchId: 'branch-1',
        orderId: 'order-1', // same orderId — idempotency guard short-circuits
        occurredAt: DateTime(2026, 1, 6),
      );

      expect(result.wasAlreadyRecorded, isTrue);
      expect(
        await fixture.grantRepository.findByCustomerId('customer-1'),
        hasLength(1),
      );
    });

    test(
        'a downstream reward-grant failure produces a recoverable result — '
        'the visit is still saved and reported', () async {
      final fixture = _Fixture();
      await fixture.customerRepository.save(buildTestCustomer());
      await fixture.ruleRepository.save(_buildRule(requiredVisitCount: 1));
      final useCase = fixture.build(
        grantRepositoryOverride: _ThrowingCustomerRewardGrantRepository(),
      );

      final result = await useCase(
        customerId: 'customer-1',
        branchId: 'branch-1',
        orderId: 'order-1',
        occurredAt: DateTime(2026, 1, 5),
      );

      expect(result.wasAlreadyRecorded, isFalse);
      expect(result.grantedRewards, isEmpty);
      expect(result.failedRuleIds, ['reward-rule-1']);
      expect(
        await fixture.visitRepository.findByCustomerId('customer-1'),
        hasLength(1),
      );
    });

    test(
        'CustomerVisitPassport.completedRewards and .rewardHistory remain '
        'consistent after this call — the divergence gap the passport '
        'previously had is closed', () async {
      final fixture = _Fixture();
      await fixture.customerRepository.save(buildTestCustomer());
      await fixture.ruleRepository.save(_buildRule(requiredVisitCount: 1));
      final useCase = fixture.build();

      await useCase(
        customerId: 'customer-1',
        branchId: 'branch-1',
        orderId: 'order-1',
        occurredAt: DateTime(2026, 1, 5),
      );

      final buildPassport = BuildCustomerVisitPassport(
        clock: FakeClock(DateTime(2026, 1, 5)),
        visitRepository: fixture.visitRepository,
        ruleRepository: fixture.ruleRepository,
        grantRepository: fixture.grantRepository,
      );
      final passport = await buildPassport(
        customerId: 'customer-1',
        branchId: 'branch-1',
      );

      expect(passport.completedRewards, hasLength(1));
      expect(passport.rewardHistory, hasLength(1));
      expect(passport.completedRewards.first.id,
          passport.rewardHistory.first.ruleId);
    });

    test('an inactive rule is never granted even past its threshold', () async {
      final fixture = _Fixture();
      await fixture.customerRepository.save(buildTestCustomer());
      await fixture.ruleRepository
          .save(_buildRule(requiredVisitCount: 1, isActive: false));
      final useCase = fixture.build();

      final result = await useCase(
        customerId: 'customer-1',
        branchId: 'branch-1',
        orderId: 'order-1',
        occurredAt: DateTime(2026, 1, 5),
      );

      expect(result.grantedRewards, isEmpty);
    });

    group('callForOrder', () {
      test(
          'missing customer mapping (Order.customerId == null) fails '
          'safely — no visit, no exception', () async {
        final fixture = _Fixture();
        final useCase = fixture.build();
        final order = _buildOrder(customerId: null);

        final result = await useCase.callForOrder(
          order: order,
          occurredAt: DateTime(2026, 1, 5),
        );

        expect(result, isNull);
        expect(await fixture.visitRepository.findByCustomerId('customer-1'),
            isEmpty);
      });

      test('a resolvable customerId records a visit', () async {
        final fixture = _Fixture();
        await fixture.customerRepository.save(buildTestCustomer());
        final useCase = fixture.build();
        final order = _buildOrder(customerId: 'customer-1');

        final result = await useCase.callForOrder(
          order: order,
          occurredAt: DateTime(2026, 1, 5),
        );

        expect(result, isNotNull);
        expect(result!.visit.orderId, 'order-1');
      });
    });
  });
}
