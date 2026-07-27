import '../../../../core/errors/business_rule_violation.dart';
import '../models/order_id.dart';
import '../models/order_number.dart';
import '../pricing/price_breakdown.dart';
import 'foreign_currency_equivalent.dart';
import 'payment_summary_line.dart';
import 'receipt_business_details.dart';

/// A printable/displayable receipt for one [Order] — shaped for a future
/// POS printer output, no printer integration exists this sprint.
///
/// [informationalEquivalents] are computed separately from
/// [paymentSummary]: they're always-present, TRY-total-converted-to-EUR/
/// USD estimates shown at the bottom of every receipt (approved receipt-
/// enhancement decision), independent of how the order was actually paid.
/// If the order *was* actually paid in a foreign currency, that payment's
/// own real snapshot appears in [paymentSummary] via
/// [PaymentSummaryLine.exchangeRate] instead — the two rates may differ
/// (the informational one reflects the rate at receipt-issue time; the
/// payment one is frozen from when that payment was actually made).
class Receipt {
  factory Receipt({
    required String receiptNumber,
    required OrderId orderId,
    required OrderNumber orderNumber,
    required DateTime issuedAt,
    required PriceBreakdown summary,
    List<PaymentSummaryLine> paymentSummary = const [],
    List<ForeignCurrencyEquivalent> informationalEquivalents = const [],
    ReceiptBusinessDetails businessDetails = const ReceiptBusinessDetails(),
  }) {
    if (receiptNumber.isEmpty) {
      throw const EmptyIdentifierViolation(identifierName: 'receiptNumber');
    }
    return Receipt._(
      receiptNumber: receiptNumber,
      orderId: orderId,
      orderNumber: orderNumber,
      issuedAt: issuedAt,
      summary: summary,
      paymentSummary: List.unmodifiable(paymentSummary),
      informationalEquivalents: List.unmodifiable(informationalEquivalents),
      businessDetails: businessDetails,
    );
  }

  const Receipt._({
    required this.receiptNumber,
    required this.orderId,
    required this.orderNumber,
    required this.issuedAt,
    required this.summary,
    required this.paymentSummary,
    required this.informationalEquivalents,
    required this.businessDetails,
  });

  /// Externally supplied, like [OrderId]/[OrderNumber] — no ID-generation
  /// mechanism exists in this codebase.
  final String receiptNumber;

  final OrderId orderId;
  final OrderNumber orderNumber;
  final DateTime issuedAt;

  /// Order summary and taxes — the same [PriceBreakdown] the order itself
  /// was priced with, not recomputed.
  final PriceBreakdown summary;

  final List<PaymentSummaryLine> paymentSummary;

  /// Informational EUR/USD equivalents — see this class's own doc comment.
  /// Always carries [ForeignCurrencyEquivalent.disclaimer] alongside each
  /// entry; empty when no current acceptance rate was available to
  /// compute one (never a fabricated estimate).
  final List<ForeignCurrencyEquivalent> informationalEquivalents;

  final ReceiptBusinessDetails businessDetails;
}
