import '../../../../core/errors/business_rule_violation.dart';
import '../../../pos/domain/authorization/pos_authorization_policy.dart';
import '../../../pos/domain/authorization/pos_authorized_action.dart';
import '../../data/profitability_audit_entry_repository.dart';
import '../../data/profitability_threshold_config_repository.dart';
import '../../domain/profitability_audit_entry.dart';
import '../../domain/profitability_audit_event_type.dart';
import '../../domain/profitability_threshold_config.dart';
import '../identity/profitability_threshold_config_id_generator.dart';

/// Creates or updates (upserts by `branchId`) a branch's
/// [ProfitabilityThresholdConfig] — admin-only
/// (`PosAuthorizedAction.manageCostingConfiguration`, reused rather
/// than adding a profitability-specific configuration action for the
/// same "configures financial thresholds" act), Phase 7
/// (`docs/decisions.md` ADR-024).
class SetProfitabilityThresholdConfig {
  const SetProfitabilityThresholdConfig({
    required PosAuthorizationPolicy authorizationPolicy,
    required ProfitabilityThresholdConfigIdGenerator idGenerator,
    required ProfitabilityThresholdConfigRepository repository,
    required ProfitabilityAuditEntryRepository auditRepository,
  })  : _authorizationPolicy = authorizationPolicy,
        _idGenerator = idGenerator,
        _repository = repository,
        _auditRepository = auditRepository;

  final PosAuthorizationPolicy _authorizationPolicy;
  final ProfitabilityThresholdConfigIdGenerator _idGenerator;
  final ProfitabilityThresholdConfigRepository _repository;
  final ProfitabilityAuditEntryRepository _auditRepository;

  Future<ProfitabilityThresholdConfig> call({
    required String organizationId,
    required String branchId,
    int? lowMarginBasisPointsThreshold,
    int? costSpikeBasisPointsThreshold,
    int? floorPriceMinorUnits,
    required String performedByStaffId,
    required DateTime performedAt,
  }) async {
    const action = PosAuthorizedAction.manageCostingConfiguration;
    final authResult = await _authorizationPolicy.authorize(
      action: action,
      actorStaffId: performedByStaffId,
    );
    if (!authResult.granted) {
      throw AuthorizationDeniedViolation(actionName: action.name);
    }

    final existing = await _repository.findByBranchId(branchId);
    final config = ProfitabilityThresholdConfig(
      id: existing?.id ?? _idGenerator.nextProfitabilityThresholdConfigId(),
      organizationId: organizationId,
      branchId: branchId,
      lowMarginBasisPointsThreshold: lowMarginBasisPointsThreshold,
      costSpikeBasisPointsThreshold: costSpikeBasisPointsThreshold,
      floorPriceMinorUnits: floorPriceMinorUnits,
      createdAt: existing?.createdAt ?? performedAt,
      revision: (existing?.revision ?? 0) + 1,
    );
    await _repository.save(config);

    await _auditRepository.appendEvent(ProfitabilityAuditEntry(
      id: '${config.id}-audit-set-${performedAt.microsecondsSinceEpoch}',
      organizationId: organizationId,
      actorId: performedByStaffId,
      type: ProfitabilityAuditEventType.thresholdConfigSet,
      description: 'Profitability thresholds set for branch "$branchId"',
      targetEntityId: config.id,
      timestamp: performedAt,
    ));

    return config;
  }
}
