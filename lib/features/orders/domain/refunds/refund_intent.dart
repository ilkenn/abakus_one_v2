import '../../../../shared/models/money.dart';
import '../models/order_id.dart';
import 'refund_type.dart';

/// A request to refund some or all of an order's already-settled payment —
/// **domain/application foundation only this sprint, no UI**
/// (`docs/decisions.md` ADR-012). Distinct from `PaymentVoid` (which
/// corrects a mistake made while *recording* a payment) — a refund
/// reverses money after the fact for an otherwise-correctly-recorded
/// payment.
///
/// [amount] is validated against the order's refundable balance by
/// [RefundCalculator], not by this class itself — a plain value object,
/// same shape-only role `PaymentSplit`/`PaymentVoid` play.
class RefundIntent {
  const RefundIntent({
    required this.id,
    required this.orderId,
    required this.paymentSessionId,
    required this.refundType,
    required this.amount,
    required this.reason,
    required this.requestedByStaffId,
    required this.requestedAt,
  });

  final String id;
  final OrderId orderId;
  final String paymentSessionId;
  final RefundType refundType;
  final Money amount;
  final String reason;

  /// Always externally supplied — never generated or guessed.
  final String requestedByStaffId;
  final DateTime requestedAt;
}
