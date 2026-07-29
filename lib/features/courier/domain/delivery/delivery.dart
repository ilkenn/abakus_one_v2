import '../../../orders/domain/models/order_id.dart';
import 'delivery_status.dart';

/// One delivery-channel order's courier-operations lifecycle — **never a
/// duplicate of `Order`**: references [orderId] only, never re-storing
/// order lines, pricing, or customer data. [orderId] also stands in for
/// "the package-preparation reference" — `PackagePreparation` (Sprint 3D)
/// is itself `orderId`-keyed, so no separate field is needed to reference
/// it (the same reasoning ADR-015 already used for
/// `CourierCashCollection.orderId`, extended here).
///
/// **Append-only via [revision]**: every status change produces a new
/// instance with the same [id] and an incremented [revision]. A
/// [DeliveryStatus.delivered] delivery is terminal — see
/// `DeliveryStatusTransitions`'s own doc comment.
class Delivery {
  const Delivery({
    required this.id,
    required this.orderId,
    required this.branchId,
    required this.status,
    this.courierId,
    this.currentAssignmentId,
    required this.createdAt,
    this.deliveredAt,
    required this.revision,
  });

  final String id;
  final OrderId orderId;
  final String branchId;
  final DeliveryStatus status;

  /// The courier currently responsible, if any — set once an assignment is
  /// accepted, cleared on reassignment/cancellation. Never a second source
  /// of truth for "who is assigned": always kept in sync with the latest
  /// accepted `DeliveryAssignment` by the use cases that change it.
  final String? courierId;

  final String? currentAssignmentId;
  final DateTime createdAt;
  final DateTime? deliveredAt;
  final int revision;

  bool get isTerminal => DeliveryStatusTransitions.isTerminal(status);

  Delivery copyWith({
    DeliveryStatus? status,
    String? courierId,
    bool clearCourierId = false,
    String? currentAssignmentId,
    bool clearAssignmentId = false,
    DateTime? deliveredAt,
    required int revision,
  }) {
    return Delivery(
      id: id,
      orderId: orderId,
      branchId: branchId,
      status: status ?? this.status,
      courierId: clearCourierId ? null : (courierId ?? this.courierId),
      currentAssignmentId: clearAssignmentId
          ? null
          : (currentAssignmentId ?? this.currentAssignmentId),
      createdAt: createdAt,
      deliveredAt: deliveredAt ?? this.deliveredAt,
      revision: revision,
    );
  }
}
