/// Lifecycle state of a [PaymentSession] — the POS payment-collection
/// process for one order. Distinct from `PaymentStatus`
/// (`features/payment/domain/models/payment_enums.dart`), which is a
/// single provider-adapter call's own pending/success/failed/notConfigured
/// result, not a whole collection session's state.
///
/// No `idle` value here — a [PaymentSession] object only exists once
/// collection has actually started (`StartPaymentSession`); "no active
/// session yet" is a `PaymentSessionController`-level concept, mirroring
/// how `PosOrderSessionStatus.idle` works one level up in `PosOrderSession`
/// /`PosOrderSessionController`.
enum PaymentSessionStatus {
  /// Splits are being added/removed; `remainingAmount > 0`.
  collecting,

  /// `remainingAmount == 0` — reached automatically the moment a split
  /// addition satisfies the balance, never a caller-chosen transition.
  readyToComplete,

  /// `CompletePaymentSession` is running its validation/provider-check
  /// sequence.
  completing,

  /// Every completion check passed — terminal, successful.
  completed,

  /// The cashier abandoned this session before completion — terminal, but
  /// distinct from [failed] (an abandoned session is not an error).
  cancelled,

  /// A `CompletePaymentSession` attempt failed a validation or provider
  /// check — not terminal, the cashier may retry or go back to collecting.
  failed,
}

/// The [PaymentSession] state machine: which [PaymentSessionStatus]
/// transitions are valid. Single source of truth, mirroring
/// `OrderStatusTransitions`'s existing pattern exactly.
abstract final class PaymentSessionStatusTransitions {
  PaymentSessionStatusTransitions._();

  static const Map<PaymentSessionStatus, Set<PaymentSessionStatus>> _allowed = {
    PaymentSessionStatus.collecting: {
      PaymentSessionStatus.readyToComplete,
      PaymentSessionStatus.cancelled,
    },
    PaymentSessionStatus.readyToComplete: {
      PaymentSessionStatus.collecting,
      PaymentSessionStatus.cancelled,
      PaymentSessionStatus.completing,
    },
    PaymentSessionStatus.completing: {
      PaymentSessionStatus.completed,
      PaymentSessionStatus.failed,
    },
    PaymentSessionStatus.completed: {},
    PaymentSessionStatus.cancelled: {},
    PaymentSessionStatus.failed: {
      PaymentSessionStatus.completing,
      PaymentSessionStatus.collecting,
    },
  };

  static bool canTransition(PaymentSessionStatus from, PaymentSessionStatus to) {
    return _allowed[from]?.contains(to) ?? false;
  }

  static Set<PaymentSessionStatus> allowedNextStates(PaymentSessionStatus from) {
    return _allowed[from] ?? const {};
  }
}
