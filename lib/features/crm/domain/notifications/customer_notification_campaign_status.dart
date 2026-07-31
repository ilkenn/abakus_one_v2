/// Lifecycle of a [CustomerNotificationCampaign] — Sprint 5D's CRM
/// Notification Foundation. `sent` is reachable only once a real
/// push-provider integration exists to actually deliver the campaign —
/// nothing in this feature ever sets it (see `CustomerNotificationCampaign`'s
/// own doc comment).
enum CustomerNotificationCampaignStatus {
  draft,
  scheduled,
  sent,
  cancelled,
}
