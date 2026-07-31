/// Every CRM/Loyalty mutation Sprint 5E's audit-parity fix
/// (`docs/decisions.md` ADR-022) covers — one value per [CrmAuditEntry]
/// this codebase actually writes.
enum CrmAuditEventType {
  customerCategoryChanged,
  visitRecorded,
  visitRewardRuleCreated,
  visitRewardRuleActivated,
  visitRewardRuleDeactivated,
  visitRewardGranted,
  surveyCreated,
  customerNotificationCampaignCreated,
  customerNotificationCampaignScheduled,
}
