import 'order_channel.dart';
import 'order_status.dart';

/// One customer-facing milestone in an order's journey, as shown on the
/// Active Order Tracking progress stepper.
///
/// This is a presentation-facing **projection** of [OrderStatus] +
/// [OrderChannel] — not a competing status model. [OrderStatus] (via
/// `OrderModel.lifecycleStatus`) remains the single canonical source of
/// truth; [OrderTrackingTimeline] only describes how to read that state as
/// a customer-readable stepper, per channel.
enum OrderTrackingStep {
  /// Sipariş Alındı.
  received,

  /// Hazırlanıyor.
  preparing,

  /// Paketleniyor / Servise Hazır.
  readyForService,

  /// Kurye Yolda — delivery orders only, see [OrderTrackingTimeline.stepsFor].
  courierEnRoute,

  /// Teslim Edildi.
  delivered,
}

/// Derives the customer-facing tracking timeline from [OrderStatus] +
/// [OrderChannel] — the single place that decides which steps apply to a
/// given order and which one is currently active, so no screen hardcodes
/// that mapping itself.
abstract final class OrderTrackingTimeline {
  OrderTrackingTimeline._();

  /// The ordered steps applicable to [channel]. The courier step is
  /// deliberately omitted for dine-in/takeaway/reservation channels — only
  /// [OrderChannel.delivery] ever involves a courier leg.
  static List<OrderTrackingStep> stepsFor(OrderChannel channel) {
    return [
      OrderTrackingStep.received,
      OrderTrackingStep.preparing,
      OrderTrackingStep.readyForService,
      if (channel == OrderChannel.delivery) OrderTrackingStep.courierEnRoute,
      OrderTrackingStep.delivered,
    ];
  }

  /// The step [status] currently represents, or `null` for
  /// [OrderStatus.cancelled]/[OrderStatus.rejected] — a cancelled/rejected
  /// order has no normal progress step; the UI should render the cancelled
  /// state instead of a timeline position.
  static OrderTrackingStep? currentStepFor(OrderStatus status) {
    switch (status) {
      case OrderStatus.created:
      case OrderStatus.pendingConfirmation:
      case OrderStatus.confirmed:
        return OrderTrackingStep.received;
      case OrderStatus.preparing:
        return OrderTrackingStep.preparing;
      case OrderStatus.ready:
        return OrderTrackingStep.readyForService;
      case OrderStatus.outForDelivery:
        return OrderTrackingStep.courierEnRoute;
      case OrderStatus.served:
      case OrderStatus.completed:
      case OrderStatus.refunded:
        return OrderTrackingStep.delivered;
      case OrderStatus.cancelled:
      case OrderStatus.rejected:
        return null;
    }
  }

  /// Whether [status] is one the customer should still be actively
  /// tracking. Deliberately distinct from [OrderStatusTransitions.isTerminal]
  /// (`served`/`completed` aren't state-machine terminal — `completed` can
  /// still move to `refunded` — but from the customer's tracking-screen
  /// point of view, the delivery experience is over the moment food has
  /// been served).
  static bool isActiveForCustomer(OrderStatus status) {
    return status != OrderStatus.served &&
        status != OrderStatus.completed &&
        status != OrderStatus.refunded &&
        status != OrderStatus.cancelled &&
        status != OrderStatus.rejected;
  }

  /// Turkish customer-facing label for [step].
  static String labelFor(OrderTrackingStep step) {
    switch (step) {
      case OrderTrackingStep.received:
        return 'Sipariş Alındı';
      case OrderTrackingStep.preparing:
        return 'Hazırlanıyor';
      case OrderTrackingStep.readyForService:
        return 'Paketleniyor / Servise Hazır';
      case OrderTrackingStep.courierEnRoute:
        return 'Kurye Yolda';
      case OrderTrackingStep.delivered:
        return 'Teslim Edildi';
    }
  }
}
