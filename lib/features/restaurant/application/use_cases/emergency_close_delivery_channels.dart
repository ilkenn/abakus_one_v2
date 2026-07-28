import '../../../../core/errors/business_rule_violation.dart';
import '../../../../core/utils/clock.dart';
import '../../../orders/domain/models/order_channel.dart';
import '../../../pos/domain/authorization/pos_authorization_policy.dart';
import '../../../pos/domain/authorization/pos_authorized_action.dart';
import '../../data/channel_operation_policy_repository.dart';
import '../../data/restaurant_operations_audit_entry_repository.dart';
import '../../domain/audit/restaurant_operations_audit_entry.dart';
import '../../domain/audit/restaurant_operations_audit_event_type.dart';
import '../../domain/models/channel_acceptance_mode.dart';
import '../../domain/models/channel_operation_policy.dart';
import '../../domain/models/channel_operational_state.dart';

/// Branch-wide emergency stop: moves every delivery-capable channel
/// (`OrderChannel.delivery`) at [branchId] to
/// [ChannelOperationalState.emergencyClosed] in one authorized action.
///
/// Only `OrderChannel.delivery` is affected — dine-in/takeaway/reservation
/// channels are a different operational concern and are not silently
/// closed by a delivery-specific emergency stop. Existing, already-placed
/// orders are never touched: this only affects whether a *new* order on
/// the channel is accepted going forward (`docs/business_rules.md`).
///
/// Throws [AuthorizationDeniedViolation] if the policy denies the action —
/// an emergency stop is exactly the kind of action `PosAuthorizationPolicy`
/// exists to gate (see its own doc comment: no unsafe default grant).
class EmergencyCloseDeliveryChannels {
  const EmergencyCloseDeliveryChannels({
    required Clock clock,
    required PosAuthorizationPolicy authorizationPolicy,
    required ChannelOperationPolicyRepository policyRepository,
    required RestaurantOperationsAuditEntryRepository auditRepository,
  })  : _clock = clock,
        _authorizationPolicy = authorizationPolicy,
        _policyRepository = policyRepository,
        _auditRepository = auditRepository;

  final Clock _clock;
  final PosAuthorizationPolicy _authorizationPolicy;
  final ChannelOperationPolicyRepository _policyRepository;
  final RestaurantOperationsAuditEntryRepository _auditRepository;

  Future<ChannelOperationPolicy> call({
    required String branchId,
    required String reason,
    required String performedByStaffId,
  }) async {
    final authResult = await _authorizationPolicy.authorize(
      action: PosAuthorizedAction.emergencyChannelClosure,
      actorStaffId: performedByStaffId,
      context: {'branchId': branchId},
    );
    if (!authResult.granted) {
      throw AuthorizationDeniedViolation(
        actionName: PosAuthorizedAction.emergencyChannelClosure.name,
      );
    }

    final now = _clock.now();
    final current = await _policyRepository.findCurrent(
      branchId,
      OrderChannel.delivery,
    );

    final updated = current == null
        ? ChannelOperationPolicy(
            branchId: branchId,
            channel: OrderChannel.delivery,
            acceptanceMode: ChannelAcceptanceMode.automatic,
            operationalState: ChannelOperationalState.emergencyClosed,
            updatedAt: now,
            updatedByStaffId: performedByStaffId,
            revision: 1,
          )
        : current.copyWith(
            operationalState: ChannelOperationalState.emergencyClosed,
            updatedAt: now,
            updatedByStaffId: performedByStaffId,
            revision: current.revision + 1,
          );

    await _policyRepository.save(updated);
    await _auditRepository.appendEvent(
      RestaurantOperationsAuditEntry(
        id: '$branchId-delivery-emergency-${updated.revision}',
        branchId: branchId,
        type: RestaurantOperationsAuditEventType.emergencyChannelClosure,
        description: 'Emergency delivery channel closure: $reason',
        actorStaffId: performedByStaffId,
        timestamp: now,
        previousValue: current?.operationalState.name,
        newValue: ChannelOperationalState.emergencyClosed.name,
      ),
    );
    return updated;
  }
}
