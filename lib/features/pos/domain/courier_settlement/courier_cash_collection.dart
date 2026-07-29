import '../../../../shared/models/money.dart';
import '../../../orders/domain/models/order_id.dart';
import 'courier_collection_type.dart';

/// One immutable, append-only record of cash a courier collected (or
/// failed to collect) for one delivery — never mutated or deleted once
/// recorded, mirroring [CashMovement]'s immutability.
///
/// References [orderId] rather than a separate `Delivery` id — no
/// `Delivery` aggregate exists in this codebase; a delivery *is* an order
/// with `OrderChannel.delivery` here, the same reasoning
/// `docs/decisions.md` ADR-013 already used to keep `PackagePreparation`
/// keyed by `orderId` rather than inventing a new identity for it.
/// [paymentSessionId] links to the order's own `PaymentSession` — this
/// class never duplicates or re-derives payment data, only references it
/// (`docs/business_rules.md` BR-CASH-*'s "never duplicate financial
/// events" principle, extended to couriers).
class CourierCashCollection {
  const CourierCashCollection({
    required this.id,
    required this.settlementSessionId,
    required this.courierId,
    required this.orderId,
    required this.paymentSessionId,
    required this.collectedAmount,
    required this.collectionType,
    required this.collectedAt,
    this.notes = '',
  });

  /// Externally supplied — no id-generation mechanism lives on this class.
  final String id;

  final String settlementSessionId;
  final String courierId;
  final OrderId orderId;
  final String paymentSessionId;

  /// Always non-negative. The *actual* amount collected — never the
  /// expected/order-total amount, which [CourierCollectionType.partial]
  /// and [CourierCollectionType.failed] exist specifically to distinguish
  /// from.
  final Money collectedAmount;

  final CourierCollectionType collectionType;
  final DateTime collectedAt;
  final String notes;
}
