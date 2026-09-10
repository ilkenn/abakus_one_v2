import 'consortium_settlement_status.dart';

/// AP-6 Sprint 3 — a single delivery-fee ledger entry owed to/from an
/// external consortium merchant, auto-created by
/// `advanceDeliveryOrderStatus.ts`'s completion hook the moment a
/// consortium order (`Order.merchantId` set) reaches
/// `OrderStatus.completed`. The basis for a future end-of-day inter-business
/// reconciliation report (not built this sprint — see
/// `registerConsortiumOrder.ts`'s own doc comment for the explicit scope
/// boundary).
///
/// Mirrors `PaymentSettlementRecord`'s own flat shape
/// (`lib/features/payment_hub/domain/payment_settlement_record.dart`) —
/// the right structural precedent for a small, auto-generated ledger entry
/// — rather than the much heavier, still-100%-in-memory
/// `CourierSettlementSession` family (`lib/features/pos/domain/
/// courier_settlement/`), which solves a different problem (a courier's own
/// cash-on-hand reconciliation with our branch, not an inter-business fee
/// ledger).
class ConsortiumDeliverySettlement {
  const ConsortiumDeliverySettlement({
    required this.id,
    required this.merchantId,
    required this.merchantName,
    required this.orderId,
    required this.courierId,
    required this.branchId,
    required this.deliveryFeeMinorUnits,
    this.status = ConsortiumSettlementStatus.pending,
    required this.createdAt,
    this.settledAt,
    this.revision = 1,
  });

  final String id;
  final String merchantId;
  final String merchantName;
  final String orderId;

  /// The courier who carried the order at the moment it completed —
  /// `null` if the order somehow completed with no courier ever assigned
  /// (should not happen in practice, but the field stays honestly nullable
  /// rather than assuming).
  final String? courierId;

  final String branchId;

  /// The exact fee captured once at registration
  /// (`Order.consortiumDeliveryFeeMinorUnits`), copied verbatim — never
  /// recomputed here. Minor units, matching every other monetary amount in
  /// this codebase.
  final int deliveryFeeMinorUnits;

  final ConsortiumSettlementStatus status;
  final DateTime createdAt;
  final DateTime? settledAt;
  final int revision;

  ConsortiumDeliverySettlement copyWith({
    ConsortiumSettlementStatus? status,
    DateTime? settledAt,
    required int revision,
  }) {
    return ConsortiumDeliverySettlement(
      id: id,
      merchantId: merchantId,
      merchantName: merchantName,
      orderId: orderId,
      courierId: courierId,
      branchId: branchId,
      deliveryFeeMinorUnits: deliveryFeeMinorUnits,
      status: status ?? this.status,
      createdAt: createdAt,
      settledAt: settledAt ?? this.settledAt,
      revision: revision,
    );
  }
}
