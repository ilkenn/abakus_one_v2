import '../../../../core/errors/business_rule_violation.dart';
import '../../../pos/domain/authorization/pos_authorization_policy.dart';
import '../../../pos/domain/authorization/pos_authorized_action.dart';
import '../../data/stock_consumption_audit_entry_repository.dart';
import '../../data/stock_consumption_channel_policy_repository.dart';
import '../../domain/stock_consumption_audit_entry.dart';
import '../../domain/stock_consumption_audit_event_type.dart';
import '../../domain/stock_consumption_channel_policy.dart';
import '../../domain/stock_consumption_timing_policy.dart';
import '../identity/stock_consumption_channel_policy_id_generator.dart';

/// Creates or updates (upserts by branch+channel) a
/// [StockConsumptionChannelPolicy] — manager+
/// (`PosAuthorizedAction.manageInventory`, reused rather than adding a
/// stock-consumption-specific configuration action), Phase 7
/// (`docs/decisions.md` ADR-024).
class SetStockConsumptionChannelPolicy {
  const SetStockConsumptionChannelPolicy({
    required PosAuthorizationPolicy authorizationPolicy,
    required StockConsumptionChannelPolicyIdGenerator idGenerator,
    required StockConsumptionChannelPolicyRepository repository,
    required StockConsumptionAuditEntryRepository auditRepository,
  })  : _authorizationPolicy = authorizationPolicy,
        _idGenerator = idGenerator,
        _repository = repository,
        _auditRepository = auditRepository;

  final PosAuthorizationPolicy _authorizationPolicy;
  final StockConsumptionChannelPolicyIdGenerator _idGenerator;
  final StockConsumptionChannelPolicyRepository _repository;
  final StockConsumptionAuditEntryRepository _auditRepository;

  Future<StockConsumptionChannelPolicy> call({
    required String organizationId,
    required String branchId,
    required String channelCode,
    required StockConsumptionTimingPolicy timingPolicy,
    required String performedByStaffId,
    required DateTime performedAt,
  }) async {
    const action = PosAuthorizedAction.manageInventory;
    final authResult = await _authorizationPolicy.authorize(
      action: action,
      actorStaffId: performedByStaffId,
    );
    if (!authResult.granted) {
      throw AuthorizationDeniedViolation(actionName: action.name);
    }

    final existing =
        await _repository.findByBranchAndChannel(branchId, channelCode);
    final policy = StockConsumptionChannelPolicy(
      id: existing?.id ?? _idGenerator.nextStockConsumptionChannelPolicyId(),
      organizationId: organizationId,
      branchId: branchId,
      channelCode: channelCode,
      timingPolicy: timingPolicy,
      createdAt: existing?.createdAt ?? performedAt,
      revision: (existing?.revision ?? 0) + 1,
    );
    await _repository.save(policy);

    await _auditRepository.appendEvent(StockConsumptionAuditEntry(
      id: '${policy.id}-audit-set-${performedAt.microsecondsSinceEpoch}',
      branchId: branchId,
      actorId: performedByStaffId,
      type: StockConsumptionAuditEventType.channelPolicySet,
      description: 'Stock consumption timing for channel "$channelCode" set '
          'to ${timingPolicy.name}',
      targetEntityId: policy.id,
      timestamp: performedAt,
    ));

    return policy;
  }
}
