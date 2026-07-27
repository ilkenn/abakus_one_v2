import '../../../../shared/models/currency.dart';
import '../../../../shared/models/money.dart';
import '../../../payment/domain/models/payment_enums.dart';
import '../models/order_id.dart';
import 'payment_split.dart';

/// A payment attempt against one [Order] — split-payment-ready from the
/// start (see [splits]). **Foundation only**: no real payment provider is
/// wired behind this (the existing 5 adapters in `features/payment/data/`
/// all return [PaymentStatus.notConfigured] today, per `docs/business_rules
/// .md` BR-PAY-003), and no PAN/CVV/raw card data is ever represented here
/// or anywhere in this app (BR-PAY-004) — only [PaymentMethodType] (which
/// provider/instrument) and amounts are modeled.
///
/// Reuses the existing [PaymentStatus] (`pending, success, failed,
/// notConfigured`) rather than introducing a second, competing payment-
/// status enum.
class PaymentIntent {
  const PaymentIntent({
    required this.id,
    required this.orderId,
    required this.totalAmount,
    required this.status,
    this.splits = const [],
    required this.createdAt,
  });

  final String id;
  final OrderId orderId;

  /// Always TRY — the order's grand total this intent must settle (see
  /// `PriceBreakdown.grandTotal`). Currency conversion applies only at the
  /// [PaymentSplit] boundary; the intent's own total is never itself a
  /// foreign amount.
  final Money totalAmount;

  final PaymentStatus status;
  final List<PaymentSplit> splits;
  final DateTime createdAt;

  /// Sum of every split's [PaymentSplit.settlementAmount] (always TRY).
  Money get totalSettled {
    return splits.fold<Money>(
      Money.zero(Currency.tryLira),
      (sum, split) => sum + split.settlementAmount,
    );
  }

  /// Whether [totalSettled] covers [totalAmount] in full.
  bool get isFullySettled => totalSettled >= totalAmount;

  PaymentIntent copyWith({
    String? id,
    OrderId? orderId,
    Money? totalAmount,
    PaymentStatus? status,
    List<PaymentSplit>? splits,
    DateTime? createdAt,
  }) {
    return PaymentIntent(
      id: id ?? this.id,
      orderId: orderId ?? this.orderId,
      totalAmount: totalAmount ?? this.totalAmount,
      status: status ?? this.status,
      splits: splits ?? this.splits,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
