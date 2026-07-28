/// How a [PaymentMethod] is grouped for reporting/accounting purposes —
/// independent of which specific method or provider was used.
///
/// Closed, but includes [unknown] deliberately: a [PaymentMethodSnapshot]
/// freezes whichever value was current at transaction time, so adding a
/// new category here in the future never changes what an already-frozen
/// historical snapshot reports (see `docs/decisions.md` ADR-012's
/// append-only-financial-record rationale). [unknown] exists for a future
/// seed/admin-added method that doesn't yet fit one of the named
/// categories, so reporting code always has an exhaustive value to handle
/// rather than a nullable gap.
enum PaymentMethodReportingCategory {
  cash,
  card,
  mealCard,
  bankTransfer,
  giftVoucher,
  unknown,
}
