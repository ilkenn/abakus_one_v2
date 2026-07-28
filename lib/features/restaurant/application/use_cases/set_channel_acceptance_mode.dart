import '../../../../core/utils/clock.dart';
import '../../../orders/domain/models/order_channel.dart';
import '../../data/channel_operation_policy_repository.dart';
import '../../data/restaurant_operations_audit_entry_repository.dart';
import '../../domain/audit/restaurant_operations_audit_entry.dart';
import '../../domain/audit/restaurant_operations_audit_event_type.dart';
import '../../domain/models/channel_acceptance_mode.dart';
import '../../domain/models/channel_operation_policy.dart';
import '../../domain/models/channel_operational_state.dart';

/// Sets a branch/channel's [ChannelAcceptanceMode] (automatic vs. manual
/// confirmation of new orders). Creates the policy at
/// [ChannelOperationalState.open] if none exists yet for this
/// branch/channel — a channel is open by default until staff explicitly
/// changes it (see `docs/business_rules.md`: platforms remain open without
/// staff reopening them every morning).
class SetChannelAcceptanceMode {
  const SetChannelAcceptanceMode({
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
    required ChannelAcceptanceMode acceptanceMode,
    required String updatedByStaffId,
  }) async {
    final now = _clock.now();
    final current = await _policyRepository.findCurrent(
      branchId,
      channel,
      externalPlatformCode: externalPlatformCode,
    );

    final updated = current == null
        ? ChannelOperationPolicy(
            branchId: branchId,
            channel: channel,
            externalPlatformCode: externalPlatformCode,
            acceptanceMode: acceptanceMode,
            operationalState: ChannelOperationalState.open,
            updatedAt: now,
            updatedByStaffId: updatedByStaffId,
            revision: 1,
          )
        : current.copyWith(
            acceptanceMode: acceptanceMode,
            updatedAt: now,
            updatedByStaffId: updatedByStaffId,
            revision: current.revision + 1,
          );

    await _policyRepository.save(updated);
    await _auditRepository.appendEvent(
      RestaurantOperationsAuditEntry(
        id: '$branchId-${channel.name}-audit-${updated.revision}',
        branchId: branchId,
        type: RestaurantOperationsAuditEventType.channelAcceptanceModeChanged,
        description:
            'Acceptance mode for ${channel.name} set to ${acceptanceMode.name}',
        actorStaffId: updatedByStaffId,
        timestamp: now,
        previousValue: current?.acceptanceMode.name,
        newValue: acceptanceMode.name,
      ),
    );
    return updated;
  }
}
