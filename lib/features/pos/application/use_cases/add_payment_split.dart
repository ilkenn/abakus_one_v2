import '../../../../core/errors/business_rule_violation.dart';
import '../../../../shared/models/exchange_rate_snapshot.dart';
import '../../../../shared/models/money.dart';
import '../../../orders/domain/payment/payment_split.dart';
import '../../../payment/domain/models/payment_method.dart';
import '../../../payment/domain/models/payment_method_snapshot.dart';
import '../../domain/models/payment_session.dart';
import '../../domain/models/payment_session_status.dart';
import '../identity/payment_split_id_generator.dart';

/// Adds one [PaymentSplit] to a [PaymentSession] — supports unlimited
/// splits across different [PaymentMethod]s (approved split-payment
/// requirement).
///
/// **Cash overpayment rule**: only a split whose method reports
/// [PaymentMethodReportingCategory.cash] may push `totalSettled` beyond
/// `totalAmount` (the excess becomes [PaymentSession.changeAmount]); any
/// other method that would do so is rejected with
/// [NonCashOverpaymentViolation] before it's ever added.
///
/// Recomputes [PaymentSessionStatus] after every add: `readyToComplete`
/// the instant `remainingAmount` reaches zero, `collecting` otherwise —
/// this is a derived, automatic transition, never a separate call.
class AddPaymentSplit {
  const AddPaymentSplit({required PaymentSplitIdGenerator splitIdGenerator})
      : _splitIdGenerator = splitIdGenerator;

  final PaymentSplitIdGenerator _splitIdGenerator;

  /// Adds a same-currency (TRY) split — the common case (cash, card,
  /// meal cards, bank transfer, gift voucher all settle directly in TRY).
  ///
  /// [transactionReference]/[authorizationCode]/[terminalId] are frozen
  /// onto the split's [PaymentMethodSnapshot] as given — a bank-transfer
  /// reference or a gift-voucher code the cashier enters at this point,
  /// not something this use case invents or validates the shape of
  /// (`CompletePaymentSession` is what enforces "required and present").
  PaymentSession call({
    required PaymentSession session,
    required PaymentMethod method,
    required Money amount,
    String? transactionReference,
    String? authorizationCode,
    String? terminalId,
  }) {
    return _apply(
      session,
      PaymentSplit.tryLira(
        id: _splitIdGenerator.nextSplitId(),
        methodSnapshot: PaymentMethodSnapshot.capture(
          method,
          transactionReference: transactionReference,
          authorizationCode: authorizationCode,
          terminalId: terminalId,
        ),
        amount: amount,
      ),
    );
  }

  /// Adds a foreign-currency split — rare in POS, but `PaymentSplit`
  /// already supports it (Phase 3 Sprint 3A); exposed here for
  /// completeness rather than left unreachable from the application layer.
  PaymentSession callForeignCurrency({
    required PaymentSession session,
    required PaymentMethod method,
    required Money amount,
    required ExchangeRateSnapshot exchangeRate,
  }) {
    return _apply(
      session,
      PaymentSplit.foreignCurrency(
        id: _splitIdGenerator.nextSplitId(),
        methodSnapshot: PaymentMethodSnapshot.capture(method),
        amount: amount,
        exchangeRate: exchangeRate,
      ),
    );
  }

  PaymentSession _apply(PaymentSession session, PaymentSplit split) {
    if (session.status != PaymentSessionStatus.collecting &&
        session.status != PaymentSessionStatus.readyToComplete) {
      throw PaymentSessionNotEditableViolation(statusName: session.status.name);
    }

    if (!split.isCash) {
      final wouldBeSettled = session.totalSettled + split.settlementAmount;
      if (wouldBeSettled > session.totalAmount) {
        throw NonCashOverpaymentViolation(
          methodId: split.methodSnapshot.paymentMethodId,
          overpaidMinorUnits: (wouldBeSettled - session.totalAmount).minorUnits,
        );
      }
    }

    final updated = session.copyWith(
      splits: [...session.splits, split],
      revision: session.revision + 1,
    );
    return updated.copyWith(
      status: updated.isFullySettled
          ? PaymentSessionStatus.readyToComplete
          : PaymentSessionStatus.collecting,
    );
  }
}
