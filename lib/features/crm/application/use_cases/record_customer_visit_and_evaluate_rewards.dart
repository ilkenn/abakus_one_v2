import '../../../orders/domain/models/order.dart';
import '../../data/customer_visit_repository.dart';
import '../../data/visit_reward_rule_repository.dart';
import '../../domain/rewards/customer_reward_grant.dart';
import '../../domain/visits/customer_visit.dart';
import 'grant_visit_reward.dart';
import 'record_customer_visit.dart';

/// The outcome of one [RecordCustomerVisitAndEvaluateRewards] call.
class RecordCustomerVisitAndEvaluateRewardsResult {
  const RecordCustomerVisitAndEvaluateRewardsResult({
    required this.visit,
    required this.wasAlreadyRecorded,
    required this.grantedRewards,
    required this.failedRuleIds,
  });

  final CustomerVisit visit;

  /// `true` if [orderId] already had a recorded visit — [visit] is the
  /// pre-existing one, and no new visit or reward evaluation happened.
  final bool wasAlreadyRecorded;

  /// Every [CustomerRewardGrant] newly granted by this call (empty if
  /// [wasAlreadyRecorded], or if no rule's threshold was newly reached).
  final List<CustomerRewardGrant> grantedRewards;

  /// The ids of any [VisitRewardRule]s whose grant attempt threw — see
  /// this class's doc comment on why a failure here does not roll back
  /// [visit].
  final List<String> failedRuleIds;
}

/// Orchestrates the Kitchen/Delivery → Visit → Reward chain's
/// customer-facing half — Sprint 5E Part 5 (`docs/decisions.md`
/// ADR-022): records one [CustomerVisit] for a qualifying completed
/// order, then evaluates every active `VisitRewardRule` against the
/// customer's new total visit count and grants any newly-reached one via
/// [GrantVisitReward] — closing the gap where
/// `CustomerVisitPassport.completedRewards` (derived, evaluated live) and
/// `.rewardHistory` (actual grants) could otherwise silently diverge:
/// every rule this call sees as newly completed is granted in the same
/// call, not left for a future passport read to reconcile.
///
/// **In-process orchestration, not a distributed transaction.** This is
/// the one boundary that sequences visit-recording and reward-granting
/// together; there is no message queue, retry, or durability guarantee
/// beyond a single in-memory call. A future backend/event bus replacing
/// this must provide: at-least-once delivery of the triggering
/// "order completed" event, a durable outbox/idempotency table keyed by
/// `orderId` (this class approximates that with
/// [CustomerVisitRepository.findByOrderId]), and its own retry policy for
/// the reward-granting step independent of visit-recording succeeding.
///
/// **Idempotent per order**: [call]'s [orderId] is checked against
/// [CustomerVisitRepository.findByOrderId] before recording — a duplicate
/// completion event for the same order returns the already-recorded
/// visit, with no new visit and no re-evaluation, rather than erroring or
/// double-recording.
///
/// **A downstream reward-grant failure never corrupts the already-saved
/// visit**: the visit is recorded first, and only once; each eligible
/// rule's [GrantVisitReward] call is individually caught, so one rule
/// throwing (e.g. a corrupt config) still lets every other eligible rule
/// grant normally, and never un-saves the visit — "failed downstream
/// steps must not corrupt completed upstream state."
///
/// **Rules are evaluated as of [call]'s `occurredAt`**, not wall-clock
/// "now" — "reward rules must be evaluated using the configuration active
/// at the correct business moment," i.e. the moment the visit actually
/// happened, not the moment this call happens to run.
class RecordCustomerVisitAndEvaluateRewards {
  const RecordCustomerVisitAndEvaluateRewards({
    required CustomerVisitRepository visitRepository,
    required VisitRewardRuleRepository ruleRepository,
    required RecordCustomerVisit recordCustomerVisit,
    required GrantVisitReward grantVisitReward,
  })  : _visitRepository = visitRepository,
        _ruleRepository = ruleRepository,
        _recordCustomerVisit = recordCustomerVisit,
        _grantVisitReward = grantVisitReward;

  final CustomerVisitRepository _visitRepository;
  final VisitRewardRuleRepository _ruleRepository;
  final RecordCustomerVisit _recordCustomerVisit;
  final GrantVisitReward _grantVisitReward;

  Future<RecordCustomerVisitAndEvaluateRewardsResult> call({
    required String customerId,
    required String branchId,
    required String orderId,
    required DateTime occurredAt,
  }) async {
    final existing = await _visitRepository.findByOrderId(orderId);
    if (existing != null) {
      return RecordCustomerVisitAndEvaluateRewardsResult(
        visit: existing,
        wasAlreadyRecorded: true,
        grantedRewards: const [],
        failedRuleIds: const [],
      );
    }

    final visit = await _recordCustomerVisit(
      customerId: customerId,
      branchId: branchId,
      orderId: orderId,
      occurredAt: occurredAt,
    );

    final totalVisitCount =
        (await _visitRepository.findByCustomerId(customerId)).length;

    final allRules = await _ruleRepository.findAll();
    final eligibleRules = allRules.where(
      (rule) =>
          rule.isActive &&
          rule.appliesToBranch(branchId) &&
          rule.isWithinCampaignWindow(occurredAt) &&
          totalVisitCount >= rule.requiredVisitCount,
    );

    final granted = <CustomerRewardGrant>[];
    final failed = <String>[];
    for (final rule in eligibleRules) {
      try {
        final grant = await _grantVisitReward(
          customerId: customerId,
          rule: rule,
          visitCountAtGrant: totalVisitCount,
          grantedAt: occurredAt,
        );
        if (grant != null) granted.add(grant);
      } catch (_) {
        failed.add(rule.id);
      }
    }

    return RecordCustomerVisitAndEvaluateRewardsResult(
      visit: visit,
      wasAlreadyRecorded: false,
      grantedRewards: List.unmodifiable(granted),
      failedRuleIds: List.unmodifiable(failed),
    );
  }

  /// Convenience for callers that only have an [order], not an
  /// already-resolved `customerId` — resolves [Order.customerId] and
  /// skips entirely (returns `null`) rather than throwing when it is
  /// absent. "A valid order reference is required for automatic visit
  /// recording" and "missing customer mapping fails safely"
  /// (`docs/decisions.md` ADR-022): today this is the common case, since
  /// no real order-submission path populates `Order.customerId` yet — an
  /// honest, documented limitation, not silently narrowed.
  Future<RecordCustomerVisitAndEvaluateRewardsResult?> callForOrder({
    required Order order,
    required DateTime occurredAt,
  }) async {
    final customerId = order.customerId;
    if (customerId == null) return null;
    return call(
      customerId: customerId,
      branchId: order.branchId,
      orderId: order.id.value,
      occurredAt: occurredAt,
    );
  }
}
