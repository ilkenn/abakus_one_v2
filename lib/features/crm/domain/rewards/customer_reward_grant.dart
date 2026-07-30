import 'reward_type.dart';
import 'visit_reward_config.dart';

/// One immutable, append-only record of a reward actually earned by a
/// customer under a [VisitRewardRule] — the "completed rewards"/"reward
/// history" the Visit Passport shows. [visitCountAtGrant] plus [ruleId]
/// together are the idempotency key `GrantVisitReward` checks before
/// appending — the same customer never receives a duplicate grant for
/// reaching the same rule's threshold twice.
///
/// [rewardType]/[rewardConfig] are a **snapshot**, copied from the rule
/// at grant time — never a live re-read through [ruleId]. `VisitRewardRule`
/// is a mutable registry entity (an administrator can edit or deactivate
/// it later); without this snapshot, a later edit could silently rewrite
/// what history says a customer already received.
class CustomerRewardGrant {
  const CustomerRewardGrant({
    required this.id,
    required this.customerId,
    required this.ruleId,
    required this.rewardType,
    required this.rewardConfig,
    required this.visitCountAtGrant,
    required this.grantedAt,
  });

  final String id;
  final String customerId;
  final String ruleId;
  final RewardType rewardType;
  final VisitRewardConfig rewardConfig;
  final int visitCountAtGrant;
  final DateTime grantedAt;
}
