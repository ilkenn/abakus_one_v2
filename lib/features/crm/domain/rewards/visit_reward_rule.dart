import 'reward_type.dart';
import 'visit_reward_config.dart';

/// An administrator-defined "reward after X visits" rule — Sprint 5D's
/// Visit Rewards Engine. [requiredVisitCount] is always a configured
/// field on this type — nothing anywhere in this feature hardcodes a
/// visit threshold like "5 visits."
///
/// A mutable registry entity, mirroring `Courier`'s own shape (not
/// `CourierCompensationProfile`'s history-preserving versioning): an
/// administrator edits a rule's own current shape in place —
/// [VisitRewardRuleRepository.save] overwrites by [id] — and [revision]
/// is an optimistic-concurrency counter, not a preserved history. This is
/// safe because `CustomerRewardGrant` (the actually-earned-reward record)
/// snapshots `rewardType`/`rewardConfig` at grant time rather than
/// re-reading the rule later — a customer's already-earned reward is
/// never affected by a subsequent edit to the rule that granted it.
class VisitRewardRule {
  const VisitRewardRule({
    required this.id,
    required this.requiredVisitCount,
    required this.rewardType,
    required this.rewardConfig,
    this.isActive = true,
    this.campaignStartDate,
    this.campaignEndDate,
    this.branchIds = const [],
    required this.createdByStaffId,
    required this.createdAt,
    required this.revision,
  });

  final String id;
  final int requiredVisitCount;
  final RewardType rewardType;
  final VisitRewardConfig rewardConfig;
  final bool isActive;

  /// Both optional — `null` means "no start/end restriction" on that
  /// side.
  final DateTime? campaignStartDate;
  final DateTime? campaignEndDate;

  /// Empty means "every branch" — never a magic sentinel value.
  final List<String> branchIds;

  final String createdByStaffId;
  final DateTime createdAt;
  final int revision;

  bool appliesToBranch(String branchId) =>
      branchIds.isEmpty || branchIds.contains(branchId);

  bool isWithinCampaignWindow(DateTime now) {
    final start = campaignStartDate;
    final end = campaignEndDate;
    if (start != null && now.isBefore(start)) return false;
    if (end != null && now.isAfter(end)) return false;
    return true;
  }

  VisitRewardRule copyWith({
    int? requiredVisitCount,
    RewardType? rewardType,
    VisitRewardConfig? rewardConfig,
    bool? isActive,
    DateTime? campaignStartDate,
    bool clearCampaignStartDate = false,
    DateTime? campaignEndDate,
    bool clearCampaignEndDate = false,
    List<String>? branchIds,
    required int revision,
  }) {
    return VisitRewardRule(
      id: id,
      requiredVisitCount: requiredVisitCount ?? this.requiredVisitCount,
      rewardType: rewardType ?? this.rewardType,
      rewardConfig: rewardConfig ?? this.rewardConfig,
      isActive: isActive ?? this.isActive,
      campaignStartDate: clearCampaignStartDate
          ? null
          : (campaignStartDate ?? this.campaignStartDate),
      campaignEndDate: clearCampaignEndDate
          ? null
          : (campaignEndDate ?? this.campaignEndDate),
      branchIds: branchIds ?? this.branchIds,
      createdByStaffId: createdByStaffId,
      createdAt: createdAt,
      revision: revision,
    );
  }
}
