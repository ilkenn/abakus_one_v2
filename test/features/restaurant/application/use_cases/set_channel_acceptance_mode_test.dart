import 'package:abakus_one_v2/features/orders/domain/models/order_channel.dart';
import 'package:abakus_one_v2/features/restaurant/application/use_cases/set_channel_acceptance_mode.dart';
import 'package:abakus_one_v2/features/restaurant/data/channel_operation_policy_repository.dart';
import 'package:abakus_one_v2/features/restaurant/data/restaurant_operations_audit_entry_repository.dart';
import 'package:abakus_one_v2/features/restaurant/domain/audit/restaurant_operations_audit_event_type.dart';
import 'package:abakus_one_v2/features/restaurant/domain/models/channel_acceptance_mode.dart';
import 'package:abakus_one_v2/features/restaurant/domain/models/channel_operational_state.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../pos/test_support/fake_clock.dart';

void main() {
  test(
      'creates a new policy defaulting to open when none exists, and logs an audit entry',
      () async {
    final policyRepository = InMemoryChannelOperationPolicyRepository();
    final auditRepository = InMemoryRestaurantOperationsAuditEntryRepository();
    final useCase = SetChannelAcceptanceMode(
      clock: FakeClock(DateTime(2026, 7, 29)),
      policyRepository: policyRepository,
      auditRepository: auditRepository,
    );

    final result = await useCase(
      branchId: 'branch-1',
      channel: OrderChannel.delivery,
      acceptanceMode: ChannelAcceptanceMode.manual,
      updatedByStaffId: 'staff-1',
    );

    expect(result.acceptanceMode, ChannelAcceptanceMode.manual);
    expect(result.operationalState, ChannelOperationalState.open);
    expect(result.revision, 1);

    final events = await auditRepository.findByBranchId('branch-1');
    expect(events, hasLength(1));
    expect(events.first.type,
        RestaurantOperationsAuditEventType.channelAcceptanceModeChanged);
  });

  test('a second call increments the revision rather than overwriting',
      () async {
    final policyRepository = InMemoryChannelOperationPolicyRepository();
    final useCase = SetChannelAcceptanceMode(
      clock: FakeClock(DateTime(2026, 7, 29)),
      policyRepository: policyRepository,
      auditRepository: InMemoryRestaurantOperationsAuditEntryRepository(),
    );

    await useCase(
      branchId: 'branch-1',
      channel: OrderChannel.delivery,
      acceptanceMode: ChannelAcceptanceMode.manual,
      updatedByStaffId: 'staff-1',
    );
    final second = await useCase(
      branchId: 'branch-1',
      channel: OrderChannel.delivery,
      acceptanceMode: ChannelAcceptanceMode.automatic,
      updatedByStaffId: 'staff-1',
    );

    expect(second.revision, 2);
    final history =
        await policyRepository.findHistory('branch-1', OrderChannel.delivery);
    expect(history, hasLength(2));
  });
}
