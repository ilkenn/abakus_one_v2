/// What kind of correction a [PaymentCorrection] represents. Closed this
/// sprint (only [paymentMethodCorrection] is actually produced by any use
/// case — `CorrectPaymentMethod`), but [PaymentCorrection]'s shape is
/// deliberately generic enough to carry the other four without a redesign
/// once those correction flows are built (`docs/decisions.md` ADR-012):
/// this enum is the seam that lets a future `CorrectPaymentAmount`,
/// `MergeSplits`, or `SplitPayment` use case reuse the same record shape.
enum PaymentCorrectionType {
  /// The cashier recorded the wrong payment method — void the original,
  /// record a replacement under the correct method. The only type any use
  /// case actually produces this sprint (`CorrectPaymentMethod`).
  paymentMethodCorrection,

  /// The cashier recorded the wrong amount. Not implemented this sprint.
  amountCorrection,

  /// A reference/authorization code needs fixing without changing the
  /// method or amount. Not implemented this sprint.
  referenceCorrection,

  /// Two splits should be combined into one. Not implemented this sprint.
  splitMerge,

  /// One split should be divided into several. Not implemented this
  /// sprint.
  splitSplit,
}
