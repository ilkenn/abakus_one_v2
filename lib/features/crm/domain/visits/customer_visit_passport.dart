import '../rewards/customer_reward_grant.dart';
import '../rewards/visit_reward_rule.dart';

/// A customer's assembled Visit Passport — Sprint 5D's "visit counter,
/// current progress, next reward, completed rewards, reward history."
/// Computed fresh on every read by `BuildCustomerVisitPassport`, never
/// persisted itself (mirrors `CourierPerformanceSnapshot`/
/// `CourierDispatchQueueSnapshot`'s "computed, never stored" discipline)
/// — always rebuildable from `CustomerVisit`/`VisitRewardRule`/
/// `CustomerRewardGrant`, which remain the actual sources of truth.
///
/// No separate "visit stamp" field exists: each `CustomerVisit` already
/// recorded *is* one stamp — [totalVisitCount] is the stamp count.
class CustomerVisitPassport {
  const CustomerVisitPassport({
    required this.customerId,
    required this.totalVisitCount,
    this.nextReward,
    required this.completedRewards,
    required this.rewardHistory,
    required this.generatedAt,
  });

  final String customerId;

  /// Every recorded visit, regardless of which rules exist — the "visit
  /// counter."
  final int totalVisitCount;

  /// The active, in-window, branch-eligible rule with the lowest
  /// `requiredVisitCount` still above [totalVisitCount] — `null` when
  /// none exists (no eligible rule configured, or every eligible rule is
  /// already reached).
  final VisitRewardRule? nextReward;

  /// Every active, in-window, branch-eligible rule whose
  /// `requiredVisitCount` has been reached by [totalVisitCount] —
  /// "completed rewards."
  final List<VisitRewardRule> completedRewards;

  /// Every reward this customer has actually been granted — "reward
  /// history." Independent of [completedRewards]: a completed threshold
  /// only becomes history once `GrantVisitReward` has actually recorded
  /// it.
  final List<CustomerRewardGrant> rewardHistory;

  final DateTime generatedAt;

  /// 0.0-1.0 progress toward [nextReward], or `null` when there is no
  /// next reward to progress toward. "Current progress."
  double? get progressRatioTowardNextReward {
    final target = nextReward?.requiredVisitCount;
    if (target == null || target <= 0) return null;
    return (totalVisitCount / target).clamp(0.0, 1.0);
  }
}
