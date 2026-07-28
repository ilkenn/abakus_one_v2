/// The kind of cash-management event a [CashAuditEntry] records.
enum CashAuditEventType {
  drawerOpened,
  drawerClosed,
  movementAdded,
  movementReversed,
  countSubmitted,
  approvalGranted,
  approvalRejected,
  varianceAccepted,
  manualAdjustment,
}
