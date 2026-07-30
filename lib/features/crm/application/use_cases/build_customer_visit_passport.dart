import '../../../../core/utils/clock.dart';
import '../../data/customer_reward_grant_repository.dart';
import '../../data/customer_visit_repository.dart';
import '../../data/visit_reward_rule_repository.dart';
import '../../domain/rewards/visit_reward_rule.dart';
import '../../domain/visits/customer_visit_passport.dart';

/// Assembles one customer's [CustomerVisitPassport] for one branch —
/// Sprint 5D. A pure read-model builder: no I/O beyond the repository
/// reads it needs, no authorization check (matches
/// `BuildCourierLiveStatus`'s established precedent — screen
/// reachability is the access gate).
class BuildCustomerVisitPassport {
  const BuildCustomerVisitPassport({
    required Clock clock,
    required CustomerVisitRepository visitRepository,
    required VisitRewardRuleRepository ruleRepository,
    required CustomerRewardGrantRepository grantRepository,
  })  : _clock = clock,
        _visitRepository = visitRepository,
        _ruleRepository = ruleRepository,
        _grantRepository = grantRepository;

  final Clock _clock;
  final CustomerVisitRepository _visitRepository;
  final VisitRewardRuleRepository _ruleRepository;
  final CustomerRewardGrantRepository _grantRepository;

  Future<CustomerVisitPassport> call({
    required String customerId,
    required String branchId,
  }) async {
    final now = _clock.now();
    final visits = await _visitRepository.findByCustomerId(customerId);
    final totalVisitCount = visits.length;

    final allRules = await _ruleRepository.findAll();
    final eligibleRules = allRules
        .where((r) =>
            r.isActive &&
            r.appliesToBranch(branchId) &&
            r.isWithinCampaignWindow(now))
        .toList()
      ..sort((a, b) => a.requiredVisitCount.compareTo(b.requiredVisitCount));

    final completedRewards = eligibleRules
        .where((r) => totalVisitCount >= r.requiredVisitCount)
        .toList();

    VisitRewardRule? nextReward;
    for (final rule in eligibleRules) {
      if (totalVisitCount < rule.requiredVisitCount) {
        nextReward = rule;
        break;
      }
    }

    final rewardHistory = await _grantRepository.findByCustomerId(customerId);

    return CustomerVisitPassport(
      customerId: customerId,
      totalVisitCount: totalVisitCount,
      nextReward: nextReward,
      completedRewards: completedRewards,
      rewardHistory: rewardHistory,
      generatedAt: now,
    );
  }
}
