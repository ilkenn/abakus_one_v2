/// The kind of fact one [KitchenEvent] records — every real-time-relevant
/// change in the KDS domain, including connectivity events (which never
/// produce a [KitchenAuditEntry], unlike every other value here).
enum KitchenEventType {
  workItemQueued,
  workItemAcknowledged,
  workItemPreparingStarted,
  workItemQuantityReady,
  workItemReady,
  workItemCancelled,
  workItemUnavailable,
  workItemRecalled,
  workItemResumed,

  /// AP-5 Sprint 3 — mirrors `KitchenAuditEventType.wasted`.
  workItemWasted,
  orderPreparationCompleted,
  ticketDeltaFired,
  ticketCancellationFired,
  deviceHeartbeat,
  deviceConnected,
  deviceDisconnected,
}
