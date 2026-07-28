import '../../../../core/errors/business_rule_violation.dart';
import '../../../../core/utils/clock.dart';
import '../../../orders/domain/models/order_channel.dart';
import '../../data/channel_operation_policy_repository.dart';
import '../../data/restaurant_operations_audit_entry_repository.dart';
import '../../domain/audit/restaurant_operations_audit_entry.dart';
import '../../domain/audit/restaurant_operations_audit_event_type.dart';
import '../../domain/models/channel_acceptance_mode.dart';
import '../../domain/models/channel_operation_policy.dart';
import '../../domain/models/channel_operational_state.dart';

/// Sets a branch/channel's [ChannelOperationalState] (open/busy/closed) —
/// the staff-facing "pause this channel" action. Never used to reach or
/// leave [ChannelOperationalState.emergencyClosed]; see
/// `EmergencyCloseDeliveryChannels`/`ReopenChannelAfterEmergency` for that.
///
/// Throws [InvalidChannelOperationalStateTransitionViolation] if the
/// requested transition isn't permitted by
/// [ChannelOperationalStateTransitions].
class SetChannelOperationalState {
  const SetChannelOperationalState({
    required Clock clock,
    required ChannelOperationPolicyRepository policyRepository,
    required RestaurantOperationsAuditEntryRepository auditRepository,
  })  : _clock = clock,
        _policyRepository = policyRepository,
        _auditRepository = auditRepository;

  final Clock _clock;
  final ChannelOperationPolicyRepository _policyRepository;
  final RestaurantOperationsAuditEntryRepository _auditRepository;

  Future<ChannelOperationPolicy> call({
    required String branchId,
    required OrderChannel channel,
    String? externalPlatformCode,
    required ChannelOperationalState operationalState,
    required String updatedByStaffId,
  }) async {
    if (operationalState == ChannelOperationalState.emergencyClosed) {
      throw InvalidChannelOperationalStateTransitionViolation(
        fromStateName: 'unknown',
        toStateName: operationalState.name,
      );
    }

    final now = _clock.now();
    final current = await _policyRepository.findCurrent(
      branchId,
      channel,
      externalPlatformCode: externalPlatformCode,
    );
    final fromState = current?.operationalState ?? ChannelOperationalState.open;

    if (current != null &&
        !ChannelOperationalStateTransitions.canTransition(
            fromState, operationalState)) {
      throw InvalidChannelOperationalStateTransitionViolation(
        fromStateName: fromState.name,
        toStateName: operationalState.name,
      );
    }

    final updated = current == null
        ? ChannelOperationPolicy(
            branchId: branchId,
            channel: channel,
            externalPlatformCode: externalPlatformCode,
            acceptanceMode: ChannelAcceptanceMode.automatic,
            operationalState: operationalState,
            updatedAt: now,
            updatedByStaffId: updatedByStaffId,
            revision: 1,
          )
        : current.copyWith(
            operationalState: operationalState,
            updatedAt: now,
            updatedByStaffId: updatedByStaffId,
            revision: current.revision + 1,
          );

    await _policyRepository.save(updated);
    await _auditRepository.appendEvent(
      RestaurantOperationsAuditEntry(
        id: '$branchId-${channel.name}-audit-${updated.revision}',
        branchId: branchId,
        type: RestaurantOperationsAuditEventType.channelOperationalStateChanged,
        description:
            'Operational state for ${channel.name} set to ${operationalState.name}',
        actorStaffId: updatedByStaffId,
        timestamp: now,
        previousValue: fromState.name,
        newValue: operationalState.name,
      ),
    );
    return updated;
  }
}
