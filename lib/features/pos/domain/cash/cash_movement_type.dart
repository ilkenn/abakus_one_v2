/// The category of one [CashMovement].
enum CashMovementType {
  /// The starting float placed in the drawer when a session opens —
  /// always the session's first movement (see `CashOpening`'s own doc
  /// comment).
  openingFloat,
  cashSale,
  cashRefund,
  manualIn,
  manualOut,
  safeDeposit,
  pettyCash,
  expense,

  /// A correction — e.g. `ReverseCashMovement`'s offsetting entry, or
  /// `RecordCashAdjustment`'s manager-approved adjustment. Unlike every
  /// other type, its sign is caller-supplied rather than fixed by the
  /// type itself, since a correction may need to add or remove cash.
  correction,

  /// The gap between expected and actual cash recorded once a session
  /// closes with an accepted variance — see `CloseCashSession`.
  closingDifference,

  /// Cash a courier physically hands over to the drawer once their
  /// `CourierSettlement` is manager-approved (Phase 3 Sprint 3F) — always
  /// an inflow, recorded automatically by `ApproveCourierSettlement` via
  /// the existing `RecordCashMovement`, never a separate financial event.
  courierCashSettlement,
}

/// Whether [CashMovementType.amount] is always recorded as a cash inflow
/// (positive) or outflow (negative) by `RecordCashMovement` — `null` for
/// [CashMovementType.correction]/[CashMovementType.closingDifference],
/// whose sign is caller-supplied instead (see their own doc comments).
extension CashMovementTypeDirection on CashMovementType {
  bool? get isInflow {
    switch (this) {
      case CashMovementType.openingFloat:
      case CashMovementType.cashSale:
      case CashMovementType.manualIn:
      case CashMovementType.courierCashSettlement:
        return true;
      case CashMovementType.cashRefund:
      case CashMovementType.manualOut:
      case CashMovementType.safeDeposit:
      case CashMovementType.pettyCash:
      case CashMovementType.expense:
        return false;
      case CashMovementType.correction:
      case CashMovementType.closingDifference:
        return null;
    }
  }
}
