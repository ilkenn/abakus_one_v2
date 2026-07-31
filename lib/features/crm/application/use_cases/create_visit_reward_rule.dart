import '../../../../core/errors/business_rule_violation.dart';
import '../../../pos/domain/authorization/pos_authorization_policy.dart';
import '../../../pos/domain/authorization/pos_authorized_action.dart';
import '../../data/crm_audit_entry_repository.dart';
import '../../data/visit_reward_rule_repository.dart';
import '../../domain/audit/crm_audit_entry.dart';
import '../../domain/audit/crm_audit_event_type.dart';
import '../../domain/rewards/reward_type.dart';
import '../../domain/rewards/visit_reward_config.dart';
import '../../domain/rewards/visit_reward_rule.dart';
import '../identity/visit_reward_rule_id_generator.dart';

/// An administrator defines a new "reward after X visits" rule —
/// manager-only ([PosAuthorizedAction.manageVisitRewardRules]).
///
/// **Sprint 5E**: audited via [CrmAuditEntry] (`docs/decisions.md`
/// ADR-022).
class CreateVisitRewardRule {
  const CreateVisitRewardRule({
    required PosAuthorizationPolicy authorizationPolicy,
    required VisitRewardRuleIdGenerator idGenerator,
    required VisitRewardRuleRepository repository,
    required CrmAuditEntryRepository auditRepository,
  })  : _authorizationPolicy = authorizationPolicy,
        _idGenerator = idGenerator,
        _repository = repository,
        _auditRepository = auditRepository;

  final PosAuthorizationPolicy _authorizationPolicy;
  final VisitRewardRuleIdGenerator _idGenerator;
  final VisitRewardRuleRepository _repository;
  final CrmAuditEntryRepository _auditRepository;

  Future<VisitRewardRule> call({
    required int requiredVisitCount,
    required RewardType rewardType,
    required VisitRewardConfig rewardConfig,
    bool isActive = true,
    DateTime? campaignStartDate,
    DateTime? campaignEndDate,
    List<String> branchIds = const [],
    required String performedByStaffId,
    required DateTime createdAt,
  }) async {
    const action = PosAuthorizedAction.manageVisitRewardRules;
    final authResult = await _authorizationPolicy.authorize(
      action: action,
      actorStaffId: performedByStaffId,
    );
    if (!authResult.granted) {
      throw AuthorizationDeniedViolation(actionName: action.name);
    }

    if (requiredVisitCount <= 0) {
      throw InvalidVisitRewardRuleViolation(
        reason: 'requiredVisitCount must be positive, got '
            '$requiredVisitCount',
      );
    }

    final rule = VisitRewardRule(
      id: _idGenerator.nextRuleId(),
      requiredVisitCount: requiredVisitCount,
      rewardType: rewardType,
      rewardConfig: rewardConfig,
      isActive: isActive,
      campaignStartDate: campaignStartDate,
      campaignEndDate: campaignEndDate,
      branchIds: branchIds,
      createdByStaffId: performedByStaffId,
      createdAt: createdAt,
      revision: 1,
    );
    await _repository.save(rule);

    await _auditRepository.appendEvent(CrmAuditEntry(
      id: '${rule.id}-audit-created',
      actorId: performedByStaffId,
      type: CrmAuditEventType.visitRewardRuleCreated,
      description: 'Visit reward rule created '
          '(requiredVisitCount: $requiredVisitCount, '
          'rewardType: ${rewardType.name})',
      targetEntityId: rule.id,
      newStateName: isActive ? 'active' : 'inactive',
      timestamp: createdAt,
    ));

    return rule;
  }
}
