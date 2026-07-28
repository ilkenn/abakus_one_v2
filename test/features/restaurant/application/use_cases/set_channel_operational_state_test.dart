import 'package:abakus_one_v2/core/errors/business_rule_violation.dart';
import 'package:abakus_one_v2/features/orders/domain/models/order_channel.dart';
import 'package:abakus_one_v2/features/restaurant/application/use_cases/set_channel_operational_state.dart';
import 'package:abakus_one_v2/features/restaurant/data/channel_operation_policy_repository.dart';
import 'package:abakus_one_v2/features/restaurant/data/restaurant_operations_audit_entry_repository.dart';
import 'package:abakus_one_v2/features/restaurant/domain/models/channel_acceptance_mode.dart';
import 'package:abakus_one_v2/features/restaurant/domain/models/channel_operation_policy.dart';
import 'package:abakus_one_v2/features/restaurant/domain/models/channel_operational_state.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../pos/test_support/fake_clock.dart';

void main() {
  test('moves an existing policy from open to busy', () async {
    final policyRepository = InMemoryChannelOperationPolicyRepository();
    final useCase = SetChannelOperationalState(
      clock: FakeClock(DateTime(2026, 7, 29)),
      policyRepository: policyRepository,
      auditRepository: InMemoryRestaurantOperationsAuditEntryRepository(),
    );
    await useCase(
      branchId: 'branch-1',
      channel: OrderChannel.delivery,
      operationalState: ChannelOperationalState.open,
      updatedByStaffId: 'staff-1',
    );

    final result = await useCase(
      branchId: 'branch-1',
      channel: OrderChannel.delivery,
      operationalState: ChannelOperationalState.busy,
      updatedByStaffId: 'staff-1',
    );

    expect(result.operationalState, ChannelOperationalState.busy);
  });

  test('rejects a direct attempt to set emergencyClosed through this use case',
      () async {
    final useCase = SetChannelOperationalState(
      clock: FakeClock(DateTime(2026, 7, 29)),
      policyRepository: InMemoryChannelOperationPolicyRepository(),
      auditRepository: InMemoryRestaurantOperationsAuditEntryRepository(),
    );

    expect(
      () => useCase(
        branchId: 'branch-1',
        channel: OrderChannel.delivery,
        operationalState: ChannelOperationalState.emergencyClosed,
        updatedByStaffId: 'staff-1',
      ),
      throwsA(isA<InvalidChannelOperationalStateTransitionViolation>()),
    );
  });

  test('from an emergencyClosed policy, only a transition to open is permitted',
      () async {
    final policyRepository = InMemoryChannelOperationPolicyRepository();
    await policyRepository.save(ChannelOperationPolicy(
      branchId: 'branch-1',
      channel: OrderChannel.delivery,
      acceptanceMode: ChannelAcceptanceMode.automatic,
      operationalState: ChannelOperationalState.emergencyClosed,
      updatedAt: DateTime(2026, 7, 29),
      updatedByStaffId: 'staff-1',
      revision: 1,
    ));
    final useCase = SetChannelOperationalState(
      clock: FakeClock(DateTime(2026, 7, 29)),
      policyRepository: policyRepository,
      auditRepository: InMemoryRestaurantOperationsAuditEntryRepository(),
    );

    expect(
      () => useCase(
        branchId: 'branch-1',
        channel: OrderChannel.delivery,
        operationalState: ChannelOperationalState.busy,
        updatedByStaffId: 'staff-1',
      ),
      throwsA(isA<InvalidChannelOperationalStateTransitionViolation>()),
    );

    final result = await useCase(
      branchId: 'branch-1',
      channel: OrderChannel.delivery,
      operationalState: ChannelOperationalState.open,
      updatedByStaffId: 'staff-1',
    );
    expect(result.operationalState, ChannelOperationalState.open);
  });
}
