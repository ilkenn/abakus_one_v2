/// What kind of change a [ClosureAuditEntry] records — the closure-domain
/// counterpart of `OrderAuditChangeType`, kept as its own enum rather than
/// extending that one (`docs/decisions.md` ADR-012): these events are
/// about `OrderClosure`/`PaymentSession`, not `Order`'s own status
/// history, and `OrderAuditChangeType` is closed/exhaustive by design —
/// extending it would leak a POS-closure concern into the generic,
/// cross-channel `Order` audit shape.
enum ClosureAuditEventType {
  paymentCompleted,
  orderClosed,
  orderReopened,
  paymentVoided,
  paymentMethodCorrected,
  orderReclosed,
  duplicateReceiptRequested,
}
