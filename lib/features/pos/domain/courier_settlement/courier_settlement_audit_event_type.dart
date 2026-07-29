/// The kind of courier-settlement event a [CourierSettlementAuditEntry]
/// records — matches Sprint 3F's brief exactly: Collection, Declaration,
/// Approval, Rejection, Adjustment, Variance Accepted, Variance Rejected,
/// Settlement Closed.
enum CourierSettlementAuditEventType {
  collectionRecorded,
  declarationSubmitted,
  approvalGranted,
  approvalRejected,
  adjustmentRecorded,
  varianceAccepted,
  varianceRejected,
  settlementClosed,
}
