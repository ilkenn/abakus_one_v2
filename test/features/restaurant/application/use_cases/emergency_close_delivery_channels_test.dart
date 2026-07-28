import 'package:abakus_one_v2/core/errors/business_rule_violation.dart';
import 'package:abakus_one_v2/features/pos/domain/authorization/authorization_result.dart';
import 'package:abakus_one_v2/features/restaurant/application/use_cases/emergency_close_delivery_channels.dart';
import 'package:abakus_one_v2/features/restaurant/data/channel_operation_policy_repository.dart';
import 'package:abakus_one_v2/features/restaurant/data/restaurant_operations_audit_entry_repository.dart';
import 'package:abakus_one_v2/features/restaurant/domain/audit/restaurant_operations_audit_event_type.dart';
import 'package:abakus_one_v2/features/restaurant/domain/models/channel_operational_state.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../pos/test_support/fake_clock.dart';
import '../../../pos/test_support/fake_pos_authorization_policy.dart';

void main() {
  test('sets the delivery channel to emergencyClosed and logs an audit entry',
      () async {
    final policyRepository = InMemoryChannelOperationPolicyRepository();
    final auditRepository = InMemoryRestaurantOperationsAuditEntryRepository();
    final useCase = EmergencyCloseDeliveryChannels(
      clock: FakeClock(DateTime(2026, 7, 29)),
      authorizationPolicy:
          FakePosAuthorizationPolicy(const AuthorizationResult(granted: true)),
      policyRepository: policyRepository,
      auditRepository: auditRepository,
    );

    final result = await useCase(
      branchId: 'branch-1',
      reason: 'Kurye eksikliği',
      performedByStaffId: 'staff-1',
    );

    expect(result.operationalState, ChannelOperationalState.emergencyClosed);
    final events = await auditRepository.findByBranchId('branch-1');
    expect(events.single.type,
        RestaurantOperationsAuditEventType.emergencyChannelClosure);
  });

  test('throws AuthorizationDeniedViolation when the policy denies it',
      () async {
    final useCase = EmergencyCloseDeliveryChannels(
      clock: FakeClock(DateTime(2026, 7, 29)),
      authorizationPolicy: FakePosAuthorizationPolicy(
          const AuthorizationResult(granted: false, reason: 'Yetkisiz')),
      policyRepository: InMemoryChannelOperationPolicyRepository(),
      auditRepository: InMemoryRestaurantOperationsAuditEntryRepository(),
    );

    expect(
      () => useCase(
        branchId: 'branch-1',
        reason: 'Kurye eksikliği',
        performedByStaffId: 'staff-1',
      ),
      throwsA(isA<AuthorizationDeniedViolation>()),
    );
  });
}
