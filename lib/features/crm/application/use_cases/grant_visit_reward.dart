import '../../data/customer_reward_grant_repository.dart';
import '../../domain/rewards/customer_reward_grant.dart';
import '../../domain/rewards/visit_reward_rule.dart';
import '../identity/customer_reward_grant_id_generator.dart';

/// Grants a [CustomerRewardGrant] for a customer reaching a
/// [VisitRewardRule]'s threshold — idempotent per customer+rule+
/// visit-count (never double-grants the same milestone). System-
/// triggered, no authorization gate (mirrors `RecordCourierEvent`'s own
/// system-triggered shape) — the authorization boundary lives on
/// *defining* a rule ([CreateVisitRewardRule]/[SetVisitRewardRuleActive]),
/// not on a customer earning what a rule already promises.
class GrantVisitReward {
  const GrantVisitReward({
    required CustomerRewardGrantIdGenerator idGenerator,
    required CustomerRewardGrantRepository repository,
  })  : _idGenerator = idGenerator,
        _repository = repository;

  final CustomerRewardGrantIdGenerator _idGenerator;
  final CustomerRewardGrantRepository _repository;

  /// Returns the new grant, or `null` if this customer already holds a
  /// grant for [rule] at this exact [visitCountAtGrant] (a no-op, not an
  /// error — the caller may safely call this speculatively every time a
  /// visit is recorded).
  Future<CustomerRewardGrant?> call({
    required String customerId,
    required VisitRewardRule rule,
    required int visitCountAtGrant,
    required DateTime grantedAt,
  }) async {
    final existingGrants = await _repository.findByCustomerId(customerId);
    final alreadyGranted = existingGrants.any(
      (g) => g.ruleId == rule.id && g.visitCountAtGrant == visitCountAtGrant,
    );
    if (alreadyGranted) return null;

    final grant = CustomerRewardGrant(
      id: _idGenerator.nextGrantId(),
      customerId: customerId,
      ruleId: rule.id,
      rewardType: rule.rewardType,
      rewardConfig: rule.rewardConfig,
      visitCountAtGrant: visitCountAtGrant,
      grantedAt: grantedAt,
    );
    await _repository.append(grant);
    return grant;
  }
}
