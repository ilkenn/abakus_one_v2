import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../bootstrap/firebase_ready_provider.dart';
import '../../../../core/utils/clock_provider.dart';
import '../../../admin/presentation/providers/admin_dependencies_provider.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../application/use_cases/submit_customer_order.dart';
import '../../data/canonical_order_repository.dart';
import '../../data/order_firestore_client.dart';
import '../../data/orders_repository.dart';
import '../../domain/models/courier_visibility.dart';
import '../../domain/models/order_actor.dart';
import '../../domain/models/order_audit_entry.dart';
import '../../domain/models/order_cancellation.dart';
import '../../domain/models/order_model.dart';
import '../../domain/models/order_status.dart';
import '../../domain/models/order_timestamps.dart';
import '../../domain/models/order_tracking_step.dart';
import 'order_identity_provider.dart';

/// The [OrdersRepository] implementation this codebase previously seeded
/// customer order history from (3 hardcoded demo orders, identical for
/// every user). **Orphaned as of the Phase 9K canonical read-path
/// migration** (`docs/decisions.md` ADR-026, closing the Phase 9
/// adversarial review's BLOCKING finding): [OrdersNotifier] no longer
/// references this provider or [LocalOrdersRepository], and nothing else
/// in production code does either. Left in place rather than deleted, per
/// this project's standing "never delete/orphan code unilaterally" rule
/// (`CLAUDE.md` §13/§15) — reported in `docs/phase9_final_report.md` for
/// the human to decide on removal.
final ordersRepositoryProvider = Provider<OrdersRepository>((ref) {
  return const LocalOrdersRepository();
});

/// The [CanonicalOrderRepository] implementation currently in use —
/// Sprint 9D/9E (`docs/decisions.md` ADR-026). A single app-wide instance:
/// both `posOrderRepositoryProvider` (`features/pos`) and
/// `SubmitCustomerOrder`/checkout wire through this same provider, so a
/// POS-submitted and a customer-checkout-submitted [Order] land in the
/// same store — "customer/POS/QR-created orders all enter the same
/// lifecycle," verified at the storage level. As of Phase 9K, this is also
/// the **sole** read source for the customer-facing order screens (see
/// [OrdersNotifier]) — there is exactly one production truth for orders.
///
/// Gated on [firebaseReadyProvider] — Sprint 9E — mirroring every other
/// Firebase-backed provider in this codebase: [FirestoreCanonicalOrderRepository]
/// once Firebase is ready (resolving `organizationId` via the same
/// restaurant→organization closure-injection pattern
/// `RealPosAuthorizationPolicy` uses, Sprint 9B), [InMemoryCanonicalOrderRepository]
/// otherwise — including every `flutter test` run. **No release build may
/// silently persist orders in memory only**: once Firebase is ready, this
/// always resolves to the real, durable implementation.
final canonicalOrderRepositoryProvider =
    Provider<CanonicalOrderRepository>((ref) {
  final isFirebaseReady = ref.watch(firebaseReadyProvider);
  if (!isFirebaseReady) {
    return InMemoryCanonicalOrderRepository();
  }
  return FirestoreCanonicalOrderRepository(
    client: DefaultOrderFirestoreClient(),
    resolveOrganizationId: (restaurantId) async {
      final restaurant =
          await ref.read(restaurantRepositoryProvider).findById(restaurantId);
      return restaurant?.organizationId;
    },
  );
});

/// Builds and persists customer-checkout orders onto the canonical [Order]
/// aggregate — Sprint 9D (`docs/decisions.md` ADR-026). `restaurantId`/
/// `branchId` are hardcoded to the app's single seeded restaurant/branch
/// (`'restaurant-1'`/`'branch-1'`) — the same honest-placeholder pattern
/// `currentBranchIdProvider` (`features/navigation`) already documents:
/// there is no restaurant/branch *selection* UI anywhere in the customer
/// app yet, so there is nothing else this could meaningfully read from.
final submitCustomerOrderProvider = Provider<SubmitCustomerOrder>((ref) {
  return SubmitCustomerOrder(
    clock: ref.watch(clockProvider),
    identityProvider: ref.watch(orderIdentityProvider),
    repository: ref.watch(canonicalOrderRepositoryProvider),
    branchId: 'branch-1',
    restaurantId: 'restaurant-1',
  );
});

/// Customer-facing order history/tracking — Phase 9K (`docs/decisions.md`
/// ADR-026): sources exclusively from [canonicalOrderRepositoryProvider]
/// via [CanonicalOrderRepository.findByCustomerId], the same store
/// `SubmitCustomerOrder`/`SubmitPosOrder` both write to. Closes the Phase 9
/// adversarial review's one BLOCKING finding, "legacy order path remains
/// competing truth" — no production read path in this class touches
/// [ordersRepositoryProvider]/[LocalOrdersRepository] anymore.
///
/// `AsyncNotifier`, not `Notifier` — the initial load is now a real,
/// fallible Firestore call, not a synchronous in-memory return, so
/// loading/error states must be modeled explicitly (`CLAUDE.md` §4/§7)
/// rather than assumed away. `null`/signed-out sessions resolve to an
/// empty list (mirrors `features/crm`'s `currentCustomerProvider` — the
/// established shape in this codebase for "resolve real data for the
/// signed-in session, empty/`null` when signed out").
///
/// **Known, unchanged limitation, not a new regression**: none of this
/// notifier's mutator methods below (`updateScheduledTime`,
/// `updateLifecycleStatus`, `setCourierVisibleToCustomer`, `cancelOrder`,
/// `submitReview`) persist anywhere — they never did even before this
/// migration ([LocalOrdersRepository] never had a `save`/`update` method
/// at all, so these were always session-local-only). Making them durable
/// is new use-case work, out of this sprint's scope ("fix the read path,"
/// not "add order-mutation backend support").
class OrdersNotifier extends AsyncNotifier<List<OrderModel>> {
  @override
  Future<List<OrderModel>> build() async {
    final session = ref.watch(authProvider).session;
    if (session == null) return const [];

    final repository = ref.watch(canonicalOrderRepositoryProvider);
    final orders = await repository.findByCustomerId(session.uid);
    final sorted = [...orders]
      ..sort((a, b) => b.timestamps.created.compareTo(a.timestamps.created));
    return [for (final order in sorted) OrderModel.fromCanonicalOrder(order)];
  }

