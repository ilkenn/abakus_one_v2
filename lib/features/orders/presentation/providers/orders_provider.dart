import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/orders_repository.dart';
import '../../domain/models/courier_visibility.dart';
import '../../domain/models/order_actor.dart';
import '../../domain/models/order_audit_entry.dart';
import '../../domain/models/order_cancellation.dart';
import '../../domain/models/order_model.dart';
import '../../domain/models/order_status.dart';
import '../../domain/models/order_timestamps.dart';
import '../../domain/models/order_tracking_step.dart';

/// The [OrdersRepository] implementation currently in use. A future
/// backend-backed phase overrides only this provider — nothing in
/// [OrdersNotifier] or any UI depends on [LocalOrdersRepository] directly.
final ordersRepositoryProvider = Provider<OrdersRepository>((ref) {
  return const LocalOrdersRepository();
});

class OrdersNotifier extends Notifier<List<OrderModel>> {
  @override
  List<OrderModel> build() {
    return ref.read(ordersRepositoryProvider).loadInitialOrders();
  }

  void addOrder(OrderModel order) {
    state = [order, ...state];
  }

  void updateScheduledTime(String orderId, String newDateTime) {
    state = [
      for (final order in state)
        if (order.id == orderId)
          order.copyWith(scheduledDeliveryDateTime: newDateTime)
        else
          order,
    ];
  }

  /// Moves [orderId] to [newStatus] if [OrderStatusTransitions.canTransition]
  /// allows it from the order's current [OrderModel.lifecycleStatus] —
  /// an invalid or backward transition (e.g. `preparing` →
  /// `pendingConfirmation`) is silently rejected rather than corrupting
  /// state; returns whether the transition was applied.
  ///
  /// Also records the change in [OrderModel.timestamps]/
  /// [OrderModel.auditTrail], mirrors it onto the legacy [OrderModel.status]
  /// string (see [OrderStatusLegacyLabel]) so the pre-existing
  /// `orders_screen.dart`/`order_detail_screen.dart` stay coherent, and
  /// resets [OrderModel.courierVisibility] to [CourierVisibility.hidden]
  /// unless [newStatus] is [OrderStatus.outForDelivery] — visibility must
  /// always be re-earned per the courier-visibility rule, never inherited
  /// across statuses.
  bool updateLifecycleStatus(
    String orderId,
    OrderStatus newStatus, {
    OrderActor actor = OrderActor.system,
  }) {
    final index = state.indexWhere((order) => order.id == orderId);
    if (index < 0) return false;

    final current = state[index];
    if (!OrderStatusTransitions.canTransition(
      current.lifecycleStatus,
      newStatus,
    )) {
      return false;
    }

    final now = DateTime.now();
    final baseTimestamps = current.timestamps ?? OrderTimestamps(created: now);

    final updated = current.copyWith(
      lifecycleStatus: newStatus,
      status: OrderStatusLegacyLabel.forStatus(newStatus),
      timestamps: baseTimestamps.recordedAt(newStatus, now),
      courierVisibility: newStatus == OrderStatus.outForDelivery
          ? current.courierVisibility
          : CourierVisibility.hidden,
      auditTrail: [
        ...current.auditTrail,
        OrderAuditEntry.statusChange(
          id: 'audit_${current.id}_${current.auditTrail.length + 1}',
          from: current.lifecycleStatus,
          to: newStatus,
          actor: actor,
          at: now,
        ),
      ],
    );

    state = [
      for (final order in state)
        if (order.id == orderId) updated else order,
    ];
    return true;
  }

  /// Marks the courier as visible to the customer for [orderId] — the only
  /// action that may set [OrderModel.courierVisibility] to
  /// [CourierVisibility.visibleToCustomer]. Only valid while the order's
  /// [OrderModel.lifecycleStatus] is [OrderStatus.outForDelivery] (a courier
  /// can't be "on the way to this customer" before that leg has started);
  /// no-ops and returns `false` otherwise.
  bool setCourierVisibleToCustomer(String orderId) {
    final index = state.indexWhere((order) => order.id == orderId);
    if (index < 0) return false;

    final current = state[index];
    if (current.lifecycleStatus != OrderStatus.outForDelivery) return false;

    state = [
      for (final order in state)
        if (order.id == orderId)
          order.copyWith(
            courierVisibility: CourierVisibility.visibleToCustomer,
          )
        else
          order,
    ];
    return true;
  }

  void cancelOrder(String orderId, String reason, String description) {
    final index = state.indexWhere((order) => order.id == orderId);
    if (index < 0) return;

    final current = state[index];
    if (!OrderStatusTransitions.canTransition(
      current.lifecycleStatus,
      OrderStatus.cancelled,
    )) {
      return;
    }

    final now = DateTime.now();
    final formattedNow =
        '${now.day.toString().padLeft(2, '0')}.${now.month.toString().padLeft(2, '0')}.${now.year} '
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';

    state = [
      for (final order in state)
        if (order.id == orderId)
          order.copyWith(
            status: 'İptal Edildi',
            lifecycleStatus: OrderStatus.cancelled,
            cancellationReason: reason,
            cancellationDescription: description,
            cancelledAt: formattedNow,
            cancellation: OrderCancellationInfo(
              reason: reason,
              actor: OrderActor.customer,
              timestamp: now,
            ),
            courierVisibility: CourierVisibility.hidden,
          )
        else
          order,
    ];
  }

  void submitReview(String orderId, OrderModel updatedReviewFields) {
    state = [
      for (final order in state)
        if (order.id == orderId)
          order.copyWith(
            overallRating: updatedReviewFields.overallRating,
            tasteRating: updatedReviewFields.tasteRating,
            packagingRating: updatedReviewFields.packagingRating,
            deliveryRating: updatedReviewFields.deliveryRating,
            reviewComment: updatedReviewFields.reviewComment,
            reviewedAt: '18.07.2026',
            courierRating: updatedReviewFields.courierRating,
            courierWasPolite: updatedReviewFields.courierWasPolite,
            courierWasOnTime: updatedReviewFields.courierWasOnTime,
            courierCommunicationWasGood:
                updatedReviewFields.courierCommunicationWasGood,
            packageWasHandledCarefully:
                updatedReviewFields.packageWasHandledCarefully,
            courierReviewComment: updatedReviewFields.courierReviewComment,
          )
        else
          order,
    ];
  }
}

final ordersProvider = NotifierProvider<OrdersNotifier, List<OrderModel>>(() {
  return OrdersNotifier();
});

/// The customer's current active order, or `null` if none exists.
///
/// "Active" means [OrderTrackingTimeline.isActiveForCustomer] — a
/// delivered/completed/refunded/cancelled/rejected order is never active,
/// per the product rule. [ordersProvider]'s list is newest-first
/// ([OrdersNotifier.addOrder] prepends), so the first match is the most
/// recently placed active order. This is the single provider both the Home
/// "Aktif Siparişin" card and `ActiveOrderScreen`'s default (no explicit
/// `orderId`) case read from.
final activeOrderProvider = Provider<OrderModel?>((ref) {
  final orders = ref.watch(ordersProvider);
  for (final order in orders) {
    if (OrderTrackingTimeline.isActiveForCustomer(order.lifecycleStatus)) {
      return order;
    }
  }
  return null;
});
