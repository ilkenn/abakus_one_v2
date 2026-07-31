import '../../../../core/errors/business_rule_violation.dart';
import '../../../pos/domain/authorization/pos_authorization_policy.dart';
import '../../../pos/domain/authorization/pos_authorized_action.dart';
import '../../data/crm_audit_entry_repository.dart';
import '../../data/visit_reward_rule_repository.dart';
import '../../domain/audit/crm_audit_entry.dart';
import '../../domain/audit/crm_audit_event_type.dart';
import '../../domain/rewards/visit_reward_rule.dart';

/// An administrator activates or deactivates a [VisitRewardRule] —
/// manager-only ([PosAuthorizedAction.manageVisitRewardRules]). An
/// inactive rule is excluded from `BuildCustomerVisitPassport`'s
/// "next reward"/"completed rewards" computation, but any
/// `CustomerRewardGrant` already earned under it stands unaffected
/// (grants are snapshots, never re-validated against the rule's current
/// state).
///
/// **Sprint 5E**: audited via [CrmAuditEntry] — activation and
/// deactivation are recorded as distinct
/// [CrmAuditEventType.visitRewardRuleActivated]/
/// [CrmAuditEventType.visitRewardRuleDeactivated] event types, not one
/// generic "changed" type (`docs/decisions.md` ADR-022).
class SetVisitRewardRuleActive {
  const SetVisitRewardRuleActive({
    required PosAuthorizationPolicy authorizationPolicy,
    required VisitRewardRuleRepository repository,
    required CrmAuditEntryRepository auditRepository,
  })  : _authorizationPolicy = authorizationPolicy,
        _repository = repository,
        _auditRepository = auditRepository;

  final PosAuthorizationPolicy _authorizationPolicy;
  final VisitRewardRuleRepository _repository;
  final CrmAuditEntryRepository _auditRepository;

  Future<VisitRewardRule> call({
    required String ruleId,
    required bool isActive,
    required String performedByStaffId,
    required DateTime performedAt,
  }) async {
    const action = PosAuthorizedAction.manageVisitRewardRules;
    final authResult = await _authorizationPolicy.authorize(
      action: action,
      actorStaffId: performedByStaffId,
    );
    if (!authResult.granted) {
      throw AuthorizationDeniedViolation(actionName: action.name);
    }

    final existing = await _repository.findById(ruleId);
    if (existing == null) {
      throw UnknownCrmEntityViolation(
        entityName: 'VisitRewardRule',
        id: ruleId,
      );
    }

    final updated = existing.copyWith(
      isActive: isActive,
      revision: existing.revision + 1,
    );
    await _repository.save(updated);

    await _auditRepository.appendEvent(CrmAuditEntry(
      id: '$ruleId-audit-${performedAt.microsecondsSinceEpoch}',
      actorId: performedByStaffId,
      type: isActive
          ? CrmAuditEventType.visitRewardRuleActivated
          : CrmAuditEventType.visitRewardRuleDeactivated,
      description:
          'Visit reward rule ${isActive ? 'activated' : 'deactivated'}',
      targetEntityId: ruleId,
      previousStateName: existing.isActive ? 'active' : 'inactive',
      newStateName: isActive ? 'active' : 'inactive',
      timestamp: performedAt,
    ));

    return updated;
  }
}