  /// Prepends a just-submitted order to the current session's list — the
  /// one-time write-through bridge `checkout_screen.dart` uses immediately
  /// after a real canonical submit, so the customer sees their own order
  /// without waiting on a Firestore round-trip. Awaits [future] first so a
  /// still-in-flight initial [build] can never clobber this mutation once
  /// it resolves.
  Future<void> addOrder(OrderModel order) async {
    final current = await future;
    state = AsyncData([order, ...current]);
  }

  void updateScheduledTime(String orderId, String newDateTime) {
    final current = state.value;
    if (current == null) return;
    state = AsyncData([
      for (final order in current)
        if (order.id == orderId)
          order.copyWith(scheduledDeliveryDateTime: newDateTime)
        else
          order,
    ]);
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
    final current = state.value;
    if (current == null) return false;
    final index = current.indexWhere((order) => order.id == orderId);
    if (index < 0) return false;

    final existing = current[index];
    if (!OrderStatusTransitions.canTransition(
      existing.lifecycleStatus,
      newStatus,
    )) {
      return false;
    }

    final now = DateTime.now();
    final baseTimestamps = existing.timestamps ?? OrderTimestamps(created: now);

    final updated = existing.copyWith(
      lifecycleStatus: newStatus,
      status: OrderStatusLegacyLabel.forStatus(newStatus),
      timestamps: baseTimestamps.recordedAt(newStatus, now),
      courierVisibility: newStatus == OrderStatus.outForDelivery
          ? existing.courierVisibility
          : CourierVisibility.hidden,
      auditTrail: [
        ...existing.auditTrail,
        OrderAuditEntry.statusChange(
          id: 'audit_${existing.id}_${existing.auditTrail.length + 1}',
          from: existing.lifecycleStatus,
          to: newStatus,
          actor: actor,
          at: now,
        ),
      ],
    );

    state = AsyncData([
      for (final order in current)
        if (order.id == orderId) updated else order,
    ]);
    return true;
  }

  /// Marks the courier as visible to the customer for [orderId] — the only
  /// action that may set [OrderModel.courierVisibility] to
  /// [CourierVisibility.visibleToCustomer]. Only valid while the order's
  /// [OrderModel.lifecycleStatus] is [OrderStatus.outForDelivery] (a courier
  /// can't be "on the way to this customer" before that leg has started);
  /// no-ops and returns `false` otherwise.
  bool setCourierVisibleToCustomer(String orderId) {
    final current = state.value;
    if (current == null) return false;
    final index = current.indexWhere((order) => order.id == orderId);
    if (index < 0) return false;

    final existing = current[index];
    if (existing.lifecycleStatus != OrderStatus.outForDelivery) return false;

    state = AsyncData([
      for (final order in current)
        if (order.id == orderId)
          order.copyWith(
            courierVisibility: CourierVisibility.visibleToCustomer,
          )
        else
          order,
    ]);
    return true;
  }

  void cancelOrder(String orderId, String reason, String description) {
    final current = state.value;
    if (current == null) return;
    final index = current.indexWhere((order) => order.id == orderId);
    if (index < 0) return;

    final existing = current[index];
    if (!OrderStatusTransitions.canTransition(
      existing.lifecycleStatus,
      OrderStatus.cancelled,
    )) {
      return;
    }

    final now = DateTime.now();
    final formattedNow =
        '${now.day.toString().padLeft(2, '0')}.${now.month.toString().padLeft(2, '0')}.${now.year} '
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';

    state = AsyncData([
      for (final order in current)
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
    ]);
  }

  void submitReview(String orderId, OrderModel updatedReviewFields) {
    final current = state.value;
    if (current == null) return;
    state = AsyncData([
      for (final order in current)
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
    ]);
  }
}

final ordersProvider =
    AsyncNotifierProvider<OrdersNotifier, List<OrderModel>>(() {
  return OrdersNotifier();
});

/// The customer's current active order, or `null` if none exists — also
/// `null` while [ordersProvider] is loading or has errored, matching every
/// consumer screen's existing "no active order" empty-state handling (no
/// new state needed there).
///
/// "Active" means [OrderTrackingTimeline.isActiveForCustomer] — a
/// delivered/completed/refunded/cancelled/rejected order is never active,
/// per the product rule. [ordersProvider]'s list is newest-first
/// ([OrdersNotifier.build] sorts by [OrderTimestamps.created] descending;
/// [OrdersNotifier.addOrder] also prepends), so the first match is the most
/// recently placed active order. This is the single provider both the Home
/// "Aktif Siparişin" card and `ActiveOrderScreen`'s default (no explicit
/// `orderId`) case read from.
final activeOrderProvider = Provider<OrderModel?>((ref) {
  final orders = ref.watch(ordersProvider).valueOrNull;
  if (orders == null) return null;
  for (final order in orders) {
    if (OrderTrackingTimeline.isActiveForCustomer(order.lifecycleStatus)) {
      return order;
    }
  }
  return null;
});
