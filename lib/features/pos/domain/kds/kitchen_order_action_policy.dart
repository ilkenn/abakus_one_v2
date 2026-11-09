import '../../../orders/domain/models/order_channel.dart';
import '../../../orders/domain/models/order_status.dart';

/// The single whole-order action a KDS card's footer offers for an order's
/// current status — always exactly one step along the backend's strict
/// `confirmed -> preparing -> ready -> (served | completed)` chain, never a
/// skip (every `advance*OrderStatus` callable rejects anything but the
/// exact next status).
enum KitchenOrderAction {
  /// `confirmed -> preparing` — "Hazırlanıyor".
  startPreparing,

  /// `preparing -> ready` — "Hazırlandı".
  markReady,

  /// `ready -> served` (dine-in/reservation) or `ready -> completed`
  /// (takeaway) — "Teslim Edildi".
  handOver,
}

/// 2026-11-08 — which KDS footer actions apply to an order, per channel and
/// current [OrderStatus]. Pure and side-effect free so the board/detail
/// screens never re-derive the chain themselves.
///
/// Scope decisions (confirmed with the product owner, 2026-11-08):
/// - `pendingConfirmation` orders never reach the KDS (confirm/reject stays
///   on the POS) — so there is no confirm/reject action here.
/// - "Teslim Edildi" applies to dine-in (`served`), reservation preorder
///   (`served`) and takeaway (`completed`, which triggers Boncuk earning
///   server-side). Delivery's next step after `ready` is `outForDelivery`
///   — a courier hand-off owned by the courier flow, not the kitchen.
/// - Cancel applies to every channel with a staff cancellation callable;
///   the server still enforces the escalated (manager-tier) permission for
///   takeaway/delivery once preparation has started.
/// - `dineInStaff` has no lifecycle callable at all on the backend (staff
///   dine-in orders are stored as `dineInQr`), so it gets no actions.
abstract final class KitchenOrderActionPolicy {
  static bool supportsOrderActions(OrderChannel channel) =>
      channel != OrderChannel.dineInStaff;

  /// The status "Teslim Edildi" advances a `ready` order to, or `null` when
  /// the kitchen must not hand this channel's order over itself.
  static OrderStatus? handOverTargetFor(OrderChannel channel) {
    switch (channel) {
      case OrderChannel.dineInQr:
      case OrderChannel.reservationPreorder:
        return OrderStatus.served;
      case OrderChannel.takeaway:
        return OrderStatus.completed;
      case OrderChannel.delivery:
      case OrderChannel.dineInStaff:
        return null;
    }
  }

  static KitchenOrderAction? primaryActionFor(
    OrderChannel channel,
    OrderStatus? status,
  ) {
    if (status == null || !supportsOrderActions(channel)) return null;
    switch (status) {
      case OrderStatus.confirmed:
        return KitchenOrderAction.startPreparing;
      case OrderStatus.preparing:
        return KitchenOrderAction.markReady;
      case OrderStatus.ready:
        return handOverTargetFor(channel) == null
            ? null
            : KitchenOrderAction.handOver;
      case OrderStatus.created:
      case OrderStatus.pendingConfirmation:
      case OrderStatus.outForDelivery:
      case OrderStatus.served:
      case OrderStatus.completed:
      case OrderStatus.cancelled:
      case OrderStatus.rejected:
      case OrderStatus.refunded:
      case OrderStatus.scheduled:
      case OrderStatus.readyForPickup:
        return null;
    }
  }

  /// Only the kitchen-visible, still-cancellable window — every channel's
  /// staff cancellation callable accepts `confirmed`/`preparing`/`ready`.
  static bool canCancel(OrderChannel channel, OrderStatus? status) {
    if (status == null || !supportsOrderActions(channel)) return false;
    return status == OrderStatus.confirmed ||
        status == OrderStatus.preparing ||
        status == OrderStatus.ready;
  }

  /// "Hazırlanıyor" / "Hazırlandı" / "Teslim Edildi".
  static String labelFor(KitchenOrderAction action) {
    switch (action) {
      case KitchenOrderAction.startPreparing:
        return 'Hazırlanıyor';
      case KitchenOrderAction.markReady:
        return 'Hazırlandı';
      case KitchenOrderAction.handOver:
        return 'Teslim Edildi';
    }
  }
}
