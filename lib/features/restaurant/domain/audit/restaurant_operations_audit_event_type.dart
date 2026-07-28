/// The kind of restaurant-operations event a [RestaurantOperationsAuditEntry]
/// records.
///
/// One shared audit-entry type spans floor/channel/check/package/kitchen
/// concerns (Phase 3 Sprint 3D) rather than a separate append-only
/// repository per sub-domain — unlike `PaymentSplitIdGenerator`/
/// `PosOrderLineDraftIdGenerator` (Sprint 3C), which the user explicitly
/// kept apart because they're independently *injectable* correlation ids
/// with no shared caller, these audit events are all genuinely "a critical
/// restaurant-operations action happened" — the same shape of fact, just
/// with a different `type` — so one repository is simpler without losing
/// anything (`docs/decisions.md` ADR-013).
enum RestaurantOperationsAuditEventType {
  channelAcceptanceModeChanged,
  channelOperationalStateChanged,
  emergencyChannelClosure,
  checkReopened,
  checkTransferred,
  checksMerged,
  checkSplit,
  packageCompletionOverridden,
  kitchenTicketReprinted,
}
