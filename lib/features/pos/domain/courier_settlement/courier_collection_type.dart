/// How much of an order's cash-on-delivery amount a [CourierCashCollection]
/// represents.
enum CourierCollectionType {
  /// The full amount expected for this delivery was collected.
  full,

  /// Less than the full expected amount was collected (e.g. a customer
  /// short-paid at the door). [CourierCashCollection.collectedAmount]
  /// carries the actual amount collected, never the expected one.
  partial,

  /// Nothing was collected — a failed collection attempt (e.g. the
  /// customer refused, or the delivery itself failed).
  /// [CourierCashCollection.collectedAmount] is zero.
  failed,
}
