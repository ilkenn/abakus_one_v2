import '../../../shared/models/money.dart';
import 'payment_settlement_status.dart';

/// A payout/settlement batch reported by a payment provider for a
/// [PaymentMerchantAccount] — Phase 8 (`docs/decisions.md` ADR-025),
/// "Merchant Account → Settlement." **Foundation only** — this is the
/// record shape a future webhook handler (Webhook Foundation, 8L)
/// would populate; "do NOT integrate providers yet" means no real
/// settlement ingestion exists this phase. [amount] uses this
/// codebase's own `Money` (integer minor units, never `double`),
/// matching every other financial amount in this codebase.
class PaymentSettlementRecord {
  const PaymentSettlementRecord({
    required this.id,
    required this.merchantAccountId,
    required this.externalSettlementId,
    required this.amount,
    this.status = PaymentSettlementStatus.received,
    required this.settledAt,
    required this.revision,
  });

  final String id;
  final String merchantAccountId;

  /// The provider's own opaque settlement/payout identifier.
  final String externalSettlementId;

  final Money amount;
  final PaymentSettlementStatus status;
  final DateTime settledAt;
  final int revision;

  PaymentSettlementRecord copyWith({
    PaymentSettlementStatus? status,
    required int revision,
  }) {
    return PaymentSettlementRecord(
      id: id,
      merchantAccountId: merchantAccountId,
      externalSettlementId: externalSettlementId,
      amount: amount,
      status: status ?? this.status,
      settledAt: settledAt,
      revision: revision,
    );
  }
}
