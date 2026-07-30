import '../../../../core/errors/business_rule_violation.dart';
import '../../../pos/domain/authorization/pos_authorization_policy.dart';
import '../../../pos/domain/authorization/pos_authorized_action.dart';
import '../../data/visit_reward_rule_repository.dart';
import '../../domain/rewards/visit_reward_rule.dart';

/// An administrator activates or deactivates a [VisitRewardRule] —
/// manager-only ([PosAuthorizedAction.manageVisitRewardRules]). An
/// inactive rule is excluded from `BuildCustomerVisitPassport`'s
/// "next reward"/"completed rewards" computation, but any
/// `CustomerRewardGrant` already earned under it stands unaffected
/// (grants are snapshots, never re-validated against the rule's current
/// state).
class SetVisitRewardRuleActive {
  const SetVisitRewardRuleActive({
    required PosAuthorizationPolicy authorizationPolicy,
    required VisitRewardRuleRepository repository,
  })  : _authorizationPolicy = authorizationPolicy,
        _repository = repository;

  final PosAuthorizationPolicy _authorizationPolicy;
  final VisitRewardRuleRepository _repository;

  Future<VisitRewardRule> call({
    required String ruleId,
    required bool isActive,
    required String performedByStaffId,
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
    return updated;
  }
}
