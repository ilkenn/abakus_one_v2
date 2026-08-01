import '../../../courier/domain/health/courier_operation_health.dart';

/// A read-only aggregation of real, already-available data for the
/// Admin Overview — Phase 6E (`docs/decisions.md` ADR-023). Every field
/// here maps to a genuine repository query; nothing is a fabricated
/// metric. Fields the app has no real data source for yet (open orders,
/// delayed-kitchen-work count independent of courier health, open cash
/// sessions) are deliberately absent — see `BuildAdminOverviewSnapshot`'s
/// own doc comment for the honest accounting.
class AdminOverviewSnapshot {
  const AdminOverviewSnapshot({
    required this.activeBranchCount,
    required this.waitingDeliveryCount,
    required this.activeCourierCount,
    required this.unresolvedFeedbackCount,
    required this.pendingSurveyCount,
    required this.pendingCampaignCount,
    required this.operationHealth,
    required this.recentCriticalAuditDescriptions,
    required this.generatedAt,
  });

  final int activeBranchCount;
  final int waitingDeliveryCount;
  final int activeCourierCount;
  final int unresolvedFeedbackCount;
  final int pendingSurveyCount;
  final int pendingCampaignCount;

  /// A green/no-active-deliveries result is a genuine computed outcome
  /// from `BuildCourierOperationHealth`, not a fabricated "all clear."
  final CourierOperationHealth operationHealth;

  /// The most recent admin audit entries' descriptions, most recent
  /// first — capped, not a full history dump.
  final List<String> recentCriticalAuditDescriptions;

  final DateTime generatedAt;
}
