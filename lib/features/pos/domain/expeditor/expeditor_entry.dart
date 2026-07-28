import '../../../orders/domain/fulfillment/package_preparation_status.dart';
import '../../../orders/domain/models/order_id.dart';

/// One order's readiness summary for the expeditor view — a pure
/// projection over already-fired [KitchenTicket]s and (if started) the
/// order's [PackagePreparation], never its own persisted state.
class ExpeditorEntry {
  const ExpeditorEntry({
    required this.orderId,
    required this.orderNumber,
    required this.pendingLineCount,
    required this.readyLineCount,
    required this.isOrderReady,
    this.readySince,
    this.packageStatus,
  });

  final OrderId orderId;
  final String orderNumber;

  /// How many product lines, across every ticket fired for this order,
  /// are not yet marked ready.
  final int pendingLineCount;

  /// How many product lines are marked ready.
  final int readyLineCount;

  /// Whether every ticket fired for this order is fully ready.
  final bool isOrderReady;

  /// When this order became fully ready — `null` until [isOrderReady].
  /// The expeditor's "how long has this been waiting" reading is
  /// `now.difference(readySince)`.
  final DateTime? readySince;

  /// `null` if `StartPackagePreparation` hasn't run yet for this order.
  final PackagePreparationStatus? packageStatus;
}
