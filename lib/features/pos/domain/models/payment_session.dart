import '../../../../shared/models/currency.dart';
import '../../../../shared/models/money.dart';
import '../../../orders/domain/models/order_id.dart';
import '../../../orders/domain/payment/payment_split.dart';
import 'payment_session_status.dart';

/// The POS payment-collection process for one [Order] — split-payment-
/// ready from the start (see [splits]).
///
/// **Renamed from `PaymentIntent`** (Phase 3 Sprint 3A) to `PaymentSession`
/// this sprint — see `docs/decisions.md` ADR-012 for why: this type's
/// actual responsibility (splits, remaining balance, change, a
/// multi-step collection lifecycle) is a *session*, not a technical
/// authorization/capture request to a provider. A `PaymentIntent`-shaped
/// concept (a single technical capture request sent to iyzico/Stripe/
/// Adyen/...) may be reintroduced later, separately, once a real provider
/// integration exists — it is not this type reused under a new name.
///
/// **Foundation only**: no real payment provider is wired behind this
/// (every `PaymentProviderAdapter` returns "not configured" today), and no
/// PAN/CVV/raw card data is ever represented here or anywhere in this app
/// — only [PaymentMethodSnapshot] (via each [PaymentSplit]) and amounts.
///
/// **Append-only**: a [PaymentSession] is never mutated in place —
/// `copyWith` always produces a new instance, and
/// `PaymentSessionRepository.save` always appends a new revision rather
/// than overwriting a previous one (see `docs/decisions.md` ADR-012).
class PaymentSession {
  const PaymentSession({
    required this.id,
    required this.orderId,
    required this.totalAmount,
    required this.status,
    this.splits = const [],
    required this.createdAt,
    required this.revision,
  });

  final String id;
  final OrderId orderId;

  /// Always TRY — the order's grand total this session must settle (see
  /// `PriceBreakdown.grandTotal`). Currency conversion applies only at the
  /// [PaymentSplit] boundary; the session's own total is never itself a
  /// foreign amount.
  final Money totalAmount;

  final PaymentSessionStatus status;
  final List<PaymentSplit> splits;
  final DateTime createdAt;

  /// Optimistic-concurrency counter — starts at 1, incremented by every
  /// mutation. `CompletePaymentSession` takes an `expectedRevision` and
  /// rejects a stale caller rather than silently overwriting a concurrent
  /// change.
  final int revision;

  /// Sum of every split's [PaymentSplit.settlementAmount] (always TRY).
  Money get totalSettled {
    return splits.fold<Money>(
      Money.zero(Currency.accountingCurrency),
      (sum, split) => sum + split.settlementAmount,
    );
  }

  /// Whether [totalSettled] covers [totalAmount] in full.
  bool get isFullySettled => totalSettled >= totalAmount;

  /// `totalAmount - totalSettled`, never negative — a cash overpay (the
  /// only category allowed to exceed the balance) shows up in
  /// [changeAmount] instead of a negative remaining figure.
  Money get remainingAmount {
    final raw = totalAmount - totalSettled;
    return raw.isNegative ? Money.zero(totalAmount.currency) : raw;
  }

  /// The excess to hand back to the customer — zero unless [totalSettled]
  /// exceeds [totalAmount], which only a cash split is ever allowed to
  /// cause (enforced by `AddPaymentSplit`, not here).
  Money get changeAmount {
    final raw = totalSettled - totalAmount;
    return raw.isNegative ? Money.zero(totalAmount.currency) : raw;
  }

  PaymentSession copyWith({
    String? id,
    OrderId? orderId,
    Money? totalAmount,
    PaymentSessionStatus? status,
    List<PaymentSplit>? splits,
    DateTime? createdAt,
    int? revision,
  }) {
    return PaymentSession(
      id: id ?? this.id,
      orderId: orderId ?? this.orderId,
      totalAmount: totalAmount ?? this.totalAmount,
      status: status ?? this.status,
      splits: splits ?? this.splits,
      createdAt: createdAt ?? this.createdAt,
      revision: revision ?? this.revision,
    );
  }
}
