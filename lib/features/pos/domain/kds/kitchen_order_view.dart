import '../../../orders/domain/models/order_id.dart';
import 'kitchen_line_status.dart';
import 'kitchen_work_item.dart';

/// A read-only, per-line progress summary within a [KitchenOrderView] —
/// **a computed DTO, never persisted** (mirrors `KitchenDelayState`'s
/// "always fresh, never stored" reasoning). Built directly from a
/// [KitchenWorkItem]; carries no product/ingredient data of its own (that
/// still lives on the source `KitchenTicketLine`, read separately by a
/// screen when needed).
class KitchenLineProgress {
  const KitchenLineProgress({
    required this.workItemId,
    required this.kitchenTicketLineId,
    required this.status,
    required this.quantity,
    required this.readyQuantity,
  });

  final String workItemId;
  final String kitchenTicketLineId;
  final KitchenLineStatus status;
  final int quantity;
  final int readyQuantity;

  bool get isFullyReady => readyQuantity >= quantity;
}

/// A per-order kitchen-readiness projection — **computed on read, never
/// persisted as a second source of truth**. Order-level readiness is
/// always *derived* from every one of the order's [KitchenWorkItem]s
/// being [KitchenLineStatus.ready] (or a terminal non-blocking state) —
/// never a separately-stored flag that could disagree with the lines it
/// summarizes (the same "order-ready is derived, not a conflicting second
/// truth" rule `KitchenTicket.orderReadyAt`/`isFullyReady` already
/// enforces for Sprint 3D's simpler tracking; this view is additive on
/// top of it, not a replacement).
class KitchenOrderView {
  const KitchenOrderView({
    required this.orderId,
    required this.kitchenTicketId,
    required this.lines,
    required this.isFullyReady,
  });

  final OrderId orderId;
  final String kitchenTicketId;
  final List<KitchenLineProgress> lines;

  /// `true` once every non-cancelled, non-unavailable line has reached
  /// [KitchenLineStatus.ready] — a cancelled/unavailable line never blocks
  /// order-level readiness, since the kitchen has nothing further to do
  /// for it.
  final bool isFullyReady;

  static bool _blocksReadiness(KitchenLineStatus status) {
    return status != KitchenLineStatus.ready &&
        status != KitchenLineStatus.cancelled &&
        status != KitchenLineStatus.unavailable;
  }

  /// Builds the view from already-loaded work items for one ticket — pure,
  /// no I/O, mirrors `ExpeditorProjectionBuilder`'s shape exactly.
  factory KitchenOrderView.build({
    required OrderId orderId,
    required String kitchenTicketId,
    required List<KitchenWorkItem> workItems,
  }) {
    final lines = [
      for (final item in workItems)
        KitchenLineProgress(
          workItemId: item.id,
          kitchenTicketLineId: item.kitchenTicketLineId,
          status: item.status,
          quantity: item.quantity,
          readyQuantity: item.readyQuantity,
        ),
    ];
    final isFullyReady =
        lines.isNotEmpty && !lines.any((l) => _blocksReadiness(l.status));
    return KitchenOrderView(
      orderId: orderId,
      kitchenTicketId: kitchenTicketId,
      lines: lines,
      isFullyReady: isFullyReady,
    );
  }
}
